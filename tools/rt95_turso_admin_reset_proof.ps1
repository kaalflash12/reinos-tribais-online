$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if([string]::IsNullOrWhiteSpace($env:TURSO_DATABASE_URL) -or [string]::IsNullOrWhiteSpace($env:TURSO_AUTH_TOKEN)){throw 'RT95_TURSO_SECRETS_MISSING'}
$root=Join-Path $env:RUNNER_TEMP 'rt95-admin-reset'
New-Item -ItemType Directory -Force $root|Out-Null
Push-Location $root
$backup=Join-Path $root 'backup.json'
$passFile=Join-Path $root 'password.txt'
$proofDir=Join-Path $root 'proof'
$browser=Join-Path $root 'rt90_admin_public_proof.mjs'
$pub=Join-Path $root 'rt95_public.pem'
$enc=Join-Path $root 'password.enc'
$artifact=Join-Path $env:RUNNER_TEMP 'RT95_FINAL_ADMIN_PROOF'
$committed=$false
try {
  npm init -y | Out-Null
  npm install --no-audit --no-fund @tursodatabase/serverless | Out-Null

  @'
import {connect} from '@tursodatabase/serverless';
import {randomBytes,scryptSync} from 'node:crypto';
import fs from 'node:fs';
const [backupPath,passwordPath]=process.argv.slice(2);
const db=connect({url:process.env.TURSO_DATABASE_URL,authToken:process.env.TURSO_AUTH_TOKEN});
const admin=await (await Promise.resolve(db.prepare("SELECT * FROM rt_users WHERE username='reinos_admin' LIMIT 1"))).get();
if(!admin) throw new Error('RT95_ADMIN_MISSING');
const sessions=await (await Promise.resolve(db.prepare('SELECT token_hash,user_id,expires_at,created_at,last_seen_at FROM rt_sessions WHERE user_id=?'))).all([admin.id]);
fs.writeFileSync(backupPath,JSON.stringify({admin:{id:admin.id,password_hash:admin.password_hash,role:admin.role,disabled:Number(admin.disabled||0),updated_at:admin.updated_at},sessions}),{mode:0o600});
const password='Rt95-'+randomBytes(24).toString('base64url')+'-A9!';
const salt=randomBytes(16).toString('hex');
const password_hash=`scrypt$${salt}$${scryptSync(password,salt,64).toString('hex')}`;
await (await Promise.resolve(db.prepare("UPDATE rt_users SET password_hash=?,role='admin',disabled=0,updated_at=? WHERE id=?"))).run([password_hash,new Date().toISOString(),admin.id]);
fs.writeFileSync(passwordPath,password,{mode:0o600});
console.log('RT95_TEMP_ADMIN_PASSWORD_HASH_SET');
await db.close?.();
'@ | Set-Content -Encoding UTF8 (Join-Path $root 'prepare.mjs')

  @'
import {connect} from '@tursodatabase/serverless';
import fs from 'node:fs';
const backup=JSON.parse(fs.readFileSync(process.argv[2],'utf8'));
const db=connect({url:process.env.TURSO_DATABASE_URL,authToken:process.env.TURSO_AUTH_TOKEN});
await (await Promise.resolve(db.prepare('UPDATE rt_users SET password_hash=?,role=?,disabled=?,updated_at=? WHERE id=?'))).run([backup.admin.password_hash,backup.admin.role,backup.admin.disabled,backup.admin.updated_at,backup.admin.id]);
await (await Promise.resolve(db.prepare('DELETE FROM rt_sessions WHERE user_id=?'))).run([backup.admin.id]);
for(const s of backup.sessions){await (await Promise.resolve(db.prepare('INSERT INTO rt_sessions(token_hash,user_id,expires_at,created_at,last_seen_at) VALUES (?,?,?,?,?)'))).run([s.token_hash,s.user_id,s.expires_at,s.created_at,s.last_seen_at]);}
console.log('RT95_ROLLBACK_COMPLETE');
await db.close?.();
'@ | Set-Content -Encoding UTF8 (Join-Path $root 'restore.mjs')

  @'
import {connect} from '@tursodatabase/serverless';
import fs from 'node:fs';
const backup=JSON.parse(fs.readFileSync(process.argv[2],'utf8'));
const db=connect({url:process.env.TURSO_DATABASE_URL,authToken:process.env.TURSO_AUTH_TOKEN});
const row=await (await Promise.resolve(db.prepare("SELECT id,username,role,disabled FROM rt_users WHERE username='reinos_admin' LIMIT 1"))).get();
if(!row||row.id!==backup.admin.id||row.role!=='admin'||Number(row.disabled||0)!==0)throw new Error('RT95_FINAL_ADMIN_STATE_INVALID');
await (await Promise.resolve(db.prepare('DELETE FROM rt_sessions WHERE user_id=?'))).run([row.id]);
console.log('RT95_FINAL_PASSWORD_COMMITTED_AND_OLD_SESSIONS_REVOKED');
await db.close?.();
'@ | Set-Content -Encoding UTF8 (Join-Path $root 'finalize.mjs')

  node (Join-Path $root 'prepare.mjs') $backup $passFile
  if($LASTEXITCODE -ne 0){throw 'RT95_PREPARE_FAILED'}
  $password=(Get-Content $passFile -Raw).Trim()
  if($password.Length -lt 24){throw 'RT95_PASSWORD_GENERATION_INVALID'}

  $body=@{action='login';identifier='reinos_admin';password=$password}|ConvertTo-Json -Compress
  try{
    $login=Invoke-RestMethod -Method Post -Uri 'https://reino-tribal-api.mestrederpg35.deno.net/api/reino' -Headers @{Origin='https://kaalflash12.github.io'} -ContentType 'application/json' -Body $body
  }catch{
    $status=$_.Exception.Response.StatusCode.value__
    Write-Host "RT95_USERNAME_LOGIN_HTTP=$status"
    throw 'RT95_USERNAME_LOGIN_REJECTED_AFTER_DB_RESET'
  }
  if([string]::IsNullOrWhiteSpace([string]$login.access_token) -or $login.user.username -ne 'reinos_admin' -or $login.user.role -ne 'admin'){throw 'RT95_LOGIN_RESPONSE_INVALID'}
  Write-Host 'RT95_USERNAME_PASSWORD_LOGIN_PASS'

  $statusBody=@{action='admin_status'}|ConvertTo-Json -Compress
  $status=Invoke-RestMethod -Method Post -Uri 'https://reino-tribal-api.mestrederpg35.deno.net/api/reino' -Headers @{Origin='https://kaalflash12.github.io';Authorization=('Bearer '+[string]$login.access_token)} -ContentType 'application/json' -Body $statusBody
  if(-not $status.ok){throw 'RT95_ADMIN_STATUS_API_FAILED'}
  Write-Host 'RT95_AUTHENTICATED_ADMIN_STATUS_PASS'

  curl.exe --fail --silent --show-error --location --retry 4 --retry-all-errors --output $browser 'https://raw.githubusercontent.com/kaalflash12/reinos-tribais-online/main/tools/rt90_admin_public_proof.mjs'
  if($LASTEXITCODE -ne 0){throw 'RT95_BROWSER_RUNNER_DOWNLOAD_FAILED'}
  $env:RT_FINAL_ADMIN_PASSWORD=$password
  $env:RT_FINAL_FRONTEND='https://kaalflash12.github.io/reinos-tribais-online/'
  $env:RT_FINAL_API='https://reino-tribal-api.mestrederpg35.deno.net'
  $env:RT_FINAL_PROOF_DIR=$proofDir
  try{
    deno run --allow-all $browser
    if($LASTEXITCODE -ne 0){throw 'RT95_PUBLIC_BROWSER_PROOF_FAILED'}
  }finally{
    $env:RT_FINAL_ADMIN_PASSWORD=''
    $env:RT_FINAL_FRONTEND=''
    $env:RT_FINAL_API=''
    $env:RT_FINAL_PROOF_DIR=''
  }
  $proof=Get-Content (Join-Path $proofDir 'PROVA_RT90_ADMIN_PUBLICO.json') -Raw|ConvertFrom-Json
  if(-not $proof.pass -or $proof.validate_only){throw 'RT95_PUBLIC_PROOF_NOT_PASS'}
  Write-Host 'RT95_REAL_PUBLIC_ADMIN_BROWSER_PASS'

  @'
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAsYtCZnQDttS2GqU+T4rT
1fc5xFNXHxsm4ie9Mkh3lYbrLSBsA7bNjfKqBtcAWvpOXz67pc9U1RIiobBb7w9Y
9vm6wFwvim5z2PgKoiegaP1vkxO5CgEt7D8/9Q3+1sVn7/7Imt/zBd0xbWzXm4tp
LGE+hOf7iYXWh7INDs5qU4RJfntRKzbvhCzfH/sAzaDQd8lQIxi8nrTMf8xGl+RW
4sKQCi2CdVZB3vF6TrhVz1ux5VqW1Kz6uQhPekXjAIVdN5ijtWx7jJ2jdtv1ruYr
gXPo67L9/QL5StXwnYN8vllQHKhSWwKb8sA31mWPyy3RS1wHKhyAEOdv4gGws8p8
DQIDAQAB
-----END PUBLIC KEY-----
'@ | Set-Content -Encoding ascii $pub
  $openssl=(Get-Command openssl.exe -ErrorAction SilentlyContinue)
  if(-not $openssl){$openssl=(Get-Command openssl -ErrorAction SilentlyContinue)}
  if(-not $openssl){throw 'RT95_OPENSSL_MISSING'}
  & $openssl.Source pkeyutl -encrypt -pubin -inkey $pub -in $passFile -out $enc -pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256
  if($LASTEXITCODE -ne 0 -or -not(Test-Path $enc)){throw 'RT95_PASSWORD_ENCRYPTION_FAILED'}
  $cipher=[Convert]::ToBase64String([IO.File]::ReadAllBytes($enc))
  Write-Host ('RT95_PASSWORD_CIPHERTEXT_BASE64='+$cipher)

  node (Join-Path $root 'finalize.mjs') $backup
  if($LASTEXITCODE -ne 0){throw 'RT95_FINALIZE_FAILED'}
  New-Item -ItemType Directory -Force $artifact|Out-Null
  Copy-Item (Join-Path $proofDir 'PROVA_RT90_ADMIN_PUBLICO.json') $artifact -Force
  Copy-Item (Join-Path $proofDir 'RT90_ADMIN_DASHBOARD_PUBLICO.png') $artifact -Force
  Copy-Item $enc (Join-Path $artifact 'RT95_ADMIN_PASSWORD_ENCRYPTED.bin') -Force
  @{pass=$true;username='reinos_admin';password_delivery='RSA-OAEP-SHA256 encrypted';old_admin_sessions_revoked=$true;public_browser_proof=$true;generated_at=(Get-Date).ToUniversalTime().ToString('o')}|ConvertTo-Json|Set-Content -Encoding UTF8 (Join-Path $artifact 'RT95_FINAL_SUMMARY.json')
  $committed=$true
  Write-Host 'REINO_TRIBAL_ADMIN_PUBLICO_RT95_PASS'
} finally {
  $env:RT_FINAL_ADMIN_PASSWORD=''
  if(-not $committed -and (Test-Path $backup)){
    Write-Host 'RT95: falha detectada; restaurando estado administrativo anterior.'
    node (Join-Path $root 'restore.mjs') $backup
    if($LASTEXITCODE -ne 0){Write-Error 'RT95_ROLLBACK_FAILED'}
  }
  Remove-Item $passFile,$backup -Force -ErrorAction SilentlyContinue
  Pop-Location
}
