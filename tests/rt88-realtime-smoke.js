function assert(condition, message) {
  if (!condition) throw new Error(message);
}

async function waitForHealth(url, attempts = 40) {
  let last = '';
  for (let i = 1; i <= attempts; i++) {
    try {
      const response = await fetch(url, { cache: 'no-store' });
      const text = await response.text();
      last = `${response.status} ${text}`;
      if (response.ok) return JSON.parse(text);
    } catch (error) {
      last = String(error?.message || error);
    }
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  throw new Error(`Servidor não ficou pronto: ${last}`);
}

function waitForMessage(socket, predicate, timeoutMs = 5000) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      socket.removeEventListener('message', onMessage);
      reject(new Error('Timeout aguardando mensagem WebSocket.'));
    }, timeoutMs);

    function onMessage(event) {
      let data;
      try { data = JSON.parse(String(event.data)); }
      catch { return; }
      if (!predicate(data)) return;
      clearTimeout(timer);
      socket.removeEventListener('message', onMessage);
      resolve(data);
    }

    socket.addEventListener('message', onMessage);
  });
}

const child = new Deno.Command(Deno.execPath(), {
  args: ['run', '--allow-net', '--allow-env', 'deno/main.js'],
  stdout: 'null',
  stderr: 'null',
}).spawn();

try {
  const health = await waitForHealth('http://127.0.0.1:8000/health');
  assert(health?.ok === true, 'Health não retornou ok=true.');
  assert(health?.realtime === true, 'Health não anunciou realtime=true.');
  assert(health?.websocket === '/ws', 'Health não anunciou endpoint /ws.');

  const noUpgrade = await fetch('http://127.0.0.1:8000/ws');
  const noUpgradeBody = await noUpgrade.json();
  assert(noUpgrade.status === 426, `GET /ws sem upgrade deveria retornar 426, retornou ${noUpgrade.status}.`);
  assert(noUpgradeBody?.endpoint === '/ws', 'Resposta 426 não descreveu endpoint /ws.');

  const socket = new WebSocket('ws://127.0.0.1:8000/ws');
  const welcomePromise = waitForMessage(socket, (message) => message.type === 'System/welcome');
  await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('Timeout abrindo WebSocket.')), 5000);
    socket.addEventListener('open', () => {
      clearTimeout(timer);
      resolve();
    }, { once: true });
    socket.addEventListener('error', () => {
      clearTimeout(timer);
      reject(new Error('Falha abrindo WebSocket.'));
    }, { once: true });
  });

  const welcome = await welcomePromise;
  assert(welcome?.data?.service === 'reino-tribal-realtime', 'System/welcome com serviço incorreto.');
  assert(Array.isArray(welcome?.data?.features), 'System/welcome sem features.');
  assert(welcome.data.features.includes('Authentication/session'), 'System/welcome sem Authentication/session.');
  assert(welcome.data.features.includes('World/select'), 'System/welcome sem World/select.');

  const pongPromise = waitForMessage(socket, (message) => message.type === 'System/pong' && message.id === 'ping-1');
  socket.send(JSON.stringify({ type: 'System/ping', id: 'ping-1', data: { value: 7 } }));
  const pong = await pongPromise;
  assert(pong?.data?.echo?.value === 7, 'System/pong não preservou echo.');

  const authErrorPromise = waitForMessage(socket, (message) => message.type === 'System/error' && message.id === 'auth-empty');
  socket.send(JSON.stringify({ type: 'Authentication/session', id: 'auth-empty', data: {} }));
  const authError = await authErrorPromise;
  assert(authError?.data?.code === 'AUTH_TOKEN_REQUIRED', 'Sessão sem token não foi recusada corretamente.');

  const unknownPromise = waitForMessage(socket, (message) => message.type === 'System/error' && message.id === 'unknown-1');
  socket.send(JSON.stringify({ type: 'Foo/bar', id: 'unknown-1', data: {} }));
  const unknown = await unknownPromise;
  assert(unknown?.data?.code === 'UNKNOWN_TYPE', 'Evento desconhecido não foi recusado corretamente.');

  socket.close(1000, 'smoke complete');
  await new Promise((resolve) => setTimeout(resolve, 100));

  console.log('RT88_REALTIME_SMOKE_PASS');
} finally {
  try { child.kill('SIGTERM'); } catch {}
  try { await child.status; } catch {}
}
