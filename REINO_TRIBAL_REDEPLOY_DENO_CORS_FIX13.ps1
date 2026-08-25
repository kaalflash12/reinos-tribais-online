param(
  [string]$Repositorio = 'kaalflash12/reinos-tribais-online',
  [string]$Branch = '25c61fdacf715399c7b1db5aabced5efc7db2485',
  [string]$DenoOrg = 'mestrederpg35',
  [string]$DenoApp = 'reino-tribal-api',
  [string]$DenoVersion = '2.9.5',
  [string]$DenoExeOverride = '',
  [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$ToolRoot = Join-Path $env:LOCALAPPDATA 'ReinoTribalTools'
$DenoExe = if ($DenoExeOverride) { $DenoExeOverride } else { Join-Path (Join-Path $ToolRoot ("deno-$DenoVersion")) 'deno.exe' }
$WorkRoot = Join-Path $env:TEMP ('reino-tribal-cors-fix13-' + [Guid]::NewGuid().ToString('N'))
$Backend = "https://$DenoApp.$DenoOrg.deno.net"
$Frontend = 'https://kaalflash12.github.io/reinos-tribais-online/'

function Etapa([string]$Texto) { Write-Host "`n=== $Texto ===" -ForegroundColor Cyan }
function Ok([string]$Texto) { Write-Host "PASS: $Texto" -ForegroundColor Green }
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
  $json = $Body | ConvertTo-Json -Depth 20 -Compress
  $bytes = [Text.Encoding]::UTF8.GetBytes($json)
  $req = [Net.HttpWebRequest]::Create($Url)
  $req.Method = 'POST'
  $req.ContentType = 'application/json'
  $req.Accept = 'application/json'
  $req.ContentLength = $bytes.Length
  $stream = $req.GetRequestStream()
  try { $stream.Write($bytes,0,$bytes.Length) } finally { $stream.Dispose() }
  $resp = $null
  try { $resp = $req.GetResponse() }
  catch [Net.WebException] {
    $resp = $_.Exception.Response
    if (-not $resp) { throw }
  }
  try {
    $status = [int]$resp.StatusCode
    $reader = New-Object IO.StreamReader($resp.GetResponseStream())
    try { $bodyText = $reader.ReadToEnd() } finally { $reader.Dispose() }
    return [pscustomobject]@{ Ok=($status -ge 200 -and $status -lt 300); Status=$status; Text=[string]$bodyText }
  } finally { if ($resp) { $resp.Close() } }
}

function Garantir-DenoAuth {
  $existing = [string]$env:DENO_DEPLOY_TOKEN
  if ($existing) {
    $whoExisting = Executar-Nativo -Exe $DenoExe -Args @('deploy','whoami','--json','--non-interactive') -TimeoutSec 60 -Rotulo 'Validar token Deno existente'
    if ($whoExisting.Code -eq 0) { Ok 'Token Deno existente aceito.'; return }
    $env:DENO_DEPLOY_TOKEN = ''
  }

  $verifier = [Guid]::NewGuid().ToString()
  $sha = [Security.Cryptography.SHA256]::Create()
  try { $challenge = [Convert]::ToBase64String($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($verifier))) }
  finally { $sha.Dispose() }

  $beginAuth = Deno-PostJsonRaw -Url 'https://console.deno.com/auth/interactive' -Body @{ challenge=$challenge }
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
    $exchange = Deno-PostJsonRaw -Url 'https://console.deno.com/auth/exchange' -Body @{ exchangeToken=$exchangeToken; verifier=$verifier }
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

function Baixar-BackendAtual {
  param([Parameter(Mandatory=$true)][string]$Destino)
  foreach ($relative in @('deno.json','package.json','deno/main.js','api/reino.js','api/admin.js','backend/turso/schema.sql')) {
    $dest = Join-Path $Destino ($relative -replace '/','\')
    New-Item -ItemType Directory -Force -Path (Split-Path $dest -Parent) | Out-Null
    $url = "https://raw.githubusercontent.com/$Repositorio/$Branch/$relative"
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $dest -TimeoutSec 120
    if (-not (Test-Path $dest) -or (Get-Item $dest).Length -eq 0) { Falhar "Download vazio: $relative" }
  }

  $denoConfigPath = Join-Path $Destino 'deno.json'
  $denoConfig = Get-Content -Raw -Path $denoConfigPath | ConvertFrom-Json
  if ($denoConfig.PSObject.Properties['deploy']) {
    $denoConfig.PSObject.Properties.Remove('deploy')
    [IO.File]::WriteAllText($denoConfigPath,($denoConfig | ConvertTo-Json -Depth 50),(New-Object Text.UTF8Encoding($false)))
  }
  $check = Executar-Nativo -Exe $DenoExe -Args @('check','deno/main.js') -Diretorio $Destino -TimeoutSec 180 -Rotulo 'Deno check backend FIX13'
  Exigir-Sucesso $check 'Backend FIX13 nao passou no deno check.'
  Ok 'Seis arquivos do backend FIX13 pinado baixados e validados.'
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
  Etapa 'FIX13 - redeploy Deno isolado'
  if (-not (Test-Path $DenoExe)) { Falhar "Deno $DenoVersion nao encontrado em $DenoExe" }
  $version = Executar-Nativo -Exe $DenoExe -Args @('--version') -TimeoutSec 20 -Rotulo 'Deno 2.9.5'
  Exigir-Sucesso $version 'Deno nao executou.'
  if ($version.Text -notmatch "deno $([regex]::Escape($DenoVersion))") { Falhar "Versao Deno inesperada: $($version.Text)" }

  New-Item -ItemType Directory -Force -Path $WorkRoot | Out-Null
  Baixar-BackendAtual -Destino $WorkRoot

  if ($ValidateOnly) {
    Ok 'FIX13 ValidateOnly concluido; nenhum deploy foi feito.'
    return
  }

  Garantir-DenoAuth
  $app = Executar-Nativo -Exe $DenoExe -Args @('deploy','apps','get','--org',$DenoOrg,'--app',$DenoApp,'--json','--non-interactive') -TimeoutSec 60 -Rotulo 'Validar app Deno existente'
  Exigir-Sucesso $app 'App Deno reino-tribal-api nao foi encontrado.'

  Etapa 'Publicando somente o backend FIX13'
  $deploy = Executar-Nativo -Exe $DenoExe -Args @('deploy','--org',$DenoOrg,'--app',$DenoApp,'--prod','--non-interactive') -Diretorio $WorkRoot -TimeoutSec 600 -Rotulo 'Deno deploy FIX13'
  Exigir-Sucesso $deploy 'Redeploy Deno FIX13 falhou.'

  Etapa 'Validacao publica FIX13'
  Testar-Publico
  Write-Host "`nREINO_TRIBAL_FIX13_PUBLICADO_E_VALIDADO" -ForegroundColor Green
  Write-Host "Backend: $Backend" -ForegroundColor Green
  Write-Host "Frontend: $Frontend" -ForegroundColor Green
} finally {
  $env:DENO_DEPLOY_TOKEN = ''
  Remove-Item $WorkRoot -Recurse -Force -ErrorAction SilentlyContinue
}
