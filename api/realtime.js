const PROTOCOL_VERSION = 1;
const INSTANCE_ID = crypto.randomUUID();
const CHANNEL_NAME = 'reino-tribal-realtime-v1';

const clients = new Map();
const relay = new BroadcastChannel(CHANNEL_NAME);

const DEFAULT_ALLOWED_ORIGINS = new Set([
  'https://kaalflash12.github.io',
  'http://localhost:3000',
  'http://127.0.0.1:3000',
  'http://localhost:4173',
  'http://127.0.0.1:4173',
  'http://localhost:8000',
  'http://127.0.0.1:8000',
]);

const NOTIFY_TYPES = new Set([
  'Village/changed',
  'Command/changed',
  'Report/new',
  'Chat/tribe',
  'Resources/changed',
  'Army/changed',
  'Building/changed',
  'World/changed',
]);

function responseJson(status, data) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff',
    },
  });
}

function configuredOrigins() {
  return String(process.env.RT_ALLOWED_ORIGINS || '')
    .split(',')
    .map((value) => value.trim())
    .filter(Boolean);
}

function originAllowed(request) {
  const origin = String(request.headers.get('origin') || '');
  if (!origin) return true;
  if (DEFAULT_ALLOWED_ORIGINS.has(origin)) return true;
  return configuredOrigins().includes(origin);
}

function reinoApiUrl(request) {
  const url = new URL(request.url);
  if (url.protocol === 'ws:') url.protocol = 'http:';
  if (url.protocol === 'wss:') url.protocol = 'https:';
  url.pathname = '/api/reino';
  url.search = '';
  url.hash = '';
  return url.toString();
}

async function callReino(request, token, action, data = {}) {
  const response = await fetch(reinoApiUrl(request), {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: JSON.stringify({ action, ...data }),
  });
  let body = null;
  try { body = await response.json(); }
  catch { body = { error: 'Resposta interna inválida.' }; }
  if (!response.ok) {
    const error = new Error(String(body?.error || `HTTP ${response.status}`));
    error.status = response.status;
    throw error;
  }
  return body;
}

function envelope(type, data = {}, id = null) {
  return JSON.stringify({
    type,
    ...(id != null ? { id } : {}),
    data,
    ts: Date.now(),
    protocol: PROTOCOL_VERSION,
  });
}

function send(state, type, data = {}, id = null) {
  if (!state?.socket || state.socket.readyState !== WebSocket.OPEN) return false;
  try {
    state.socket.send(envelope(type, data, id));
    return true;
  } catch {
    return false;
  }
}

function sendError(state, id, code, message, status = 400) {
  send(state, 'System/error', { code, message, status }, id);
}

function broadcastLocal(worldId, type, data, exceptConnectionId = '') {
  for (const state of clients.values()) {
    if (!state.authenticated || state.worldId !== worldId || state.id === exceptConnectionId) continue;
    send(state, type, data);
  }
}

function publishWorld(worldId, type, data, exceptConnectionId = '') {
  if (!worldId) return;
  broadcastLocal(worldId, type, data, exceptConnectionId);
  relay.postMessage({
    source_instance: INSTANCE_ID,
    world_id: worldId,
    type,
    data,
    except_connection_id: exceptConnectionId,
  });
}

relay.onmessage = (event) => {
  const message = event.data;
  if (!message || message.source_instance === INSTANCE_ID) return;
  if (!message.world_id || !message.type) return;
  broadcastLocal(
    String(message.world_id),
    String(message.type),
    message.data || {},
    String(message.except_connection_id || ''),
  );
};

async function authenticate(request, state, message) {
  const token = String(message?.data?.token || message?.data?.access_token || '').trim();
  if (!token) {
    sendError(state, message?.id, 'AUTH_TOKEN_REQUIRED', 'Token de sessão obrigatório.', 401);
    return;
  }
  try {
    const result = await callReino(request, token, 'me');
    if (!result?.user?.id) throw new Error('Sessão não retornou usuário.');
    state.token = token;
    state.user = result.user;
    state.authenticated = true;
    send(state, 'Authentication/session', {
      authenticated: true,
      user: result.user,
    }, message?.id);
  } catch (error) {
    sendError(state, message?.id, 'AUTH_FAILED', String(error?.message || 'Sessão inválida.'), Number(error?.status || 401));
  }
}

async function selectWorld(request, state, message) {
  if (!state.authenticated) {
    sendError(state, message?.id, 'AUTH_REQUIRED', 'Autentique a sessão antes de selecionar o mundo.', 401);
    return;
  }
  const worldId = String(message?.data?.world_id || '').trim();
  if (!worldId) {
    sendError(state, message?.id, 'WORLD_REQUIRED', 'world_id obrigatório.', 400);
    return;
  }
  try {
    const memberships = await callReino(request, state.token, 'memberships');
    const rows = Array.isArray(memberships) ? memberships : [];
    const membership = rows.find((row) => String(row.world_id) === worldId);
    if (!membership) {
      sendError(state, message?.id, 'WORLD_NOT_JOINED', 'Entre no mundo pela API antes de selecioná-lo no realtime.', 403);
      return;
    }

    const oldWorld = state.worldId;
    state.worldId = worldId;
    state.membership = membership;
    send(state, 'World/selected', {
      world_id: worldId,
      player_name: membership.player_name,
    }, message?.id);

    if (oldWorld && oldWorld !== worldId) {
      publishWorld(oldWorld, 'Presence/leave', {
        user_id: state.user.id,
        username: state.user.username,
      }, state.id);
    }
    publishWorld(worldId, 'Presence/join', {
      user_id: state.user.id,
      username: state.user.username,
      player_name: membership.player_name,
    }, state.id);
  } catch (error) {
    sendError(state, message?.id, 'WORLD_SELECT_FAILED', String(error?.message || 'Falha ao selecionar mundo.'), Number(error?.status || 500));
  }
}

function notifyWorld(state, message) {
  if (!state.authenticated || !state.worldId) {
    sendError(state, message?.id, 'WORLD_SESSION_REQUIRED', 'Autentique e selecione um mundo antes de publicar eventos.', 401);
    return;
  }

  const now = Date.now();
  if (now - state.lastNotifyAt < 150) {
    sendError(state, message?.id, 'RATE_LIMIT', 'Eventos enviados rápido demais.', 429);
    return;
  }
  state.lastNotifyAt = now;

  const eventType = String(message?.data?.event_type || '').trim();
  if (!NOTIFY_TYPES.has(eventType)) {
    sendError(state, message?.id, 'EVENT_NOT_ALLOWED', 'Tipo de evento realtime não autorizado.', 400);
    return;
  }

  const hint = message?.data?.hint && typeof message.data.hint === 'object'
    ? message.data.hint
    : {};
  const data = {
    world_id: state.worldId,
    source_user_id: state.user.id,
    source_username: state.user.username,
    hint,
    authoritative: false,
  };
  publishWorld(state.worldId, eventType, data, state.id);
  send(state, 'Event/accepted', { event_type: eventType }, message?.id);
}

function handleMessage(request, state, raw) {
  let message;
  try {
    message = JSON.parse(String(raw));
  } catch {
    sendError(state, null, 'INVALID_JSON', 'Mensagem realtime precisa ser JSON válido.', 400);
    return;
  }

  const type = String(message?.type || '').trim();
  if (!type) {
    sendError(state, message?.id, 'TYPE_REQUIRED', 'Campo type obrigatório.', 400);
    return;
  }

  if (type === 'System/ping') {
    send(state, 'System/pong', { echo: message?.data ?? null }, message?.id);
    return;
  }
  if (type === 'Authentication/session') {
    authenticate(request, state, message).catch((error) => {
      sendError(state, message?.id, 'AUTH_FAILED', String(error?.message || error), 500);
    });
    return;
  }
  if (type === 'World/select') {
    selectWorld(request, state, message).catch((error) => {
      sendError(state, message?.id, 'WORLD_SELECT_FAILED', String(error?.message || error), 500);
    });
    return;
  }
  if (type === 'Realtime/subscribe') {
    if (!state.authenticated || !state.worldId) {
      sendError(state, message?.id, 'WORLD_SESSION_REQUIRED', 'Autentique e selecione um mundo primeiro.', 401);
      return;
    }
    send(state, 'Realtime/subscribed', {
      world_id: state.worldId,
      events: [...NOTIFY_TYPES],
    }, message?.id);
    return;
  }
  if (type === 'Event/notify') {
    notifyWorld(state, message);
    return;
  }

  sendError(state, message?.id, 'UNKNOWN_TYPE', `Evento realtime desconhecido: ${type}`, 400);
}

export default function realtimeHandler(request) {
  if (!originAllowed(request)) {
    return responseJson(403, { error: 'Origem não autorizada para realtime.' });
  }
  if (String(request.headers.get('upgrade') || '').toLowerCase() !== 'websocket') {
    return responseJson(426, {
      error: 'Esta rota exige WebSocket.',
      endpoint: '/ws',
      protocol: PROTOCOL_VERSION,
    });
  }

  const { socket, response } = Deno.upgradeWebSocket(request, { idleTimeout: 45 });
  const state = {
    id: crypto.randomUUID(),
    socket,
    authenticated: false,
    token: '',
    user: null,
    worldId: '',
    membership: null,
    lastNotifyAt: 0,
  };

  socket.onopen = () => {
    clients.set(state.id, state);
    send(state, 'System/welcome', {
      service: 'reino-tribal-realtime',
      transport: 'websocket',
      protocol: PROTOCOL_VERSION,
      connection_id: state.id,
      features: [
        'Authentication/session',
        'World/select',
        'Realtime/subscribe',
        'Event/notify',
        'System/ping',
      ],
    });
  };

  socket.onmessage = (event) => handleMessage(request, state, event.data);

  socket.onerror = () => {
    clients.delete(state.id);
  };

  socket.onclose = () => {
    clients.delete(state.id);
    if (state.authenticated && state.worldId && state.user) {
      publishWorld(state.worldId, 'Presence/leave', {
        user_id: state.user.id,
        username: state.user.username,
      }, state.id);
    }
  };

  return response;
}
