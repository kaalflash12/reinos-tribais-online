PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS rt_users (
  id TEXT PRIMARY KEY,
  username TEXT NOT NULL COLLATE NOCASE UNIQUE,
  email TEXT COLLATE NOCASE UNIQUE,
  password_hash TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'player' CHECK(role IN ('player','admin')),
  disabled INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  last_login_at TEXT
);

CREATE TABLE IF NOT EXISTS rt_sessions (
  token_hash TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES rt_users(id) ON DELETE CASCADE,
  expires_at TEXT NOT NULL,
  created_at TEXT NOT NULL,
  last_seen_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS rt_sessions_user_idx ON rt_sessions(user_id);
CREATE INDEX IF NOT EXISTS rt_sessions_exp_idx ON rt_sessions(expires_at);

CREATE TABLE IF NOT EXISTS rt_worlds (
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
);

CREATE TABLE IF NOT EXISTS rt_player_worlds (
  world_id TEXT NOT NULL REFERENCES rt_worlds(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL REFERENCES rt_users(id) ON DELETE CASCADE,
  player_name TEXT NOT NULL,
  summary_json TEXT NOT NULL DEFAULT '{}',
  joined_at TEXT NOT NULL,
  last_seen_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY(world_id,user_id)
);
CREATE INDEX IF NOT EXISTS rt_player_worlds_seen_idx ON rt_player_worlds(world_id,last_seen_at);

CREATE TABLE IF NOT EXISTS rt_game_saves (
  world_id TEXT NOT NULL REFERENCES rt_worlds(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL REFERENCES rt_users(id) ON DELETE CASCADE,
  state_json TEXT NOT NULL,
  state_version INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY(world_id,user_id)
);

CREATE TABLE IF NOT EXISTS rt_documents (
  namespace TEXT NOT NULL,
  doc_key TEXT NOT NULL,
  world_id TEXT NOT NULL DEFAULT '',
  user_id TEXT NOT NULL DEFAULT '',
  data_json TEXT NOT NULL DEFAULT '{}',
  version INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY(namespace,doc_key,world_id,user_id)
);
CREATE INDEX IF NOT EXISTS rt_documents_scope_idx ON rt_documents(namespace,world_id,user_id,updated_at);

CREATE TABLE IF NOT EXISTS rt_admin_audit (
  id TEXT PRIMARY KEY,
  admin_user_id TEXT NOT NULL,
  action TEXT NOT NULL,
  target TEXT,
  payload_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS rt_runtime_kv (
  key TEXT PRIMARY KEY,
  value_json TEXT NOT NULL DEFAULT '{}',
  updated_at TEXT NOT NULL
);
