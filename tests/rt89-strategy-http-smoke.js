function assert(condition, message) {
  if (!condition) throw new Error(message);
}

async function waitForHealth(url, attempts = 40) {
  let last = '';
  for (let i = 0; i < attempts; i++) {
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
  throw new Error(`Servidor não iniciou: ${last}`);
}

const child = new Deno.Command(Deno.execPath(), {
  args: ['run', '--allow-net', '--allow-env', 'deno/main.js'],
  stdout: 'null',
  stderr: 'null',
}).spawn();

try {
  const root = await waitForHealth('http://127.0.0.1:8000/health');
  assert(root?.strategy === true, 'Health raiz não anunciou strategy=true.');
  assert(root?.strategy_endpoint === '/api/strategy', 'Health raiz sem strategy_endpoint.');

  const healthResponse = await fetch('http://127.0.0.1:8000/api/strategy', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ action: 'health' }),
  });
  const health = await healthResponse.json();
  assert(healthResponse.status === 200, `Strategy health retornou ${healthResponse.status}.`);
  assert(health?.ok === true && health?.service === 'reino-tribal-strategy', 'Strategy health inválido.');
  assert(Array.isArray(health?.types) && health.types.length === 7, 'Strategy health não anunciou 7 tipos.');

  const catalogResponse = await fetch('http://127.0.0.1:8000/api/strategy', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ action: 'catalog' }),
  });
  const catalog = await catalogResponse.json();
  assert(catalogResponse.status === 200, `Catalog retornou ${catalogResponse.status}.`);
  assert(Array.isArray(catalog) && catalog.length === 7, 'Catalog deveria listar 7 comandos.');
  for (const expected of ['build_upgrade','recruit_units','attack','spy','support','transfer_resources','collect_deposit']) {
    assert(catalog.some((item) => item.type === expected), `Catalog sem ${expected}.`);
  }

  const preflight = await fetch('http://127.0.0.1:8000/api/strategy', {
    method: 'OPTIONS',
    headers: {
      Origin: 'https://kaalflash12.github.io',
      'Access-Control-Request-Method': 'POST',
      'Access-Control-Request-Headers': 'content-type,authorization',
    },
  });
  assert(preflight.status === 204, `Preflight deveria retornar 204, retornou ${preflight.status}.`);
  assert(preflight.headers.get('access-control-allow-origin') === 'https://kaalflash12.github.io', 'CORS não autorizou GitHub Pages.');

  console.log('RT89_STRATEGY_HTTP_SMOKE_PASS');
} finally {
  try { child.kill('SIGTERM'); } catch {}
  try { await child.status; } catch {}
}
