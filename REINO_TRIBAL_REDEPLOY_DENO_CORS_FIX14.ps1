param(
  [string]$Repositorio = 'kaalflash12/reinos-tribais-online',
  [string]$BackendCommit = '25c61fdacf715399c7b1db5aabced5efc7db2485',
  [string]$DenoOrg = 'mestrederpg35',
  [string]$DenoApp = 'reino-tribal-api',
  [string]$DenoVersion = '2.9.5',
  [string]$DenoExeOverride = '',
  [switch]$ValidateOnly,
  [switch]$AuthTransportTest
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$ToolRoot = Join-Path $env:LOCALAPPDATA 'ReinoTribalTools'
$PortableDeno = Join-Path (Join-Path $ToolRoot ("deno-$DenoVersion")) 'deno.exe'
$DenoExe = if ($DenoExeOverride) { $DenoExeOverride } elseif (Test-Path $PortableDeno) { $PortableDeno } else { $cmd = Get-Command deno.exe -ErrorAction SilentlyContinue; if ($cmd) { $cmd.Source } else { $PortableDeno } }
$CurlCmd = Get-Command curl.exe -ErrorAction SilentlyContinue
$WorkRoot = Join-Path $env:TEMP ('reino-tribal-cors-fix14-' + [Guid]::NewGuid().ToString('N'))
$Backend = "https://$DenoApp.$DenoOrg.deno.net"
$Frontend = 'https://kaalflash12.github.io/reinos-tribais-online/'

function Etapa([string]$Texto) { Write-Host "`n=== $Texto ===" -ForegroundColor Cyan }
function Ok([string]$Texto) { Write-Host "PASS: $Texto" -ForegroundColor Green }
function Aviso([string]$Texto) { Write-Host "AVISO: $Texto" -ForegroundColor Yellow }
function Falhar([string]$Texto) { throw $Texto }

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

function Deno-PostJsonRaw {
  param([Parameter(Mandatory=$true)][string]$Url,[Parameter(Mandatory=$true)][hashtable]$Body)
  if (-not $CurlCmd) { Falhar 'curl.exe nao foi encontrado no Windows; o FIX14 nao volta a usar HttpWebRequest.' }

  $id = [Guid]::NewGuid().ToString('N')
  $reqFile = Join-Path $env:TEMP ("rt-deno-auth-$id-request.json")
  $respFile = Join-Path $env:TEMP ("rt-deno-auth-$id-response.json")
  $json = $Body | ConvertTo-Json -Depth 20 -Compress
  [IO.File]::WriteAllText($reqFile,$json,(New-Object Text.UTF8Encoding($false)))

  try {
    $last = ''
    for ($attempt=1; $attempt -le 5; $attempt++) {
      Remove-Item $respFile -Force -ErrorAction SilentlyContinue
      $r = Executar-Nativo -Exe $CurlCmd.Source -Args @(
        '--silent','--show-error','--location','--http1.1','--tlsv1.2',
        '--connect-timeout','20','--max-time','60',
        '-H','Content-Type: application/json',
        '-H','Accept: application/json',
        '--data-binary',("@" + $reqFile),
        '--output',$respFile,
        '--write-out','%{http_code}',
        $Url
      ) -TimeoutSec 75 -Rotulo "Deno HTTPS tentativa $attempt/5"

      $bodyText = if (Test-Path $respFile) { [IO.File]::ReadAllText($respFile) } else { '' }
      $status = 0
      if ($r.Stdout -match '^[0-9]{3}$') { $status = [int]$r.Stdout }
      if ($r.Code -eq 0 -and $status -gt 0) {
        return [pscustomobject]@{ Ok=($status -ge 200 -and $status -lt 300); Status=$status; Text=[string]$bodyText }
      }

      $last = "curl exit=$($r.Code); http=$status; stderr=$($r.Stderr); body=$bodyText"
      if ($attempt -lt 5) { Start-Sleep -Seconds ([Math]::Min(8,$attempt * 2)) }
    }
    return [pscustomobject]@{ Ok=$false; Status=0; Text=("Falha de transporte HTTPS apos 5 tentativas. " + $last) }
  } finally {
    Remove-Item $reqFile,$respFile -Force -ErrorAction SilentlyContinue
  }
}

function Novo-DenoChallenge {
  $verifier = [Guid]::NewGuid().ToString()
  $sha = [Security.Cryptography.SHA256]::Create()
  try { $challenge = [Convert]::ToBase64String($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($verifier))) }
  finally { $sha.Dispose() }
  return [pscustomobject]@{ Verifier=$verifier; Challenge=$challenge }
}

function Testar-DenoAuthTransport {
  $pair = Novo-DenoChallenge
  $probe = Deno-PostJsonRaw -Url 'https://console.deno.com/auth/interactive' -Body @{ challenge=$pair.Challenge }
  if (-not $probe.Ok) { Falhar "Transporte FIX14 para auth/interactive falhou HTTP $($probe.Status).`n$($probe.Text)" }
  try { $meta = $probe.Text | ConvertFrom-Json } catch { Falhar 'auth/interactive respondeu, mas o JSON veio invalido.' }
  if (-not [string]$meta.code -or -not [string]$meta.exchangeToken) { Falhar 'auth/interactive nao retornou code/exchangeToken no smoke de transporte.' }
  Ok 'Transporte HTTPS do Deno auth/interactive passou via curl.exe.'
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

  Write-Host 'Abrindo o login oficial do Deno Deploy. Apenas confirme o acesso.' -ForegroundColor Yellow
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

function Baixar-BackendPinado {
  param([Parameter(Mandatory=$true)][string]$Destino)
  foreach ($relative in @('deno.json','package.json','deno/main.js','api/reino.js','api/admin.js','backend/turso/schema.sql')) {
    $dest = Join-Path $Destino ($relative -replace '/','\')
    New-Item -ItemType Directory -Force -Path (Split-Path $dest -Parent) | Out-Null
    $url = "https://raw.githubusercontent.com/$Repositorio/$BackendCommit/$relative"
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $dest -TimeoutSec 120
    if (-not (Test-Path $dest) -or (Get-Item $dest).Length -eq 0) { Falhar "Download vazio: $relative" }
  }

  $denoConfigPath = Join-Path $Destino 'deno.json'
  $denoConfig = Get-Content -Raw -Path $denoConfigPath | ConvertFrom-Json
  if ($denoConfig.PSObject.Properties['deploy']) {
    $denoConfig.PSObject.Properties.Remove('deploy')
    [IO.File]::WriteAllText($denoConfigPath,($denoConfig | ConvertTo-Json -Depth 50),(New-Object Text.UTF8Encoding($false)))
  }
  $check = Executar-Nativo -Exe $DenoExe -Args @('check','deno/main.js') -Diretorio $Destino -TimeoutSec 180 -Rotulo 'Deno check backend FIX14'
  Exigir-Sucesso $check 'Backend FIX14 nao passou no deno check.'
  Ok 'Seis arquivos do backend CORS pinado baixados e validados.'
}

function Testar-Publico {
  $health = $null
  for ($i=1; $i -le 20; $i++) {
    try {
      $health = Invoke-RestMethod -Uri "$Backend/health" -Method Get -TimeoutSec 30
      if ($health.ok -and $health.runtime -eq 'deno-deploy') { break }
    } catch { $health = $null }
    Start-Sleep -Seconds 3
  }
  if (-not $health -or -not $health.ok -or $health.runtime -ne 'deno-deploy') { Falhar 'Health publico Deno nao passou apos redeploy.' }

  $apiHealth = Invoke-RestMethod -Uri "$Backend/api/reino" -Method Post -ContentType 'application/json' -Body '{"action":"health"}' -TimeoutSec 30
  if (-not $apiHealth.ok -or $apiHealth.database -ne 'turso') { Falhar 'Health publico Turso nao passou apos redeploy.' }

  $corsHeaders = @{
    Origin = 'https://kaalflash12.github.io'
    'Access-Control-Request-Method' = 'POST'
    'Access-Control-Request-Headers' = 'content-type,authorization'
  }
  $preflight = Invoke-WebRequest -UseBasicParsing -Uri "$Backend/api/reino" -Method Options -Headers $corsHeaders -TimeoutSec 30
  if ([int]$preflight.StatusCode -ne 204) { Falhar "CORS preflight retornou HTTP $($preflight.StatusCode), esperado 204." }
  $allowOrigin = [string]$preflight.Headers['Access-Control-Allow-Origin']
  if ($allowOrigin -ne 'https://kaalflash12.github.io') { Falhar "CORS allow-origin incorreto: $allowOrigin" }
  Ok 'Health Deno + Turso + CORS 204 passaram publicamente.'
}

try {
  Etapa 'FIX14 - redeploy Deno isolado com transporte robusto'
  if (-not (Test-Path $DenoExe)) { Falhar "Deno $DenoVersion nao encontrado em $DenoExe" }
  if (-not $CurlCmd) { Falhar 'curl.exe nao encontrado no Windows.' }
  $version = Executar-Nativo -Exe $DenoExe -Args @('--version') -TimeoutSec 20 -Rotulo 'Deno 2.9.5'
  Exigir-Sucesso $version 'Deno nao executou.'
  if ($version.Text -notmatch "deno $([regex]::Escape($DenoVersion))") { Falhar "Versao Deno inesperada: $($version.Text)" }

  if ($AuthTransportTest) {
    Testar-DenoAuthTransport
    Write-Host "`nREINO_TRIBAL_FIX14_AUTH_TRANSPORT_PASS" -ForegroundColor Green
    return
  }

  New-Item -ItemType Directory -Force -Path $WorkRoot | Out-Null
  Baixar-BackendPinado -Destino $WorkRoot

  if ($ValidateOnly) {
    Ok 'FIX14 ValidateOnly concluido; nenhum deploy foi feito.'
    return
  }

  Garantir-DenoAuth
  $app = Executar-Nativo -Exe $DenoExe -Args @('deploy','apps','get','--org',$DenoOrg,'--app',$DenoApp,'--json','--non-interactive') -TimeoutSec 60 -Rotulo 'Validar app Deno existente'
  Exigir-Sucesso $app 'App Deno reino-tribal-api nao foi encontrado.'

  Etapa 'Publicando somente o backend CORS corrigido'
  $deploy = Executar-Nativo -Exe $DenoExe -Args @('deploy','--org',$DenoOrg,'--app',$DenoApp,'--prod','--non-interactive') -Diretorio $WorkRoot -TimeoutSec 600 -Rotulo 'Deno deploy FIX14'
  Exigir-Sucesso $deploy 'Redeploy Deno FIX14 falhou.'

  Etapa 'Validacao publica FIX14'
  Testar-Publico
  Write-Host "`nREINO_TRIBAL_FIX14_PUBLICADO_E_VALIDADO" -ForegroundColor Green
  Write-Host "Backend: $Backend" -ForegroundColor Green
  Write-Host "Frontend: $Frontend" -ForegroundColor Green
} finally {
  $env:DENO_DEPLOY_TOKEN = ''
  Remove-Item $WorkRoot -Recurse -Force -ErrorAction SilentlyContinue
}
