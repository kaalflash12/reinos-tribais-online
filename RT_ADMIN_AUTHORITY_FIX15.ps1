$ErrorActionPreference = 'Stop'
$path = Join-Path $PSScriptRoot 'api/reino.js'
if (-not (Test-Path $path)) { throw 'api/reino.js nao encontrado.' }
$text = [IO.File]::ReadAllText($path)

if ($text -notmatch 'const passwordMatches = verifyPassword\(password, existing\.password_hash\);') {
$old = @'
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
'@
$new = @'
async function ensureAdmin() {
  const password = String(process.env.RT_ADMIN_PASSWORD || '');
  if (password.length < 12) return;
  const conn = db();
  const existing = await conn.prepare('SELECT * FROM rt_users WHERE username = ? LIMIT 1').get([ADMIN_USERNAME]);
  const t = nowIso();

  if (!existing) {
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
    return;
  }

  const passwordMatches = verifyPassword(password, existing.password_hash);
  const needsSync = !passwordMatches || existing.role !== 'admin' || Boolean(existing.disabled);
  if (!needsSync) return;

  await conn.prepare("UPDATE rt_users SET password_hash=?,role='admin',disabled=0,updated_at=? WHERE id=?").run([
    passwordHash(password),
    t,
    existing.id,
  ]);
  if (!passwordMatches) {
    await conn.prepare('DELETE FROM rt_sessions WHERE user_id=?').run([existing.id]);
  }
}
'@
if (-not $text.Contains($old)) { throw 'Bloco ensureAdmin antigo nao encontrado exatamente; abortando sem alterar.' }
$text = $text.Replace($old,$new)
}

$loginSync = "  if (!identifier.includes('@') && normalizeUsername(identifier) === ADMIN_USERNAME) await ensureAdmin();"
if (-not $text.Contains($loginSync)) {
  $prefix = '  if (!identifier || password.length < 6) throw Object.assign(new Error('
  $start = $text.IndexOf($prefix,[StringComparison]::Ordinal)
  if ($start -lt 0) { throw 'Prefixo estrutural do login admin nao encontrado.' }
  $lineEnd = $text.IndexOf("`n",$start)
  if ($lineEnd -lt 0) { throw 'Fim da linha estrutural do login admin nao encontrado.' }
  $text = $text.Insert($lineEnd + 1,$loginSync + "`n")
}

if ($text.Contains('if (existing) return;')) { throw 'ensureAdmin antigo ainda presente.' }
foreach ($required in @(
  'const passwordMatches = verifyPassword(password, existing.password_hash);',
  "role='admin',disabled=0",
  "DELETE FROM rt_sessions WHERE user_id=?",
  "normalizeUsername(identifier) === ADMIN_USERNAME) await ensureAdmin();"
)) {
  if (-not $text.Contains($required)) { throw "Contrato FIX15 ausente: $required" }
}

[IO.File]::WriteAllText($path,$text,(New-Object Text.UTF8Encoding($false)))
Write-Host 'FIX15_ADMIN_AUTHORITY_TRANSFORM_PASS'
