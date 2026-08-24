param([switch]$ValidateOnly)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$PinnedTursoLauncher = 'https://raw.githubusercontent.com/kaalflash12/reinos-tribais-online/d26bdec674705a61d00dec3704e7bbe7f0e5b7ff/RT_REINO_TRIBAL_TURSO_PESSOAL_20260824.ps1'
$BasePath = Join-Path $env:TEMP 'RT_REINO_TRIBAL_TURSO_V2_BASE_FIX4.ps1'
$BootstrapFinal = Join-Path $env:TEMP 'IMPLANTAR_REINO_TRIBAL_DENO_TURSO_FINAL.ps1'
$utf8Bom = New-Object Text.UTF8Encoding($true)

Write-Host '=== REINO TRIBAL FIX4 - DENO DEVICE AUTH SEM KEYCHAIN ===' -ForegroundColor Cyan
Write-Host 'Turso v2/v1 + Deno browser device flow + token apenas nesta execucao.' -ForegroundColor Green

@($BasePath,$BootstrapFinal) | ForEach-Object { Remove-Item $_ -Force -ErrorAction SilentlyContinue }
Invoke-WebRequest -UseBasicParsing -Uri $PinnedTursoLauncher -OutFile $BasePath -TimeoutSec 120
if (-not (Test-Path $BasePath) -or (Get-Item $BasePath).Length -le 0) { throw 'Falha baixando launcher Turso v2/v1 validado.' }
$raw=[IO.File]::ReadAllText($BasePath)
[IO.File]::WriteAllText($BasePath,$raw,$utf8Bom)

$tokens=$null;$errors=$null
[System.Management.Automation.Language.Parser]::ParseFile($BasePath,[ref]$tokens,[ref]$errors)|Out-Null
if($errors.Count){ throw ('Launcher Turso base nao passou no parser: '+(($errors|ForEach-Object{$_.Message}) -join '; ')) }

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $BasePath -ValidateOnly
if($LASTEXITCODE -ne 0){ throw "Launcher Turso v2/v1 ValidateOnly falhou: $LASTEXITCODE" }
if(-not(Test-Path $BootstrapFinal)){ throw 'Bootstrap final nao foi gerado.' }

$texto=[IO.File]::ReadAllText($BootstrapFinal).Replace("`r`n","`n")
$old=@'
  Aviso 'Se o Deno ainda nao estiver autenticado, confirme somente o login oficial que abrir no navegador.'
  $orgList = Executar-Nativo -Exe $DenoExe -Args @('deploy','orgs','list','--json') -TimeoutSec 300 -Rotulo 'Login/listar organizacoes Deno'
'@
$old=$old.Replace("`r`n","`n")
if(-not $texto.Contains($old)){ throw 'Ponto de autenticacao Deno antigo nao encontrado para FIX4.' }

$new=@'
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
    try {
      $resp = $req.GetResponse()
    } catch [Net.WebException] {
      $resp = $_.Exception.Response
      if (-not $resp) { throw }
    }
    try {
      $status = [int]$resp.StatusCode
      $reader = New-Object IO.StreamReader($resp.GetResponseStream())
      try { $bodyText = $reader.ReadToEnd() } finally { $reader.Dispose() }
      return [pscustomobject]@{ Ok = ($status -ge 200 -and $status -lt 300); Status = $status; Text = [string]$bodyText }
    } finally {
      if ($resp) { $resp.Close() }
    }
  }

  $denoToken = [string]$env:DENO_DEPLOY_TOKEN
  if ($denoToken) {
    $existingWho = Executar-Nativo -Exe $DenoExe -Args @('deploy','whoami','--json','--non-interactive') -TimeoutSec 60 -Rotulo 'Validar token Deno existente'
    if ($existingWho.Code -ne 0) {
      Aviso 'DENO_DEPLOY_TOKEN existente e invalido/expirado; novo login oficial sera aberto.'
      $env:DENO_DEPLOY_TOKEN = ''
      $denoToken = ''
    }
  }

  if (-not $denoToken) {
    $verifier = [Guid]::NewGuid().ToString()
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
      $challenge = [Convert]::ToBase64String($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($verifier)))
    } finally { $sha.Dispose() }

    $beginAuth = Deno-PostJsonRaw -Url 'https://console.deno.com/auth/interactive' -Body @{ challenge = $challenge }
    if (-not $beginAuth.Ok) { Falhar "Deno auth/interactive falhou HTTP $($beginAuth.Status).`n$($beginAuth.Text)" }
    try { $authMeta = $beginAuth.Text | ConvertFrom-Json } catch { Falhar "Deno auth/interactive retornou JSON invalido.`n$($beginAuth.Text)" }
    $deviceCode = [string]$authMeta.code
    $exchangeToken = [string]$authMeta.exchangeToken
    if (-not $deviceCode -or -not $exchangeToken) { Falhar 'Deno auth/interactive nao retornou code/exchangeToken.' }

    $denoAuthUrl = 'https://console.deno.com/auth?code=' + [Uri]::EscapeDataString($deviceCode)
    Write-Host 'Abrindo o login oficial do Deno Deploy no navegador. Apenas confirme o acesso.' -ForegroundColor Yellow
    Start-Process $denoAuthUrl

    $deadline = [DateTime]::UtcNow.AddMinutes(5)
    while ([DateTime]::UtcNow -lt $deadline -and -not $denoToken) {
      Start-Sleep -Seconds 2
      $exchange = Deno-PostJsonRaw -Url 'https://console.deno.com/auth/exchange' -Body @{ exchangeToken = $exchangeToken; verifier = $verifier }
      if ($exchange.Ok) {
        try { $exchangeMeta = $exchange.Text | ConvertFrom-Json } catch { Falhar "Deno auth/exchange retornou JSON invalido.`n$($exchange.Text)" }
        $denoToken = [string]$exchangeMeta.token
        if (-not $denoToken) { Falhar 'Deno auth/exchange concluiu sem retornar token.' }
        break
      }
      $pendingCode = ''
      try { $pendingCode = [string](($exchange.Text | ConvertFrom-Json).code) } catch {}
      if ($pendingCode -ne 'AUTHORIZATION_PENDING') {
        Falhar "Deno auth/exchange falhou HTTP $($exchange.Status).`n$($exchange.Text)"
      }
    }
    if (-not $denoToken) { Falhar 'Tempo de confirmacao do Deno expirou sem autorizacao.' }
    $env:DENO_DEPLOY_TOKEN = $denoToken
    Ok 'Login Deno confirmado automaticamente pelo navegador; token mantido somente nesta execucao.'
  }

  $who = Executar-Nativo -Exe $DenoExe -Args @('deploy','whoami','--json','--non-interactive') -TimeoutSec 60 -Rotulo 'Validar sessao Deno sem keychain'
  Exigir-Sucesso $who "Token Deno obtido pelo navegador nao foi aceito.`n$($who.Text)"

  $orgList = Executar-Nativo -Exe $DenoExe -Args @('deploy','orgs','list','--json','--non-interactive') -TimeoutSec 120 -Rotulo 'Listar organizacoes Deno autenticado'
'@
$new=$new.Replace("`r`n","`n")
$texto=$texto.Replace($old,$new)

# Todas as chamadas Deno seguintes herdam DENO_DEPLOY_TOKEN. Forca modo nao-interativo nas chamadas principais.
$texto=$texto.Replace("@('deploy','apps','get','--org',`$candidate,'--app',`$DenoApp,'--json')","@('deploy','apps','get','--org',`$candidate,'--app',`$DenoApp,'--json','--non-interactive')")
$texto=$texto.Replace("@('deploy','apps','get','--org',`$denoOrg,'--app',`$DenoApp,'--json')","@('deploy','apps','get','--org',`$denoOrg,'--app',`$DenoApp,'--json','--non-interactive')")
$texto=$texto.Replace("'--no-wait'`n    ) -Diretorio","'--no-wait','--non-interactive'`n    ) -Diretorio")
$texto=$texto.Replace("@('deploy','env','load','--replace',`$envFile,'--org',`$denoOrg,'--app',`$DenoApp)","@('deploy','env','load','--replace',`$envFile,'--org',`$denoOrg,'--app',`$DenoApp,'--non-interactive')")
$texto=$texto.Replace("@('deploy','env','update-contexts',`$name,'--org',`$denoOrg,'--app',`$DenoApp)","@('deploy','env','update-contexts',`$name,'--org',`$denoOrg,'--app',`$DenoApp,'--non-interactive')")
$texto=$texto.Replace("@('deploy','--org',`$denoOrg,'--app',`$DenoApp,'--prod')","@('deploy','--org',`$denoOrg,'--app',`$DenoApp,'--prod','--non-interactive')")

foreach($needle in @(
  "Deno-PostJsonRaw -Url 'https://console.deno.com/auth/interactive'",
  "Deno-PostJsonRaw -Url 'https://console.deno.com/auth/exchange'",
  '$env:DENO_DEPLOY_TOKEN = $denoToken',
  "'deploy','whoami','--json','--non-interactive'",
  "'deploy','orgs','list','--json','--non-interactive'",
  'Login Deno confirmado automaticamente pelo navegador; token mantido somente nesta execucao.',
  'TURSO_V2_V1_NO_INDEX_VALIDATE_PASS'
)){
  if(-not $texto.Contains($needle)){ throw "Contrato FIX4 ausente: $needle" }
}
foreach($forbidden in @(
  'NON_INTERACTIVE_REQUIRED',
  "Aviso 'Se o Deno ainda nao estiver autenticado, confirme somente o login oficial que abrir no navegador.'"
)){
  if($texto.Contains($forbidden)){ throw "Fluxo Deno antigo reapareceu: $forbidden" }
}

[IO.File]::WriteAllText($BootstrapFinal,$texto,$utf8Bom)
$tokens=$null;$errors=$null
[System.Management.Automation.Language.Parser]::ParseFile($BootstrapFinal,[ref]$tokens,[ref]$errors)|Out-Null
if($errors.Count){ throw ('Bootstrap FIX4 nao passou no parser: '+(($errors|ForEach-Object{$_.Message+' @ '+$_.Extent.StartLineNumber+':'+$_.Extent.StartColumnNumber}) -join "`n")) }

Write-Host 'PASS: DENO AUTH = DEVICE FLOW OFICIAL CAPTURADO PELO POWERSHELL.' -ForegroundColor Green
Write-Host 'PASS: DENO AUTH = ZERO KEYCHAIN E ZERO TTY NECESSARIO APOS LOGIN.' -ForegroundColor Green
Write-Host 'PASS: DENO AUTH = DENO_DEPLOY_TOKEN SOMENTE NA EXECUCAO.' -ForegroundColor Green
Write-Host 'PASS: TURSO = V2/V1 + ZERO INDEXACAO VAZIA MANTIDOS.' -ForegroundColor Green
Write-Host 'PASS: PARSER FINAL FIX4 VALIDADO.' -ForegroundColor Green

if($ValidateOnly){ Write-Host 'DENO_DEVICE_AUTH_FIX4_VALIDATE_PASS' -ForegroundColor Green; return }

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $BootstrapFinal
$code=$LASTEXITCODE
if($code -ne 0){ throw "FIX4 parou no proximo erro real. Codigo: $code" }
