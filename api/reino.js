import { connect } from '@tursodatabase/serverless';
import {
  createHash,
  randomBytes,
  randomUUID,
  scryptSync,
  timingSafeEqual,
} from 'node:crypto';

const DEFAULT_WORLD_ID = 'd5a546fb-316d-4332-ae92-1886d80b07df';
const DEFAULT_WORLD_SLUG = 'mundo-1';
const SESSION_DAYS = Math.max(1, Number(process.env.RT_SESSION_DAYS || 30));
const MAX_SAVE_BYTES = Math.max(256000, Number(process.env.RT_MAX_SAVE_BYTES || 6_000_000));
const ADMIN_USERNAME = 'reinos_admin';

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
        iterate: async function* (...args) { for await (const row of (await statement()).iterate(...args)) yield row; },
      };
    },
    batch: (...args) => raw.batch(...args),
    exec: (...args) => raw.exec(...args),
    run: (...args) => raw.run(...args),
    get: (...args) => raw.get(...args),
    all: (...args) => raw.all(...args),
    close: (...args) => raw.close?.(...args),
  };
}

function db() {
  if (!configured()) throw new Error('Turso não configurado no servidor.');
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

function addDaysIso(days) {
  return new Date(Date.now() + days * 86400000).toISOString();
}

function normalizeUsername(value) {
  return String(value || '')
    .trim()
    .toLowerCase()
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-z0-9_.-]+/g, '_')
    .replace(/^_+|_+$/g, '')
    .slice(0, 32);
}

function normalizeEmail(value) {
  return String(value || '').trim().toLowerCase().slice(0, 254);
}

function passwordHash(password, salt = randomBytes(16).toString('hex')) {
  const hash = scryptSync(String(password), salt, 64).toString('hex');
  return `scrypt$${salt}$${hash}`;
}

function verifyPassword(password, stored) {
  try {
    const [scheme, salt, hex] = String(stored || '').split('$');
    if (scheme !== 'scrypt' || !salt || !hex) return false;
    const actual = scryptSync(String(password), salt, 64);
    const expected = Buffer.from(hex, 'hex');
    return actual.length === expected.length && timingSafeEqual(actual, expected);
  } catch {
    return false;
  }
}

function sha256(value) {
  return createHash('sha256').update(String(value)).digest('hex');
}

function safeEqualText(a, b) {
  const aa = Buffer.from(String(a || ''));
  const bb = Buffer.from(String(b || ''));
  return aa.length === bb.length && timingSafeEqual(aa, bb);
}

function json(value, fallback = null) {
  try {
    if (value == null || value === '') return fallback;
    return typeof value === 'string' ? JSON.parse(value) : value;
  } catch {
    return fallback;
  }
}

function corsOrigin(req) {
  const origin = String(req.headers.origin || '');
  const configuredOrigins = String(process.env.RT_ALLOWED_ORIGINS || '')
    .split(',')
    .map((x) => x.trim())
    .filter(Boolean);
  const defaults = [
    'https://kaalflash12.github.io',
    'http://localhost:3000',
    'http://127.0.0.1:3000',
    'http://localhost:4173',
    'http://127.0.0.1:4173',
  ];
  const allowed = new Set([...defaults, ...configuredOrigins]);
  if (!origin) return '*';
  if (allowed.has(origin)) return origin;
  return '';
}

function setCors(req, res) {
  const origin = corsOrigin(req);
  if (origin) res.setHeader('Access-Control-Allow-Origin', origin);
  res.setHeader('Vary', 'Origin');
  res.setHeader('Access-Control-Allow-Headers', 'authorization, content-type, x-admin-token');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('X-Content-Type-Options', 'nosniff');
}

function send(res, status, body) {
  return res.status(status).json(body);
}

function publicUser(row) {
  if (!row) return null;
  return {
    id: row.id,
    email: row.email || null,
    username: row.username,
    role: row.role,
    disabled: Boolean(row.disabled),
    created_at: row.created_at,
    user_metadata: { username: row.username, role: row.role },
    aud: 'authenticated',
  };
}

async function ensureSchema() {
  if (schemaPromise) return schemaPromise;
  schemaPromise = (async () => {
    const conn = db();
    await conn.batch([
      `CREATE TABLE IF NOT EXISTS rt_users (
        id TEXT PRIMARY KEY,
        username TEXT NOT NULL COLLATE NOCASE UNIQUE,
        email TEXT COLLATE NOCASE UNIQUE,
        password_hash TEXT NOT NULL,
        role TEXT NOT NULL DEFAULT 'player' CHECK(role IN ('player','admin')),
        disabled INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        last_login_at TEXT
      )`,
      `CREATE TABLE IF NOT EXISTS rt_sessions (
        token_hash TEXT PRIMARY KEY,
        user_id TEXT NOT NULL REFERENCES rt_users(id) ON DELETE CASCADE,
        expires_at TEXT NOT NULL,
        created_at TEXT NOT NULL,
        last_seen_at TEXT NOT NULL
      )`,
      `CREATE INDEX IF NOT EXISTS rt_sessions_user_idx ON rt_sessions(user_id)`,
      `CREATE INDEX IF NOT EXISTS rt_sessions_exp_idx ON rt_sessions(expires_at)`,
      `CREATE TABLE IF NOT EXISTS rt_worlds (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        slug TEXT NOT NULL COLLATE NOCASE UNIQUE,
        status TEXT NOT NULL DEFAULT 'open',
        is_active INTEGER NOT NULL DEFAULT 1,
        season_number INTEGER NOT NULL DEFAULT 1,
        max_players INTEGER NOT NULL DEFAULT 5000,
        settings_json TEXT NOT NULL DEFAULT '{}',
        opened_at TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )`,
      `CREATE TABLE IF NOT EXISTS rt_player_worlds (
        world_id TEXT NOT NULL REFERENCES rt_worlds(id) ON DELETE CASCADE,
        user_id TEXT NOT NULL REFERENCES rt_users(id) ON DELETE CASCADE,
        player_name TEXT NOT NULL,
        summary_json TEXT NOT NULL DEFAULT '{}',
        joined_at TEXT NOT NULL,
        last_seen_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY(world_id,user_id)
      )`,
      `CREATE INDEX IF NOT EXISTS rt_player_worlds_seen_idx ON rt_player_worlds(world_id,last_seen_at)`,
      `CREATE TABLE IF NOT EXISTS rt_game_saves (
        world_id TEXT NOT NULL REFERENCES rt_worlds(id) ON DELETE CASCADE,
        user_id TEXT NOT NULL REFERENCES rt_users(id) ON DELETE CASCADE,
        state_json TEXT NOT NULL,
        state_version INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY(world_id,user_id)
      )`,
      `CREATE TABLE IF NOT EXISTS rt_documents (
        namespace TEXT NOT NULL,
        doc_key TEXT NOT NULL,
        world_id TEXT NOT NULL DEFAULT '',
        user_id TEXT NOT NULL DEFAULT '',
        data_json TEXT NOT NULL DEFAULT '{}',
        version INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY(namespace,doc_key,world_id,user_id)
      )`,
      `CREATE INDEX IF NOT EXISTS rt_documents_scope_idx ON rt_documents(namespace,world_id,user_id,updated_at)`,
      `CREATE TABLE IF NOT EXISTS rt_admin_audit (
        id TEXT PRIMARY KEY,
        admin_user_id TEXT NOT NULL,
        action TEXT NOT NULL,
        target TEXT,
        payload_json TEXT NOT NULL DEFAULT '{}',
        created_at TEXT NOT NULL
      )`,
      `CREATE TABLE IF NOT EXISTS rt_runtime_kv (
        key TEXT PRIMARY KEY,
        value_json TEXT NOT NULL DEFAULT '{}',
        updated_at TEXT NOT NULL
      )`,
    ]);

    const t = nowIso();
    await conn.prepare(`INSERT INTO rt_worlds
      (id,name,slug,status,is_active,season_number,max_players,settings_json,opened_at,created_at,updated_at)
      VALUES (?,?,?,?,?,?,?,?,?,?,?)
      ON CONFLICT(id) DO NOTHING`).run([
      DEFAULT_WORLD_ID,
      'Mundo 1',
      DEFAULT_WORLD_SLUG,
      'open',
      1,
      1,
      5000,
      JSON.stringify({ worldSpeed: 1, unitSpeed: 1, researchSystem: 'three' }),
      t,
      t,
      t,
    ]);

    await conn.prepare(`DELETE FROM rt_sessions WHERE expires_at <= ?`).run([t]);
    await ensureAdmin();
  })().catch((error) => {
    schemaPromise = null;
    throw error;
  });
  return schemaPromise;
}

async function ensureAdmin() {
  const password = String(process.env.RT_ADMIN_PASSWORD || '');
  if (password.length < 12) return;
  const conn = db();
  const existing = await conn.prepare('SELECT id FROM rt_users WHERE username = ? LIMIT 1').get([ADMIN_USERNAME]);
  if (existing) return;
  const t = nowIso();
  await conn.prepare(`INSERT INTO rt_users
    (id,username,email,password_hash,role,disabled,created_at,updated_at)
    VALUES (?,?,?,?, 'admin',0,?,?)`).run([
    randomUUID(),
    ADMIN_USERNAME,
    null,
    passwordHash(password),
    t,
    t,
  ]);
}

async function readBody(req) {
  if (!req.body) return {};
  if (typeof req.body === 'object') return req.body;
  try { return JSON.parse(req.body); } catch { return {}; }
}

function bearer(req) {
  const auth = String(req.headers.authorization || '');
  return auth.toLowerCase().startsWith('bearer ') ? auth.slice(7).trim() : '';
}

async function sessionFromRequest(req, required = true) {
  const token = bearer(req);
  if (!token) {
    if (required) throw Object.assign(new Error('Sessão necessária.'), { status: 401 });
    return null;
  }
  const row = await db().prepare(`SELECT
      s.token_hash,s.expires_at,s.user_id,
      u.id,u.username,u.email,u.role,u.disabled,u.created_at,u.updated_at,u.last_login_at
    FROM rt_sessions s
    JOIN rt_users u ON u.id=s.user_id
    WHERE s.token_hash=? AND s.expires_at>? LIMIT 1`).get([sha256(token), nowIso()]);
  if (!row || row.disabled) {
    if (required) throw Object.assign(new Error('Sessão inválida ou expirada.'), { status: 401 });
    return null;
  }
  db().prepare('UPDATE rt_sessions SET last_seen_at=? WHERE token_hash=?').run([nowIso(), row.token_hash]).catch(() => {});
  return { token, user: row };
}

async function requireAdmin(req) {
  const s = await sessionFromRequest(req, true);
  if (s.user.role !== 'admin') throw Object.assign(new Error('Acesso administrativo necessário.'), { status: 403 });
  return s;
}

async function issueSession(user) {
  const token = randomBytes(32).toString('base64url');
  const t = nowIso();
  const expires = addDaysIso(SESSION_DAYS);
  await db().prepare(`INSERT INTO rt_sessions(token_hash,user_id,expires_at,created_at,last_seen_at)
    VALUES (?,?,?,?,?)`).run([sha256(token), user.id, expires, t, t]);
  return {
    access_token: token,
    token_type: 'bearer',
    expires_in: SESSION_DAYS * 86400,
    expires_at: Math.floor(new Date(expires).getTime() / 1000),
    refresh_token: token,
    user: publicUser(user),
  };
}

async function register(body) {
  const email = normalizeEmail(body.email);
  let username = normalizeUsername(body.username || email.split('@')[0]);
  const password = String(body.password || '');
  if (!email.includes('@')) throw Object.assign(new Error('Informe um e-mail válido.'), { status: 400 });
  if (username.length < 3) username = `governante_${randomBytes(3).toString('hex')}`;
  if (password.length < 8) throw Object.assign(new Error('A senha precisa ter pelo menos 8 caracteres.'), { status: 400 });
  const conn = db();
  const collision = await conn.prepare('SELECT username,email FROM rt_users WHERE username=? OR email=? LIMIT 1').get([username, email]);
  if (collision) throw Object.assign(new Error(collision.username === username ? 'Nome de usuário já está em uso.' : 'E-mail já cadastrado.'), { status: 409 });
  const t = nowIso();
  const user = {
    id: randomUUID(), username, email, role: 'player', disabled: 0,
    created_at: t, updated_at: t, last_login_at: t,
  };
  await conn.prepare(`INSERT INTO rt_users
    (id,username,email,password_hash,role,disabled,created_at,updated_at,last_login_at)
    VALUES (?,?,?,?, 'player',0,?,?,?)`).run([
    user.id, username, email, passwordHash(password), t, t, t,
  ]);
  return issueSession(user);
}

async function login(body) {
  const identifier = String(body.identifier || body.email || body.username || '').trim().toLowerCase();
  const password = String(body.password || '');
  if (!identifier || password.length < 6) throw Object.assign(new Error('Informe usuário/e-mail e senha.'), { status: 400 });
  const row = identifier.includes('@')
    ? await db().prepare('SELECT * FROM rt_users WHERE email=? LIMIT 1').get([identifier])
    : await db().prepare('SELECT * FROM rt_users WHERE username=? LIMIT 1').get([normalizeUsername(identifier)]);
  if (!row || row.disabled || !verifyPassword(password, row.password_hash)) {
    throw Object.assign(new Error('Credenciais inválidas ou conta indisponível.'), { status: 401 });
  }
  const t = nowIso();
  await db().prepare('UPDATE rt_users SET last_login_at=?,updated_at=? WHERE id=?').run([t, t, row.id]);
  row.last_login_at = t;
  return issueSession(row);
}

async function listWorlds() {
  const rows = await db().prepare(`SELECT
      w.id,w.name,w.slug,w.status,w.is_active,w.season_number,w.max_players,w.settings_json,w.opened_at,w.created_at,
      COUNT(pw.user_id) AS player_count
    FROM rt_worlds w
    LEFT JOIN rt_player_worlds pw ON pw.world_id=w.id
    WHERE w.is_active=1 AND w.status='open'
    GROUP BY w.id
    ORDER BY w.created_at ASC`).all([]);
  return rows.map((r) => ({
    ...r,
    is_active: Boolean(r.is_active),
    settings: json(r.settings_json, {}),
    player_count: Number(r.player_count || 0),
  }));
}

async function joinWorld(user, body) {
  const worldId = String(body.world_id || body.p_world_id || DEFAULT_WORLD_ID);
  const world = await db().prepare('SELECT * FROM rt_worlds WHERE id=? AND is_active=1 LIMIT 1').get([worldId]);
  if (!world) throw Object.assign(new Error('Mundo não encontrado.'), { status: 404 });
  const playerName = String(body.player_name || body.p_player_name || user.username || 'Governante').trim().slice(0, 32) || user.username;
  const t = nowIso();
  await db().prepare(`INSERT INTO rt_player_worlds(world_id,user_id,player_name,summary_json,joined_at,last_seen_at,updated_at)
    VALUES (?,?,?,'{}',?,?,?)
    ON CONFLICT(world_id,user_id) DO UPDATE SET player_name=excluded.player_name,last_seen_at=excluded.last_seen_at,updated_at=excluded.updated_at`).run([
    worldId, user.id, playerName, t, t, t,
  ]);
  return {
    ok: true,
    world: {
      id: world.id,
      name: world.name,
      slug: world.slug,
      status: world.status,
      is_active: Boolean(world.is_active),
      season_number: Number(world.season_number || 1),
      max_players: Number(world.max_players || 5000),
      settings: json(world.settings_json, {}),
      opened_at: world.opened_at,
    },
  };
}

async function memberships(user) {
  return db().prepare('SELECT world_id,user_id,player_name,joined_at,last_seen_at,updated_at FROM rt_player_worlds WHERE user_id=? ORDER BY joined_at ASC').all([user.id]);
}

async function loadSave(user, body) {
  const worldId = String(body.world_id || DEFAULT_WORLD_ID);
  const row = await db().prepare('SELECT state_json,updated_at,state_version FROM rt_game_saves WHERE world_id=? AND user_id=? LIMIT 1').get([worldId, user.id]);
  if (!row) return null;
  return { state: json(row.state_json, null), updated_at: row.updated_at, state_version: Number(row.state_version || 1) };
}

async function saveState(user, body) {
  const worldId = String(body.world_id || DEFAULT_WORLD_ID);
  const state = body.state ?? body.state_json ?? null;
  if (state == null) throw Object.assign(new Error('Save vazio.'), { status: 400 });
  const stateJson = typeof state === 'string' ? state : JSON.stringify(state);
  if (Buffer.byteLength(stateJson, 'utf8') > MAX_SAVE_BYTES) throw Object.assign(new Error('Save excede o limite permitido.'), { status: 413 });
  const t = nowIso();
  const exists = await db().prepare('SELECT 1 AS ok FROM rt_worlds WHERE id=? LIMIT 1').get([worldId]);
  if (!exists) throw Object.assign(new Error('Mundo não encontrado.'), { status: 404 });
  await db().prepare(`INSERT INTO rt_game_saves(world_id,user_id,state_json,state_version,created_at,updated_at)
    VALUES (?,?,?,1,?,?)
    ON CONFLICT(world_id,user_id) DO UPDATE SET
      state_json=excluded.state_json,
      state_version=rt_game_saves.state_version+1,
      updated_at=excluded.updated_at`).run([worldId, user.id, stateJson, t, t]);
  await db().prepare(`INSERT INTO rt_player_worlds(world_id,user_id,player_name,summary_json,joined_at,last_seen_at,updated_at)
    VALUES (?,?,?,'{}',?,?,?)
    ON CONFLICT(world_id,user_id) DO UPDATE SET last_seen_at=excluded.last_seen_at,updated_at=excluded.updated_at`).run([
    worldId, user.id, user.username, t, t, t,
  ]);
  const saved = await db().prepare('SELECT state_version,updated_at FROM rt_game_saves WHERE world_id=? AND user_id=?').get([worldId, user.id]);
  return { ok: true, state_version: Number(saved?.state_version || 1), updated_at: saved?.updated_at || t };
}

async function deleteSave(user, body) {
  const worldId = String(body.world_id || DEFAULT_WORLD_ID);
  await db().prepare('DELETE FROM rt_game_saves WHERE world_id=? AND user_id=?').run([worldId, user.id]);
  return { ok: true };
}

async function playerWorldGet(user, body) {
  const worldId = String(body.world_id || DEFAULT_WORLD_ID);
  const row = await db().prepare('SELECT * FROM rt_player_worlds WHERE world_id=? AND user_id=? LIMIT 1').get([worldId, user.id]);
  if (!row) return null;
  return { ...json(row.summary_json, {}), world_id: row.world_id, user_id: row.user_id, player_name: row.player_name, joined_at: row.joined_at, last_seen_at: row.last_seen_at, updated_at: row.updated_at };
}

async function playerWorldUpdate(user, body) {
  const worldId = String(body.world_id || DEFAULT_WORLD_ID);
  const patch = body.patch && typeof body.patch === 'object' ? body.patch : {};
  const current = await playerWorldGet(user, { world_id: worldId });
  const merged = { ...(current || {}), ...patch };
  delete merged.world_id; delete merged.user_id; delete merged.joined_at; delete merged.last_seen_at; delete merged.updated_at;
  const playerName = String(patch.player_name || current?.player_name || user.username).slice(0, 32);
  const t = nowIso();
  await db().prepare(`INSERT INTO rt_player_worlds(world_id,user_id,player_name,summary_json,joined_at,last_seen_at,updated_at)
    VALUES (?,?,?,?,?,?,?)
    ON CONFLICT(world_id,user_id) DO UPDATE SET player_name=excluded.player_name,summary_json=excluded.summary_json,last_seen_at=excluded.last_seen_at,updated_at=excluded.updated_at`).run([
    worldId, user.id, playerName, JSON.stringify(merged), t, t, t,
  ]);
  return { ok: true, ...(await playerWorldGet(user, { world_id: worldId })) };
}

async function docPut(user, body) {
  const namespace = String(body.namespace || '').trim().slice(0, 80);
  const key = String(body.key || '').trim().slice(0, 160);
  const worldId = String(body.world_id || '');
  const owner = body.global === true ? '' : user.id;
  if (!namespace || !key) throw Object.assign(new Error('namespace e key são obrigatórios.'), { status: 400 });
  if (body.global === true && user.role !== 'admin') throw Object.assign(new Error('Somente administrador pode gravar documento global.'), { status: 403 });
  const dataJson = JSON.stringify(body.data ?? {});
  const t = nowIso();
  await db().prepare(`INSERT INTO rt_documents(namespace,doc_key,world_id,user_id,data_json,version,created_at,updated_at)
    VALUES (?,?,?,?,?,1,?,?)
    ON CONFLICT(namespace,doc_key,world_id,user_id) DO UPDATE SET data_json=excluded.data_json,version=rt_documents.version+1,updated_at=excluded.updated_at`).run([
    namespace, key, worldId, owner, dataJson, t, t,
  ]);
  return { ok: true, namespace, key, world_id: worldId, user_id: owner, updated_at: t };
}

async function docGet(user, body) {
  const namespace = String(body.namespace || '').trim().slice(0, 80);
  const key = String(body.key || '').trim().slice(0, 160);
  const worldId = String(body.world_id || '');
  const owner = body.global === true ? '' : user.id;
  const row = await db().prepare(`SELECT namespace,doc_key,world_id,user_id,data_json,version,created_at,updated_at
    FROM rt_documents WHERE namespace=? AND doc_key=? AND world_id=? AND user_id=? LIMIT 1`).get([namespace, key, worldId, owner]);
  if (!row) return null;
  return { namespace: row.namespace, key: row.doc_key, world_id: row.world_id, user_id: row.user_id, data: json(row.data_json, {}), version: Number(row.version || 1), created_at: row.created_at, updated_at: row.updated_at };
}

async function audit(admin, action, target, payload = {}) {
  await db().prepare('INSERT INTO rt_admin_audit(id,admin_user_id,action,target,payload_json,created_at) VALUES (?,?,?,?,?,?)').run([
    randomUUID(), admin.id, action, String(target || ''), JSON.stringify(payload || {}), nowIso(),
  ]);
}

async function adminPlayers(admin, body) {
  const limit = Math.min(500, Math.max(1, Number(body.limit || 200)));
  const rows = await db().prepare(`SELECT id,username,email,role,disabled,created_at,updated_at,last_login_at
    FROM rt_users ORDER BY created_at DESC LIMIT ?`).all([limit]);
  await audit(admin, 'players_list', '', { limit });
  return rows.map(publicUser);
}

async function adminPatchUser(admin, body) {
  const id = String(body.user_id || '');
  const target = await db().prepare('SELECT * FROM rt_users WHERE id=? LIMIT 1').get([id]);
  if (!target) throw Object.assign(new Error('Usuário não encontrado.'), { status: 404 });
  const role = body.role === 'admin' ? 'admin' : body.role === 'player' ? 'player' : target.role;
  const disabled = body.disabled == null ? Number(target.disabled || 0) : body.disabled ? 1 : 0;
  if (target.username === ADMIN_USERNAME && (role !== 'admin' || disabled)) throw Object.assign(new Error('A conta mestre não pode ser desativada nem rebaixada.'), { status: 400 });
  await db().prepare('UPDATE rt_users SET role=?,disabled=?,updated_at=? WHERE id=?').run([role, disabled, nowIso(), id]);
  await audit(admin, 'user_patch', id, { role, disabled: Boolean(disabled) });
  return { ok: true, user: publicUser({ ...target, role, disabled }) };
}

async function adminRecover(body) {
  const recovery = String(process.env.RT_ADMIN_RECOVERY_KEY || '');
  const supplied = String(body.token || body.recovery_key || '');
  const password = String(body.password || '');
  if (recovery.length < 32 || !safeEqualText(recovery, supplied)) throw Object.assign(new Error('Código de recuperação inválido.'), { status: 401 });
  if (password.length < 12) throw Object.assign(new Error('A nova senha precisa ter pelo menos 12 caracteres.'), { status: 400 });
  const admin = await db().prepare('SELECT * FROM rt_users WHERE username=? LIMIT 1').get([ADMIN_USERNAME]);
  if (!admin) throw Object.assign(new Error('Administrador ainda não foi provisionado.'), { status: 409 });
  const t = nowIso();
  await db().prepare('UPDATE rt_users SET password_hash=?,disabled=0,role=\'admin\',updated_at=? WHERE id=?').run([passwordHash(password), t, admin.id]);
  await db().prepare('DELETE FROM rt_sessions WHERE user_id=?').run([admin.id]);
  await audit(admin, 'admin_password_recovery', admin.id, {});
  return { ok: true, username: ADMIN_USERNAME };
}

async function handleAction(req, body) {
  const action = String(body.action || '').trim();
  if (action === 'health') {
    if (!configured()) return { status: 503, data: { ok: false, service: 'reino-tribal-turso', configured: false, error: 'Turso ainda não configurado.' } };
    await ensureSchema();
    const probe = await db().prepare('SELECT 1 AS ok').get([]);
    return { status: 200, data: { ok: Number(probe?.ok || 0) === 1, service: 'reino-tribal-turso', database: 'turso', schema: 1, configured: true } };
  }

  await ensureSchema();

  if (action === 'register' || action === 'signup') return { status: 200, data: await register(body) };
  if (action === 'login' || action === 'password_login') return { status: 200, data: await login(body) };
  if (action === 'admin_recover') return { status: 200, data: await adminRecover(body) };

  const session = await sessionFromRequest(req, true);
  const user = session.user;

  if (action === 'me') return { status: 200, data: { user: publicUser(user) } };
  if (action === 'logout') {
    await db().prepare('DELETE FROM rt_sessions WHERE token_hash=?').run([sha256(session.token)]);
    return { status: 200, data: { ok: true } };
  }
  if (action === 'list_worlds') return { status: 200, data: await listWorlds() };
  if (action === 'memberships') return { status: 200, data: await memberships(user) };
  if (action === 'join_world') return { status: 200, data: await joinWorld(user, body) };
  if (action === 'load_save') return { status: 200, data: await loadSave(user, body) };
  if (action === 'save') return { status: 200, data: await saveState(user, body) };
  if (action === 'delete_save') return { status: 200, data: await deleteSave(user, body) };
  if (action === 'player_world_get') return { status: 200, data: await playerWorldGet(user, body) };
  if (action === 'player_world_update') return { status: 200, data: await playerWorldUpdate(user, body) };
  if (action === 'doc_get') return { status: 200, data: await docGet(user, body) };
  if (action === 'doc_put') return { status: 200, data: await docPut(user, body) };

  if (action.startsWith('admin_')) {
    const adminSession = await requireAdmin(req);
    const admin = adminSession.user;
    if (action === 'admin_status') {
      const counts = await db().prepare(`SELECT
        (SELECT COUNT(*) FROM rt_users) AS users,
        (SELECT COUNT(*) FROM rt_game_saves) AS saves,
        (SELECT COUNT(*) FROM rt_player_worlds) AS memberships,
        (SELECT COUNT(*) FROM rt_sessions WHERE expires_at>?) AS sessions`).get([nowIso()]);
      return { status: 200, data: { ok: true, admin: publicUser(admin), counts } };
    }
    if (action === 'admin_players') return { status: 200, data: await adminPlayers(admin, body) };
    if (action === 'admin_user_patch') return { status: 200, data: await adminPatchUser(admin, body) };
  }

  throw Object.assign(new Error('Ação desconhecida.'), { status: 400 });
}

export default async function handler(req, res) {
  setCors(req, res);
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST') return send(res, 405, { error: 'Método inválido.' });
  if (req.headers.origin && !corsOrigin(req)) return send(res, 403, { error: 'Origem não autorizada.' });

  try {
    const body = await readBody(req);
    const result = await handleAction(req, body);
    return send(res, result.status || 200, result.data);
  } catch (error) {
    console.error('reino-tribal-api', error);
    const status = Number(error?.status || 500);
    const message = status >= 500 ? 'Falha temporária do servidor do Reino Tribal.' : String(error?.message || 'Falha na requisição.');
    return send(res, status, { error: message });
  }
}
