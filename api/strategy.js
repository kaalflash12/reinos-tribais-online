import { connect } from '@tursodatabase/serverless';
import { createHash, randomUUID } from 'node:crypto';

const MAX_PAYLOAD_BYTES = 32_000;
const MAX_RESULT_BYTES = 32_000;
const MAX_IDEMPOTENCY_LENGTH = 128;
const MAX_SCHEDULE_DAYS = 30;
const STRATEGY_TYPES = Object.freeze({
  build_upgrade: Object.freeze({
    required: ['village_id', 'building', 'target_level'],
    event: 'Building/changed',
    label: 'Evolução de edifício',
  }),
  recruit_units: Object.freeze({
    required: ['village_id', 'unit', 'quantity'],
    event: 'Army/changed',
    label: 'Recrutamento',
  }),
  attack: Object.freeze({
    required: ['village_id', 'target_village_id', 'troops'],
    event: 'Command/changed',
    label: 'Ataque',
  }),
  spy: Object.freeze({
    required: ['village_id', 'target_village_id', 'spies'],
    event: 'Command/changed',
    label: 'Espionagem',
  }),
  support: Object.freeze({
    required: ['village_id', 'target_village_id', 'troops'],
    event: 'Command/changed',
    label: 'Apoio militar',
  }),
  transfer_resources: Object.freeze({
    required: ['village_id', 'target_village_id', 'resources'],
    event: 'Resources/changed',
    label: 'Transporte de recursos',
  }),
  collect_deposit: Object.freeze({
    required: ['village_id', 'deposit_id'],
    event: 'Resources/changed',
    label: 'Coleta de depósito',
  }),
});

const COMMAND_STATUSES = new Set(['queued', 'ready', 'completed', 'cancelled', 'failed']);
let rawConnection;
let connection;
let schemaPromise;

function configured() {
  return Boolean(process.env.TURSO_DATABASE_URL && process.env.TURSO_AUTH_TOKEN);
}

function wrapConnection(raw) {
  return {
    prepare(sql) {
      let statementPromise;
      const statement = () => statementPromise ||= Promise.resolve(raw.prepare(sql));
      return {
        get: async (...args) => (await statement()).get(...args),
        all: async (...args) => (await statement()).all(...args),
        run: async (...args) => (await statement()).run(...args),
      };
    },
    batch: (...args) => raw.batch(...args),
  };
}

function db() {
  if (!configured()) throw Object.assign(new Error('Turso não configurado no servidor.'), { status: 503 });
  if (!connection) {
    rawConnection = connect({
      url: process.env.TURSO_DATABASE_URL,
      authToken: process.env.TURSO_AUTH_TOKEN,
    });
    connection = wrapConnection(rawConnection);
  }
  return connection;
}

function nowIso() {
  return new Date().toISOString();
}

function sha256(value) {
  return createHash('sha256').update(String(value)).digest('hex');
}

function parseJson(value, fallback = null) {
  try {
    if (value == null || value === '') return fallback;
    return typeof value === 'string' ? JSON.parse(value) : value;
  } catch {
    return fallback;
  }
}

function jsonBytes(value) {
  return new TextEncoder().encode(JSON.stringify(value ?? null)).byteLength;
}

function cleanId(value, max = 96) {
  return String(value || '').trim().slice(0, max);
}

function positiveInteger(value, label, max = 1_000_000) {
  const number = Number(value);
  if (!Number.isInteger(number) || number <= 0 || number > max) {
    throw Object.assign(new Error(`${label} precisa ser inteiro entre 1 e ${max}.`), { status: 400 });
  }
  return number;
}

function nonNegativeNumber(value, label, max = 1_000_000_000) {
  const number = Number(value);
  if (!Number.isFinite(number) || number < 0 || number > max) {
    throw Object.assign(new Error(`${label} precisa estar entre 0 e ${max}.`), { status: 400 });
  }
  return number;
}

function normalizeTroops(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw Object.assign(new Error('troops precisa ser um objeto de unidades.'), { status: 400 });
  }
  const normalized = {};
  for (const [unit, quantity] of Object.entries(value)) {
    const key = cleanId(unit, 48);
    if (!key) continue;
    const qty = Number(quantity);
    if (!Number.isInteger(qty) || qty < 0 || qty > 10_000_000) {
      throw Object.assign(new Error(`Quantidade inválida para unidade ${key}.`), { status: 400 });
    }
    if (qty > 0) normalized[key] = qty;
  }
  if (!Object.keys(normalized).length) {
    throw Object.assign(new Error('O comando precisa conter pelo menos uma unidade.'), { status: 400 });
  }
  return normalized;
}

function normalizeResources(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw Object.assign(new Error('resources precisa ser um objeto.'), { status: 400 });
  }
  const normalized = {
    wood: nonNegativeNumber(value.wood || 0, 'wood'),
    clay: nonNegativeNumber(value.clay || 0, 'clay'),
    iron: nonNegativeNumber(value.iron || 0, 'iron'),
  };
  if (normalized.wood + normalized.clay + normalized.iron <= 0) {
    throw Object.assign(new Error('O transporte precisa conter recursos.'), { status: 400 });
  }
  return normalized;
}

export function validateStrategyPayload(type, payload) {
  const definition = STRATEGY_TYPES[type];
  if (!definition) {
    throw Object.assign(new Error(`Tipo de comando estratégico inválido: ${type || '(vazio)'}.`), { status: 400 });
  }
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) {
    throw Object.assign(new Error('payload precisa ser um objeto JSON.'), { status: 400 });
  }
  if (jsonBytes(payload) > MAX_PAYLOAD_BYTES) {
    throw Object.assign(new Error(`payload excede ${MAX_PAYLOAD_BYTES} bytes.`), { status: 413 });
  }

  const villageId = cleanId(payload.village_id);
  if (!villageId) throw Object.assign(new Error('village_id obrigatório.'), { status: 400 });

  const normalized = { ...payload, village_id: villageId };
  switch (type) {
    case 'build_upgrade':
      normalized.building = cleanId(payload.building, 48);
      if (!normalized.building) throw Object.assign(new Error('building obrigatório.'), { status: 400 });
      normalized.target_level = positiveInteger(payload.target_level, 'target_level', 50);
      break;
    case 'recruit_units':
      normalized.unit = cleanId(payload.unit, 48);
      if (!normalized.unit) throw Object.assign(new Error('unit obrigatório.'), { status: 400 });
      normalized.quantity = positiveInteger(payload.quantity, 'quantity', 1_000_000);
      break;
    case 'attack':
    case 'support':
      normalized.target_village_id = cleanId(payload.target_village_id);
      if (!normalized.target_village_id) throw Object.assign(new Error('target_village_id obrigatório.'), { status: 400 });
      normalized.troops = normalizeTroops(payload.troops);
      break;
    case 'spy':
      normalized.target_village_id = cleanId(payload.target_village_id);
      if (!normalized.target_village_id) throw Object.assign(new Error('target_village_id obrigatório.'), { status: 400 });
      normalized.spies = positiveInteger(payload.spies, 'spies', 1_000_000);
      break;
    case 'transfer_resources':
      normalized.target_village_id = cleanId(payload.target_village_id);
      if (!normalized.target_village_id) throw Object.assign(new Error('target_village_id obrigatório.'), { status: 400 });
      normalized.resources = normalizeResources(payload.resources);
      break;
    case 'collect_deposit':
      normalized.deposit_id = cleanId(payload.deposit_id);
      if (!normalized.deposit_id) throw Object.assign(new Error('deposit_id obrigatório.'), { status: 400 });
      break;
  }

  for (const key of definition.required) {
    if (normalized[key] == null || normalized[key] === '') {
      throw Object.assign(new Error(`Campo obrigatório ausente: ${key}.`), { status: 400 });
    }
  }
  return normalized;
}

export function normalizeSchedule(value, now = Date.now()) {
  if (value == null || value === '') return new Date(now).toISOString();
  const timestamp = new Date(value).getTime();
  if (!Number.isFinite(timestamp)) {
    throw Object.assign(new Error('scheduled_at inválido.'), { status: 400 });
  }
  const min = now - 5_000;
  const max = now + MAX_SCHEDULE_DAYS * 86_400_000;
  if (timestamp < min || timestamp > max) {
    throw Object.assign(new Error(`scheduled_at precisa estar entre agora e ${MAX_SCHEDULE_DAYS} dias.`), { status: 400 });
  }
  return new Date(Math.max(timestamp, now)).toISOString();
}

function corsOrigin(req) {
  const origin = String(req.headers.origin || '');
  const configuredOrigins = String(process.env.RT_ALLOWED_ORIGINS || '')
    .split(',')
    .map((x) => x.trim())
    .filter(Boolean);
  const allowed = new Set([
    'https://kaalflash12.github.io',
    'http://localhost:3000',
    'http://127.0.0.1:3000',
    'http://localhost:4173',
    'http://127.0.0.1:4173',
    ...configuredOrigins,
  ]);
  if (!origin) return '*';
  return allowed.has(origin) ? origin : '';
}

function setCors(req, res) {
  const origin = corsOrigin(req);
  if (origin) res.setHeader('Access-Control-Allow-Origin', origin);
  res.setHeader('Vary', 'Origin');
  res.setHeader('Access-Control-Allow-Headers', 'authorization, content-type');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('X-Content-Type-Options', 'nosniff');
}

function send(res, status, body) {
  return res.status(status).json(body);
}

async function ensureSchema() {
  if (schemaPromise) return schemaPromise;
  schemaPromise = (async () => {
    const conn = db();
    await conn.batch([
      `CREATE TABLE IF NOT EXISTS rt_strategy_commands (
        id TEXT PRIMARY KEY,
        world_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        village_id TEXT NOT NULL,
        command_type TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'queued',
        payload_json TEXT NOT NULL,
        result_json TEXT,
        scheduled_at TEXT NOT NULL,
        ready_at TEXT,
        completed_at TEXT,
        cancelled_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        idempotency_key TEXT,
        FOREIGN KEY(world_id) REFERENCES rt_worlds(id) ON DELETE CASCADE,
        FOREIGN KEY(user_id) REFERENCES rt_users(id) ON DELETE CASCADE
      )`,
      `CREATE UNIQUE INDEX IF NOT EXISTS idx_rt_strategy_idempotency
       ON rt_strategy_commands(world_id,user_id,idempotency_key)
       WHERE idempotency_key IS NOT NULL`,
      `CREATE INDEX IF NOT EXISTS idx_rt_strategy_user_world_status
       ON rt_strategy_commands(user_id,world_id,status,scheduled_at)`,
      `CREATE INDEX IF NOT EXISTS idx_rt_strategy_due
       ON rt_strategy_commands(world_id,status,scheduled_at)`,
      `CREATE TABLE IF NOT EXISTS rt_strategy_audit (
        id TEXT PRIMARY KEY,
        command_id TEXT NOT NULL,
        world_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        event_type TEXT NOT NULL,
        data_json TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY(command_id) REFERENCES rt_strategy_commands(id) ON DELETE CASCADE
      )`,
      `CREATE INDEX IF NOT EXISTS idx_rt_strategy_audit_command
       ON rt_strategy_audit(command_id,created_at)`,
    ]);
  })();
  return schemaPromise;
}

function bearer(req) {
  const auth = String(req.headers.authorization || '');
  return auth.toLowerCase().startsWith('bearer ') ? auth.slice(7).trim() : '';
}

async function session(req) {
  const token = bearer(req);
  if (!token) throw Object.assign(new Error('Sessão necessária.'), { status: 401 });
  const row = await db().prepare(`SELECT
      s.token_hash,s.expires_at,s.user_id,
      u.id,u.username,u.email,u.role,u.disabled
    FROM rt_sessions s
    JOIN rt_users u ON u.id=s.user_id
    WHERE s.token_hash=? AND s.expires_at>? LIMIT 1`).get([sha256(token), nowIso()]);
  if (!row || row.disabled) throw Object.assign(new Error('Sessão inválida ou expirada.'), { status: 401 });
  return { token, user: row };
}

async function requireMembership(userId, worldId) {
  const world = cleanId(worldId);
  if (!world) throw Object.assign(new Error('world_id obrigatório.'), { status: 400 });
  const membership = await db().prepare(`SELECT world_id,user_id,player_name,joined_at,last_seen_at
    FROM rt_player_worlds WHERE world_id=? AND user_id=? LIMIT 1`).get([world, userId]);
  if (!membership) throw Object.assign(new Error('Jogador não participa deste mundo.'), { status: 403 });
  return membership;
}

async function audit(command, eventType, data = null) {
  await db().prepare(`INSERT INTO rt_strategy_audit
    (id,command_id,world_id,user_id,event_type,data_json,created_at)
    VALUES (?,?,?,?,?,?,?)`).run([
    randomUUID(), command.id, command.world_id, command.user_id,
    String(eventType), data == null ? null : JSON.stringify(data), nowIso(),
  ]);
}

function publicCommand(row) {
  if (!row) return null;
  return {
    id: row.id,
    world_id: row.world_id,
    user_id: row.user_id,
    village_id: row.village_id,
    type: row.command_type,
    status: row.status,
    payload: parseJson(row.payload_json, {}),
    result: parseJson(row.result_json, null),
    scheduled_at: row.scheduled_at,
    ready_at: row.ready_at || null,
    completed_at: row.completed_at || null,
    cancelled_at: row.cancelled_at || null,
    created_at: row.created_at,
    updated_at: row.updated_at,
    idempotency_key: row.idempotency_key || null,
    realtime_event: STRATEGY_TYPES[row.command_type]?.event || 'Command/changed',
  };
}

async function advanceReady(userId, worldId) {
  const t = nowIso();
  await db().prepare(`UPDATE rt_strategy_commands
    SET status='ready',ready_at=COALESCE(ready_at,?),updated_at=?
    WHERE user_id=? AND world_id=? AND status='queued' AND scheduled_at<=?`).run([t, t, userId, worldId, t]);
}

async function findOwned(commandId, userId) {
  const row = await db().prepare(`SELECT * FROM rt_strategy_commands WHERE id=? AND user_id=? LIMIT 1`).get([
    cleanId(commandId), userId,
  ]);
  if (!row) throw Object.assign(new Error('Comando estratégico não encontrado.'), { status: 404 });
  return row;
}

async function createCommand(user, body) {
  const worldId = cleanId(body.world_id);
  await requireMembership(user.id, worldId);
  const type = cleanId(body.type, 48);
  const payload = validateStrategyPayload(type, body.payload || {});
  const scheduledAt = normalizeSchedule(body.scheduled_at);
  const idempotencyKey = cleanId(body.idempotency_key, MAX_IDEMPOTENCY_LENGTH) || null;
  const conn = db();

  if (idempotencyKey) {
    const existing = await conn.prepare(`SELECT * FROM rt_strategy_commands
      WHERE world_id=? AND user_id=? AND idempotency_key=? LIMIT 1`).get([
      worldId, user.id, idempotencyKey,
    ]);
    if (existing) return { command: publicCommand(existing), idempotent: true };
  }

  const t = nowIso();
  const command = {
    id: randomUUID(),
    world_id: worldId,
    user_id: user.id,
    village_id: payload.village_id,
    command_type: type,
    status: new Date(scheduledAt).getTime() <= Date.now() ? 'ready' : 'queued',
    payload_json: JSON.stringify(payload),
    result_json: null,
    scheduled_at: scheduledAt,
    ready_at: new Date(scheduledAt).getTime() <= Date.now() ? t : null,
    completed_at: null,
    cancelled_at: null,
    created_at: t,
    updated_at: t,
    idempotency_key: idempotencyKey,
  };

  await conn.prepare(`INSERT INTO rt_strategy_commands
    (id,world_id,user_id,village_id,command_type,status,payload_json,result_json,
     scheduled_at,ready_at,completed_at,cancelled_at,created_at,updated_at,idempotency_key)
    VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`).run([
    command.id, command.world_id, command.user_id, command.village_id,
    command.command_type, command.status, command.payload_json, command.result_json,
    command.scheduled_at, command.ready_at, command.completed_at, command.cancelled_at,
    command.created_at, command.updated_at, command.idempotency_key,
  ]);
  await audit(command, 'created', { status: command.status });
  return { command: publicCommand(command), idempotent: false };
}

async function listCommands(user, body) {
  const worldId = cleanId(body.world_id);
  await requireMembership(user.id, worldId);
  await advanceReady(user.id, worldId);
  const requestedStatus = cleanId(body.status, 24);
  if (requestedStatus && !COMMAND_STATUSES.has(requestedStatus)) {
    throw Object.assign(new Error('status inválido.'), { status: 400 });
  }
  const limit = Math.max(1, Math.min(250, Number(body.limit || 100)));
  const rows = requestedStatus
    ? await db().prepare(`SELECT * FROM rt_strategy_commands
        WHERE user_id=? AND world_id=? AND status=?
        ORDER BY scheduled_at ASC,created_at ASC LIMIT ?`).all([user.id, worldId, requestedStatus, limit])
    : await db().prepare(`SELECT * FROM rt_strategy_commands
        WHERE user_id=? AND world_id=?
        ORDER BY created_at DESC LIMIT ?`).all([user.id, worldId, limit]);
  return rows.map(publicCommand);
}

async function getCommand(user, body) {
  const row = await findOwned(body.command_id, user.id);
  await requireMembership(user.id, row.world_id);
  await advanceReady(user.id, row.world_id);
  return publicCommand(await findOwned(row.id, user.id));
}

async function cancelCommand(user, body) {
  const row = await findOwned(body.command_id, user.id);
  await requireMembership(user.id, row.world_id);
  if (!['queued', 'ready'].includes(row.status)) {
    throw Object.assign(new Error(`Comando em estado ${row.status} não pode ser cancelado.`), { status: 409 });
  }
  const t = nowIso();
  await db().prepare(`UPDATE rt_strategy_commands
    SET status='cancelled',cancelled_at=?,updated_at=? WHERE id=? AND user_id=?`).run([t, t, row.id, user.id]);
  const next = await findOwned(row.id, user.id);
  await audit(next, 'cancelled');
  return publicCommand(next);
}

async function completeCommand(user, body, failed = false) {
  const row = await findOwned(body.command_id, user.id);
  await requireMembership(user.id, row.world_id);
  await advanceReady(user.id, row.world_id);
  const fresh = await findOwned(row.id, user.id);
  if (fresh.status !== 'ready') {
    throw Object.assign(new Error(`Somente comando ready pode ser finalizado; estado atual: ${fresh.status}.`), { status: 409 });
  }
  const result = body.result == null ? null : body.result;
  if (result != null && jsonBytes(result) > MAX_RESULT_BYTES) {
    throw Object.assign(new Error(`result excede ${MAX_RESULT_BYTES} bytes.`), { status: 413 });
  }
  const t = nowIso();
  const status = failed ? 'failed' : 'completed';
  await db().prepare(`UPDATE rt_strategy_commands
    SET status=?,result_json=?,completed_at=?,updated_at=? WHERE id=? AND user_id=?`).run([
    status, result == null ? null : JSON.stringify(result), t, t, fresh.id, user.id,
  ]);
  const next = await findOwned(fresh.id, user.id);
  await audit(next, status, result);
  return publicCommand(next);
}

async function commandAudit(user, body) {
  const command = await findOwned(body.command_id, user.id);
  await requireMembership(user.id, command.world_id);
  const rows = await db().prepare(`SELECT id,event_type,data_json,created_at
    FROM rt_strategy_audit WHERE command_id=? ORDER BY created_at ASC LIMIT 250`).all([command.id]);
  return rows.map((row) => ({
    id: row.id,
    event_type: row.event_type,
    data: parseJson(row.data_json, null),
    created_at: row.created_at,
  }));
}

async function summary(user, body) {
  const worldId = cleanId(body.world_id);
  await requireMembership(user.id, worldId);
  await advanceReady(user.id, worldId);
  const rows = await db().prepare(`SELECT status,COUNT(*) AS total
    FROM rt_strategy_commands WHERE user_id=? AND world_id=? GROUP BY status`).all([user.id, worldId]);
  const counts = { queued: 0, ready: 0, completed: 0, cancelled: 0, failed: 0 };
  for (const row of rows) if (row.status in counts) counts[row.status] = Number(row.total || 0);
  return { world_id: worldId, counts, types: Object.keys(STRATEGY_TYPES) };
}

function catalog() {
  return Object.entries(STRATEGY_TYPES).map(([type, definition]) => ({
    type,
    label: definition.label,
    required: [...definition.required],
    realtime_event: definition.event,
  }));
}

export default async function strategyHandler(req, res) {
  setCors(req, res);
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST') return send(res, 405, { error: 'Método não permitido.' });

  try {
    const body = req.body && typeof req.body === 'object' ? req.body : {};
    const action = cleanId(body.action, 48);
    if (action === 'health') {
      return send(res, 200, {
        ok: true,
        service: 'reino-tribal-strategy',
        database: 'turso',
        configured: configured(),
        types: Object.keys(STRATEGY_TYPES),
      });
    }
    if (action === 'catalog') return send(res, 200, catalog());

    await ensureSchema();
    const current = await session(req);

    if (action === 'create') return send(res, 200, await createCommand(current.user, body));
    if (action === 'list') return send(res, 200, await listCommands(current.user, body));
    if (action === 'get') return send(res, 200, await getCommand(current.user, body));
    if (action === 'cancel') return send(res, 200, await cancelCommand(current.user, body));
    if (action === 'complete') return send(res, 200, await completeCommand(current.user, body, false));
    if (action === 'fail') return send(res, 200, await completeCommand(current.user, body, true));
    if (action === 'audit') return send(res, 200, await commandAudit(current.user, body));
    if (action === 'summary') return send(res, 200, await summary(current.user, body));

    return send(res, 400, { error: `Ação estratégica desconhecida: ${action || '(vazia)'}.` });
  } catch (error) {
    const status = Number(error?.status || 500);
    console.error('reino-tribal-strategy', error);
    return send(res, status, { error: String(error?.message || 'Falha estratégica.') });
  }
}
