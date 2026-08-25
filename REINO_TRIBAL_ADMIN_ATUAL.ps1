param(
  [string]$Repositorio = 'kaalflash12/reinos-tribais-online',
  [string]$BackendCommit = 'd5d1edadd9f33b612a233c4feed0e06ec97203bc',
  [string]$DenoOrg = 'mestrederpg35',
  [string]$DenoApp = 'reino-tribal-api',
  [string]$DenoVersion = '2.9.5',
  [string]$DenoExeOverride = '',
  [switch]$ValidateOnly,
  [switch]$PreflightOnly,
  [switch]$IdentityOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$ToolRoot = Join-Path $env:LOCALAPPDATA 'ReinoTribalTools'
$PortableDeno = Join-Path (Join-Path $ToolRoot ("deno-$DenoVersion")) 'deno.exe'
$DenoExe = if ($DenoExeOverride) { $DenoExeOverride } elseif (Test-Path $PortableDeno) { $PortableDeno } else { $cmd = Get-Command deno.exe -ErrorAction SilentlyContinue; if ($cmd) { $cmd.Source } else { $PortableDeno } }
$CurlCmd = Get-Command curl.exe -ErrorAction SilentlyContinue
$WorkRoot = Join-Path $env:TEMP ('reino-tribal-admin-fix17-' + [Guid]::NewGuid().ToString('N'))
$Backend = "https://$DenoApp.$DenoOrg.deno.net"
$Frontend = 'https://kaalflash12.github.io/reinos-tribais-online/'
$CredDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'ReinoTribal'
$CredFile = Join-Path $CredDir 'CREDENCIAIS_ADMIN_REINO_TRIBAL.txt'
$ExecutorVersion = 'FIX17'
$ExecutorContract = 'ADMIN_AUTHORITY_CORS_CANONICAL'
$ExpectedBackend = 'https://reino-tribal-api.mestrederpg35.deno.net'
$SelfPath = [string]$MyInvocation.MyCommand.Path
$SelfLeaf = if ($SelfPath) { Split-Path $SelfPath -Leaf } else { '<interactive>' }
$ExecutionMarker = Join-Path $env:TEMP 'REINO_TRIBAL_EXECUTOR_ATIVO.txt'

function Etapa([string]$Texto) { Write-Host "`n=== $Texto ===" -ForegroundColor Cyan }
function Ok([string]$Texto) { Write-Host "PASS: $Texto" -ForegroundColor Green }
function Falhar([string]$Texto) { throw $Texto }
function Mostrar-Identidade {
  Write-Host ''
  Write-Host '=== REINO TRIBAL EXECUTOR CANONICO ===' -ForegroundColor Cyan
  Write-Host ('VERSAO: ' + $ExecutorVersion) -ForegroundColor Green
  Write-Host ('CONTRATO: ' + $ExecutorContract) -ForegroundColor DarkGray
  Write-Host ('ARQUIVO: ' + $SelfPath) -ForegroundColor Yellow
  Write-Host ('PID: ' + $PID) -ForegroundColor DarkGray
  Write-Host ('BACKEND: ' + $Backend) -ForegroundColor DarkGray
  Write-Host ('BACKEND COMMIT: ' + $BackendCommit) -ForegroundColor DarkGray
}

function Limpar-CopiasLegadas {
  $patterns = @(
    'RT_ADMIN_FIX15*.ps1',
    'RT_ADMIN_FIX16*.ps1',
    'REINO_TRIBAL_ADMIN_FIX15*.ps1',
    'REINO_TRIBAL_ADMIN_FIX16*.ps1',
    'REINO_TRIBAL_RESUMIR_POS_DEPLOY_FIX11*.ps1',
    'RT_FIX13*.ps1',
    'RT_FIX14*.ps1'
  )
  foreach ($pattern in $patterns) {
    Get-ChildItem -LiteralPath $env:TEMP -Filter $pattern -File -ErrorAction SilentlyContinue | ForEach-Object {
      if (-not $SelfPath -or $_.FullName -ne $SelfPath) {
        Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
      }
    }
  }
}

Mostrar-Identidade
if ($SelfLeaf -match '(?i)FIX1[56]') {
  Falhar ('FIX17 recusou nome de arquivo legado: ' + $SelfLeaf + '. Baixe o executor canonico novamente.')
}
if ($Backend -ne $ExpectedBackend) {
  Falhar ('Backend inesperado no FIX17: ' + $Backend)
}
Limpar-CopiasLegadas
$markerText = @(
  ('version=' + $ExecutorVersion),
  ('contract=' + $ExecutorContract),
  ('path=' + $SelfPath),
  ('pid=' + $PID),
  ('backend=' + $Backend),
  ('backend_commit=' + $BackendCommit),
  ('started_utc=' + [DateTime]::UtcNow.ToString('o'))
) -join [Environment]::NewLine
[IO.File]::WriteAllText($ExecutionMarker,$markerText,(New-Object Text.UTF8Encoding($false)))
if ($IdentityOnly) {
  Ok 'REINO_TRIBAL_FIX17_IDENTITY_PASS'
  return
}

function Quote-Arg([string]$Value) {
  if ($null -eq $Value) { return '""' }
  if ($Value -notmatch '[\s"]') { return $Value }
  return '"' + ($Value -replace '(\\*)"','$1$1\"' -replace '(\\+)$','$1$1') + '"'
}

function Stop-Tree([int]$ProcessId) {
  try { & "$env:SystemRoot\System32\taskkill.exe" /PID $ProcessId /T /F *> $null } catch {}
}

function Executar-Nativo {
  param(
    [Parameter(Mandatory=$true)][string]$Exe,
    [string[]]$Args = @(),
    [int]$TimeoutSec = 90,
    [string]$Diretorio = '',
    [string]$Rotulo = ''
  )
  $label = if ($Rotulo) { $Rotulo } else { Split-Path $Exe -Leaf }
  Write-Host "EXECUTANDO [limite ${TimeoutSec}s]: $label" -ForegroundColor DarkCyan
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $Exe
  $psi.Arguments = (($Args | ForEach-Object { Quote-Arg ([string]$_) }) -join ' ')
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.RedirectStandardInput = $true
  $psi.CreateNoWindow = $true
  if ($Diretorio) { $psi.WorkingDirectory = $Diretorio }
  $p = New-Object System.Diagnostics.Process
  $p.StartInfo = $psi
  if (-not $p.Start()) { Falhar "Nao foi possivel iniciar $label." }
  $p.StandardInput.Close()
  $outTask = $p.StandardOutput.ReadToEndAsync()
  $errTask = $p.StandardError.ReadToEndAsync()
  $elapsed = 0
  while (-not $p.WaitForExit(5000)) {
    $elapsed += 5
    Write-Host "... ainda executando: $label (${elapsed}s/${TimeoutSec}s)" -ForegroundColor DarkGray
    if ($elapsed -ge $TimeoutSec) {
      Stop-Tree $p.Id
      return [pscustomobject]@{ Code=124; Stdout=''; Stderr=''; Text="TIMEOUT apos ${TimeoutSec}s: $label"; TimedOut=$true }
    }
  }
  $stdout = $outTask.GetAwaiter().GetResult()
  $stderr = $errTask.GetAwaiter().GetResult()
  return [pscustomobject]@{
    Code=[int]$p.ExitCode
    Stdout=([string]$stdout).Trim()
    Stderr=([string]$stderr).Trim()
    Text=(($stdout + "`n" + $stderr).Trim())
    TimedOut=$false
  }
}

function Exigir-Sucesso($Resultado,[string]$Mensagem) {
  if ($Resultado.Code -ne 0) { Falhar "$Mensagem`n$($Resultado.Text)" }
}

function Novo-Segredo([int]$Bytes = 32) {
  $buf = New-Object byte[] $Bytes
  $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
  try { $rng.GetBytes($buf) } finally { $rng.Dispose() }
  return ([Convert]::ToBase64String($buf).TrimEnd('=').Replace('+','-').Replace('/','_'))
}

function Curl-Json {
  param(
    [Parameter(Mandatory=$true)][string]$Url,
    [Parameter(Mandatory=$true)][string]$Json,
    [string]$Bearer = '',
    [int]$Attempts = 5
  )
  if (-not $CurlCmd) { Falhar 'curl.exe nao encontrado no Windows.' }
  $id = [Guid]::NewGuid().ToString('N')
  $reqFile = Join-Path $env:TEMP ("rt-fix17-$id-request.json")
  $respFile = Join-Path $env:TEMP ("rt-fix17-$id-response.json")
  [IO.File]::WriteAllText($reqFile,$Json,(New-Object Text.UTF8Encoding($false)))
  try {
    $last = ''
    for ($attempt=1; $attempt -le $Attempts; $attempt++) {
      Remove-Item $respFile -Force -ErrorAction SilentlyContinue
      $args = @(
        '--silent','--show-error','--location','--http1.1','--tlsv1.2',
        '--connect-timeout','20','--max-time','60',
        '-H','Content-Type: application/json',
        '-H','Accept: application/json'
      )
      if ($Bearer) { $args += @('-H',('Authorization: Bearer ' + $Bearer)) }
      $args += @('--data-binary',('@' + $reqFile),'--output',$respFile,'--write-out','%{http_code}',$Url)
      $r = Executar-Nativo -Exe $CurlCmd.Source -Args $args -TimeoutSec 75 -Rotulo "HTTPS JSON tentativa $attempt/$Attempts"
      $bodyText = if (Test-Path $respFile) { [IO.File]::ReadAllText($respFile) } else { '' }
      $status = 0
      if ($r.Stdout -match '^[0-9]{3}$') { $status = [int]$r.Stdout }
      if ($r.Code -eq 0 -and $status -gt 0) {
        return [pscustomobject]@{ Ok=($status -ge 200 -and $status -lt 300); Status=$status; Text=[string]$bodyText }
      }
      $last = "curl exit=$($r.Code); http=$status; stderr=$($r.Stderr); body=$bodyText"
      if ($attempt -lt $Attempts) { Start-Sleep -Seconds ([Math]::Min(8,$attempt * 2)) }
    }
    return [pscustomobject]@{ Ok=$false; Status=0; Text=("Falha HTTPS apos $Attempts tentativas. " + $last) }
  } finally {
    Remove-Item $reqFile,$respFile -Force -ErrorAction SilentlyContinue
  }
}

function Deno-PostJsonRaw {
  param([Parameter(Mandatory=$true)][string]$Url,[Parameter(Mandatory=$true)][hashtable]$Body)
  return Curl-Json -Url $Url -Json ($Body | ConvertTo-Json -Depth 20 -Compress) -Attempts 5
}

function Novo-DenoChallenge {
  $verifier = [Guid]::NewGuid().ToString()
  $sha = [Security.Cryptography.SHA256]::Create()
  try { $challenge = [Convert]::ToBase64String($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($verifier))) }
  finally { $sha.Dispose() }
  return [pscustomobject]@{ Verifier=$verifier; Challenge=$challenge }
}

function Garantir-DenoAuth {
  $existing = [string]$env:DENO_DEPLOY_TOKEN
  if ($existing) {
    $whoExisting = Executar-Nativo -Exe $DenoExe -Args @('deploy','whoami','--json','--non-interactive') -TimeoutSec 60 -Rotulo 'Validar token Deno existente'
    if ($whoExisting.Code -eq 0) { Ok 'Token Deno existente aceito.'; return }
    $env:DENO_DEPLOY_TOKEN = ''
  }

  $pair = Novo-DenoChallenge
  $beginAuth = Deno-PostJsonRaw -Url 'https://console.deno.com/auth/interactive' -Body @{ challenge=$pair.Challenge }
  if (-not $beginAuth.Ok) { Falhar "Deno auth/interactive falhou HTTP $($beginAuth.Status).`n$($beginAuth.Text)" }
  try { $authMeta = $beginAuth.Text | ConvertFrom-Json } catch { Falhar 'Deno auth/interactive retornou JSON invalido.' }
  $deviceCode = [string]$authMeta.code
  $exchangeToken = [string]$authMeta.exchangeToken
  if (-not $deviceCode -or -not $exchangeToken) { Falhar 'Deno auth/interactive nao retornou code/exchangeToken.' }

  Write-Host 'Abrindo o login oficial do Deno Deploy. Confirme o acesso no navegador.' -ForegroundColor Yellow
  Start-Process ('https://console.deno.com/auth?code=' + [Uri]::EscapeDataString($deviceCode))

  $deadline = [DateTime]::UtcNow.AddMinutes(5)
  $denoToken = ''
  while ([DateTime]::UtcNow -lt $deadline -and -not $denoToken) {
    Start-Sleep -Seconds 2
    $exchange = Deno-PostJsonRaw -Url 'https://console.deno.com/auth/exchange' -Body @{ exchangeToken=$exchangeToken; verifier=$pair.Verifier }
    if ($exchange.Ok) {
      try { $exchangeMeta = $exchange.Text | ConvertFrom-Json } catch { Falhar 'Deno auth/exchange retornou JSON invalido.' }
      $denoToken = [string]$exchangeMeta.token
      break
    }
    $pendingCode = ''
    try { $pendingCode = [string](($exchange.Text | ConvertFrom-Json).code) } catch {}
    if ($pendingCode -ne 'AUTHORIZATION_PENDING') { Falhar "Deno auth/exchange falhou HTTP $($exchange.Status).`n$($exchange.Text)" }
  }
  if (-not $denoToken) { Falhar 'Tempo de confirmacao do Deno expirou.' }
  $env:DENO_DEPLOY_TOKEN = $denoToken
  $who = Executar-Nativo -Exe $DenoExe -Args @('deploy','whoami','--json','--non-interactive') -TimeoutSec 60 -Rotulo 'Validar sessao Deno'
  Exigir-Sucesso $who 'Token Deno nao foi aceito.'
  Ok 'Login Deno confirmado.'
}

function Baixar-BackendPinado([string]$Destino) {
  foreach ($relative in @('deno.json','package.json','deno/main.js','api/reino.js','api/admin.js','backend/turso/schema.sql')) {
    $dest = Join-Path $Destino ($relative -replace '/','\')
    New-Item -ItemType Directory -Force -Path (Split-Path $dest -Parent) | Out-Null
    $url = "https://raw.githubusercontent.com/$Repositorio/$BackendCommit/$relative"
    $r = Executar-Nativo -Exe $CurlCmd.Source -Args @(
      '--fail','--silent','--show-error','--location','--http1.1','--tlsv1.2',
      '--retry','4','--retry-all-errors','--connect-timeout','20','--max-time','120',
      '--output',$dest,$url
    ) -TimeoutSec 150 -Rotulo "Baixar $relative"
    Exigir-Sucesso $r "Falha baixando backend pinado: $relative"
    if (-not (Test-Path $dest) -or (Get-Item $dest).Length -eq 0) { Falhar "Download vazio: $relative" }
  }

  $denoConfigPath = Join-Path $Destino 'deno.json'
  $denoConfig = Get-Content -Raw -Path $denoConfigPath | ConvertFrom-Json
  if ($denoConfig.PSObject.Properties['deploy']) {
    $denoConfig.PSObject.Properties.Remove('deploy')
    [IO.File]::WriteAllText($denoConfigPath,($denoConfig | ConvertTo-Json -Depth 50),(New-Object Text.UTF8Encoding($false)))
  }

  $reino = [IO.File]::ReadAllText((Join-Path $Destino 'api\reino.js'))
  foreach ($needle in @(
    'const passwordMatches = verifyPassword(password, existing.password_hash);',
    "role='admin',disabled=0",
    'DELETE FROM rt_sessions WHERE user_id=?',
    'normalizeUsername(identifier) === ADMIN_USERNAME) await ensureAdmin();'
  )) { if (-not $reino.Contains($needle)) { Falhar "Backend pinado nao contem contrato FIX15: $needle" } }

  $check = Executar-Nativo -Exe $DenoExe -Args @('check','deno/main.js') -Diretorio $Destino -TimeoutSec 180 -Rotulo 'Deno check backend FIX15'
  Exigir-Sucesso $check 'Backend FIX15 nao passou no deno check.'
  Ok 'Backend FIX15 pinado e validado.'
}

function Testar-Preflight {
  $preflightUri = [Uri]($Backend.TrimEnd('/') + '/api/reino')
  if (-not $preflightUri.IsAbsoluteUri -or [string]::IsNullOrWhiteSpace($preflightUri.Host)) {
    Falhar ("URL CORS invalida antes do curl: " + [string]$preflightUri)
  }
  $preflightUrl = $preflightUri.AbsoluteUri
  Write-Host ("CORS URL: " + $preflightUrl) -ForegroundColor DarkGray
  $headers = Join-Path $env:TEMP ('rt-fix17-cors-' + [Guid]::NewGuid().ToString('N') + '.txt')
  try {
    $r = Executar-Nativo -Exe $CurlCmd.Source -Args @(
      '--silent','--show-error','--http1.1','--tlsv1.2','--connect-timeout','20','--max-time','30',
      '--output','NUL','--dump-header',$headers,'--request','OPTIONS',
      '-H','Origin: https://kaalflash12.github.io',
      '-H','Access-Control-Request-Method: POST',
      '-H','Access-Control-Request-Headers: content-type,authorization',
      $preflightUrl
    ) -TimeoutSec 45 -Rotulo 'CORS preflight publico'
    Exigir-Sucesso $r 'CORS preflight nao respondeu.'
    $h = if (Test-Path $headers) { [IO.File]::ReadAllText($headers) } else { '' }
    if ($h -notmatch '(?im)^HTTP/\S+\s+204\b') { Falhar "CORS preflight nao retornou 204.`n$h" }
    if ($h -notmatch '(?im)^access-control-allow-origin:\s*https://kaalflash12\.github\.io\s*$') { Falhar "CORS allow-origin nao autoriza o GitHub Pages.`n$h" }
  } finally { Remove-Item $headers -Force -ErrorAction SilentlyContinue }
}

function Parse-JsonResult($Result,[string]$Label) {
  if (-not $Result.Ok) { Falhar "$Label falhou HTTP $($Result.Status).`n$($Result.Text)" }
  try { return ($Result.Text | ConvertFrom-Json) } catch { Falhar "$Label retornou JSON invalido.`n$($Result.Text)" }
}

if ($PreflightOnly) {
  Etapa 'FIX17 - teste publico isolado de CORS'
  if (-not $CurlCmd) { Falhar 'curl.exe nao encontrado no Windows.' }
  Testar-Preflight
  Ok 'FIX17_PREFLIGHT_PUBLICO_PASS'
  return
}

try {
  Etapa 'FIX17 - sincronizacao definitiva do administrador'
  if (-not (Test-Path $DenoExe)) { Falhar "Deno $DenoVersion nao encontrado em $DenoExe" }
  if (-not $CurlCmd) { Falhar 'curl.exe nao encontrado no Windows.' }
  $version = Executar-Nativo -Exe $DenoExe -Args @('--version') -TimeoutSec 20 -Rotulo 'Deno 2.9.5'
  Exigir-Sucesso $version 'Deno nao executou.'
  if ($version.Text -notmatch "deno $([regex]::Escape($DenoVersion))") { Falhar "Versao Deno inesperada: $($version.Text)" }

  New-Item -ItemType Directory -Force -Path $WorkRoot | Out-Null
  Baixar-BackendPinado -Destino $WorkRoot

  if ($ValidateOnly) {
    Ok 'FIX17 ValidateOnly concluido; nenhum secret e nenhum deploy foram alterados.'
    return
  }

  Garantir-DenoAuth
  $app = Executar-Nativo -Exe $DenoExe -Args @('deploy','apps','get','--org',$DenoOrg,'--app',$DenoApp,'--json','--non-interactive') -TimeoutSec 60 -Rotulo 'Validar app Deno existente'
  Exigir-Sucesso $app 'App Deno reino-tribal-api nao foi encontrado.'

  $adminPassword = 'RT!' + (Novo-Segredo 30)
  $recoveryKey = Novo-Segredo 48

  Etapa 'Atualizando autoridade ADM no Deno'
  $up1 = Executar-Nativo -Exe $DenoExe -Args @('deploy','env','update-value','RT_ADMIN_PASSWORD',$adminPassword,'--org',$DenoOrg,'--app',$DenoApp,'--non-interactive') -TimeoutSec 90 -Rotulo 'Atualizar RT_ADMIN_PASSWORD'
  Exigir-Sucesso $up1 'Deno recusou RT_ADMIN_PASSWORD.'
  $up2 = Executar-Nativo -Exe $DenoExe -Args @('deploy','env','update-value','RT_ADMIN_RECOVERY_KEY',$recoveryKey,'--org',$DenoOrg,'--app',$DenoApp,'--non-interactive') -TimeoutSec 90 -Rotulo 'Atualizar RT_ADMIN_RECOVERY_KEY'
  Exigir-Sucesso $up2 'Deno recusou RT_ADMIN_RECOVERY_KEY.'
  Ok 'Senha e recovery key atualizadas no Deno.'

  Etapa 'Publicando backend FIX15 pinado'
  $deploy = Executar-Nativo -Exe $DenoExe -Args @('deploy','--org',$DenoOrg,'--app',$DenoApp,'--prod','--non-interactive') -Diretorio $WorkRoot -TimeoutSec 600 -Rotulo 'Deno deploy FIX15'
  Exigir-Sucesso $deploy 'Redeploy Deno FIX15 falhou.'

  Etapa 'Validacao publica e login ADM real'
  $health = $null
  for ($i=1; $i -le 20; $i++) {
    $healthResult = Curl-Json -Url ($Backend + '/api/reino') -Json '{"action":"health"}' -Attempts 2
    if ($healthResult.Ok) {
      try { $health = $healthResult.Text | ConvertFrom-Json } catch { $health = $null }
      if ($health -and $health.ok -and $health.database -eq 'turso') { break }
    }
    Start-Sleep -Seconds 3
  }
  if (-not $health -or -not $health.ok -or $health.database -ne 'turso') { Falhar 'Health Deno/Turso nao passou apos FIX15.' }
  Testar-Preflight
  Ok 'Health Turso e CORS 204 passaram.'

  $loginJson = @{ action='login'; identifier='reinos_admin'; password=$adminPassword } | ConvertTo-Json -Compress
  $loginResult = Curl-Json -Url ($Backend + '/api/reino') -Json $loginJson -Attempts 5
  $login = Parse-JsonResult $loginResult 'Login reinos_admin'
  if (-not [string]$login.access_token) { Falhar 'Login ADM nao retornou access_token.' }
  if ([string]$login.user.role -ne 'admin' -or [string]$login.user.username -ne 'reinos_admin') { Falhar 'Login retornou usuario/role incorretos.' }
  $adminToken = [string]$login.access_token
  Ok 'Login reinos_admin passou com a senha nova.'

  $statusResult = Curl-Json -Url ($Backend + '/api/reino') -Json '{"action":"admin_status"}' -Bearer $adminToken -Attempts 3
  $status = Parse-JsonResult $statusResult 'admin_status'
  if (-not $status.ok) { Falhar 'admin_status nao confirmou ok.' }

  $dashResult = Curl-Json -Url ($Backend + '/api/admin') -Json '{"action":"dashboard"}' -Bearer $adminToken -Attempts 3
  $dash = Parse-JsonResult $dashResult 'dashboard ADM'
  if ($null -eq $dash) { Falhar 'Dashboard ADM nao retornou dados.' }
  Ok 'admin_status e dashboard passaram.'

  Etapa 'Gravando somente a credencial que passou no teste'
  New-Item -ItemType Directory -Force -Path $CredDir | Out-Null
  $cred = @(
    'REINO TRIBAL - CREDENCIAIS ADMINISTRATIVAS VALIDAS',
    ('Validado em: ' + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')),
    ('Backend FIX15: ' + $BackendCommit),
    ('Backend: ' + $Backend),
    ('Frontend: ' + $Frontend),
    'Usuario ADM: reinos_admin',
    ('Senha ADM: ' + $adminPassword),
    ('Recovery Key: ' + $recoveryKey),
    'VALIDACAO: login + admin_status + dashboard = PASS'
  ) -join [Environment]::NewLine
  [IO.File]::WriteAllText($CredFile,$cred,(New-Object Text.UTF8Encoding($true)))
  Ok "Credenciais validas gravadas em: $CredFile"
  try { Start-Process notepad.exe -ArgumentList ('"' + $CredFile + '"') } catch {}

  Write-Host "`nREINO_TRIBAL_ADMIN_FIX17_VALIDADO" -ForegroundColor Green
  Write-Host "Frontend: $Frontend" -ForegroundColor Green
  Write-Host "Usuario: reinos_admin" -ForegroundColor Green
} finally {
  $env:DENO_DEPLOY_TOKEN = ''
  Remove-Item $WorkRoot -Recurse -Force -ErrorAction SilentlyContinue
}
