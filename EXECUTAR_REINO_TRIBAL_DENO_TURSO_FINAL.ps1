param([switch]$ValidateOnly)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Origem = 'https://raw.githubusercontent.com/kaalflash12/reinos-tribais-online/0a957ab795202a9e7542f44f11d6174a121b8f0d/IMPLANTAR_REINO_TRIBAL_DENO_TURSO.ps1'
$Destino = Join-Path $env:TEMP 'IMPLANTAR_REINO_TRIBAL_DENO_TURSO_FINAL.ps1'

Write-Host '=== REINO TRIBAL - DENO + TURSO + GITHUB PAGES ===' -ForegroundColor Cyan
Write-Host 'ZERO VERCEL / ZERO WSL / ZERO INFRAESTRUTURA DE OUTRO JOGO.' -ForegroundColor Green

Remove-Item $Destino -Force -ErrorAction SilentlyContinue
Invoke-WebRequest -UseBasicParsing -Uri $Origem -OutFile $Destino -TimeoutSec 120
if (-not (Test-Path $Destino) -or (Get-Item $Destino).Length -le 0) {
  throw 'Falha baixando o bootstrap final do Reino Tribal.'
}

$texto = [IO.File]::ReadAllText($Destino).Replace("`r`n","`n")
$proibidos = @('ver'+'cel','bw-v151','bacathegas','bacaworld','cloudflare','mongodb','neon','supabase.co')
foreach ($p in $proibidos) {
  if ($texto.IndexOf($p,[StringComparison]::OrdinalIgnoreCase) -ge 0) {
    throw "Bootstrap contem infraestrutura proibida: $p. Nada foi executado."
  }
}

# TURSO: substitui o prompt manual pelo mesmo protocolo de browser/callback usado pelo CLI oficial.
$tursoFuncMarker = 'function Turso-Request {'
$tursoFuncPos = $texto.IndexOf($tursoFuncMarker,[StringComparison]::Ordinal)
if ($tursoFuncPos -lt 0) { throw 'Ponto de injecao do login Turso nao encontrado. Nada foi executado.' }

$tursoHelper = @'
function Obter-TursoPlatformTokenBrowser {
  $state = Novo-Segredo 24
  $listener = $null
  $client = $null
  try {
    try {
      $listener = New-Object System.Net.Sockets.TcpListener -ArgumentList ([Net.IPAddress]::IPv6Any),0
      $listener.Server.DualMode = $true
      $listener.Start()
    } catch {
      if ($listener) { try { $listener.Stop() } catch {} }
      $listener = New-Object System.Net.Sockets.TcpListener -ArgumentList ([Net.IPAddress]::Any),0
      $listener.Start()
    }

    $port = ([Net.IPEndPoint]$listener.LocalEndpoint).Port
    $escapedState = [Uri]::EscapeDataString($state)
    $authUrl = "https://api.turso.tech?port=$port&redirect=true&type=cli&state=$escapedState"
    Write-Host 'Abrindo o login oficial do Turso no navegador. Apenas confirme o acesso.' -ForegroundColor Yellow
    Start-Process $authUrl

    $acceptTask = $listener.AcceptTcpClientAsync()
    if (-not $acceptTask.Wait([TimeSpan]::FromMinutes(5))) {
      Falhar 'Login Turso expirou antes da confirmacao no navegador.'
    }
    $client = $acceptTask.Result
    $stream = $client.GetStream()
    $reader = New-Object IO.StreamReader($stream,[Text.Encoding]::ASCII,$false,4096,$true)
    $requestLine = $reader.ReadLine()
    if (-not $requestLine -or $requestLine -notmatch '^GET\s+(\S+)\s+HTTP/') {
      Falhar 'Callback Turso veio em formato HTTP inesperado.'
    }

    $target = $Matches[1]
    $callbackUri = [Uri]("http://localhost:$port" + $target)
    $query = @{}
    foreach ($pair in ($callbackUri.Query.TrimStart('?') -split '&')) {
      if (-not $pair) { continue }
      $kv = $pair -split '=',2
      $key = [Uri]::UnescapeDataString(($kv[0] -replace '\+',' '))
      $value = if ($kv.Count -gt 1) { [Uri]::UnescapeDataString(($kv[1] -replace '\+',' ')) } else { '' }
      $query[$key] = $value
    }

    $returnedState = [string]$query['state']
    $jwt = [string]$query['jwt']
    $valid = ($returnedState -eq $state -and $jwt -match '^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$')
    $bodyText = if ($valid) { '<html><body><h2>Turso confirmado.</h2><p>Pode fechar esta aba.</p></body></html>' } else { '<html><body><h2>Falha na confirmacao Turso.</h2></body></html>' }
    $bodyBytes = [Text.Encoding]::UTF8.GetBytes($bodyText)
    $statusLine = if ($valid) { 'HTTP/1.1 200 OK' } else { 'HTTP/1.1 400 Bad Request' }
    $headerText = "$statusLine`r`nContent-Type: text/html; charset=utf-8`r`nContent-Length: $($bodyBytes.Length)`r`nConnection: close`r`n`r`n"
    $headerBytes = [Text.Encoding]::ASCII.GetBytes($headerText)
    $stream.Write($headerBytes,0,$headerBytes.Length)
    $stream.Write($bodyBytes,0,$bodyBytes.Length)
    $stream.Flush()

    if (-not $valid) {
      Falhar 'Callback Turso recusado: state ou JWT invalido.'
    }
  } finally {
    if ($client) { try { $client.Close() } catch {} }
    if ($listener) { try { $listener.Stop() } catch {} }
  }

  $validation = Turso-Request -Method GET -Path '/v1/auth/validate' -Token $jwt
  if ($null -eq $validation) { Falhar 'Turso nao confirmou a sessao autenticada.' }
  Ok 'Login Turso confirmado automaticamente pelo callback local.'
  return $jwt
}

'@
$tursoHelper = $tursoHelper.Replace("`r`n","`n")
$texto = $texto.Substring(0,$tursoFuncPos) + $tursoHelper + $texto.Substring($tursoFuncPos)

$tokenStartMarker = '  $platformToken = [string]$env:TURSO_PLATFORM_API_TOKEN'
$orgMarker = '  $orgs = @(Turso-Request'
$tokenStart = $texto.IndexOf($tokenStartMarker,[StringComparison]::Ordinal)
if ($tokenStart -lt 0) { throw 'Inicio do bloco de autenticacao Turso nao encontrado. Nada foi executado.' }
$orgPos = $texto.IndexOf($orgMarker,$tokenStart,[StringComparison]::Ordinal)
if ($orgPos -lt 0) { throw 'Fim do bloco de autenticacao Turso nao encontrado. Nada foi executado.' }
$tokenOriginal = $texto.Substring($tokenStart,$orgPos-$tokenStart)
if (-not $tokenOriginal.Contains("Read-Host 'Turso Platform API Token'")) {
  throw 'Contrato antigo do token Turso mudou; nada foi executado.'
}

$tokenNovo = @'
  $platformToken = [string]$env:TURSO_PLATFORM_API_TOKEN
  if (-not $platformToken) {
    $platformToken = Obter-TursoPlatformTokenBrowser
  } else {
    Ok 'Sessao Turso existente reutilizada.'
  }
  if ($platformToken.Length -lt 20) { Falhar 'Login Turso nao retornou token valido.' }

'@
$tokenNovo = $tokenNovo.Replace("`r`n","`n")
$texto = $texto.Substring(0,$tokenStart) + $tokenNovo + $texto.Substring($orgPos)

if ($texto.Contains("Read-Host 'Turso Platform API Token'")) {
  throw 'Prompt manual de token Turso ainda existe. Nada foi executado.'
}
foreach ($needle in @('Obter-TursoPlatformTokenBrowser','AcceptTcpClientAsync','https://api.turso.tech?port=','redirect=true&type=cli&state=','/v1/auth/validate','Start-Process $authUrl')) {
  if (-not $texto.Contains($needle)) { throw "Contrato do login Turso automatico ausente: $needle" }
}

# DENO: mantem a recuperacao unica de organizacao, sem loop.
$secaoMarcador = "Etapa 'Deno Deploy: app exclusivo do Reino Tribal'"
$envMarcador = '  $envFile = Join-Path $WorkRoot ''.env.reino-tribal.production'''
$codigoMarcador = '      $createCode = $LASTEXITCODE'

$secaoInicio = $texto.IndexOf($secaoMarcador,[StringComparison]::Ordinal)
if ($secaoInicio -lt 0) { throw 'Secao Deno nao encontrada. Nada foi executado.' }
$envInicio = $texto.IndexOf($envMarcador,$secaoInicio)
if ($envInicio -lt 0) { throw 'Fim da secao Deno nao encontrado. Nada foi executado.' }
$secaoOriginal = $texto.Substring($secaoInicio,$envInicio-$secaoInicio)
if (([regex]::Matches($secaoOriginal,'deploy create \. --app \$DenoApp')).Count -ne 1) {
  throw 'Secao Deno original nao contem exatamente uma criacao. Nada foi executado.'
}

$codigoInicio = $texto.IndexOf($codigoMarcador,$secaoInicio)
if ($codigoInicio -lt 0 -or $codigoInicio -ge $envInicio) {
  throw 'Ponto de insercao Deno nao encontrado. Nada foi executado.'
}
$linhaFim = $texto.IndexOf("`n",$codigoInicio)
if ($linhaFim -lt 0 -or $linhaFim -ge $envInicio) {
  throw 'Fim da linha de status Deno nao encontrado. Nada foi executado.'
}
$posInsercao = $linhaFim + 1

$recuperacao = @'
      if ($createCode -ne 0) {
        Aviso 'Se a conta Deno ainda nao tiver organizacao, crie ou selecione uma no console oficial que sera aberto.'
        Start-Process 'https://console.deno.com'
        [void](Read-Host 'Depois de criar/selecionar a organizacao Deno, pressione ENTER para UMA unica nova tentativa')
        & $DenoExe deploy create . --app $DenoApp --source local --runtime-mode dynamic --entrypoint deno/main.js --build-timeout 5 --build-memory-limit 1024 --region global --no-wait
        $createCode = $LASTEXITCODE
      }
'@
$recuperacao = $recuperacao.Replace("`r`n","`n") + "`n"
$texto = $texto.Substring(0,$posInsercao) + $recuperacao + $texto.Substring($posInsercao)

$envInicioDepois = $texto.IndexOf($envMarcador,$secaoInicio)
$secaoFinal = $texto.Substring($secaoInicio,$envInicioDepois-$secaoInicio)
if (([regex]::Matches($secaoFinal,'deploy create \. --app \$DenoApp')).Count -ne 2) {
  throw 'Contrato Deno final nao possui exatamente tentativa inicial + uma recuperacao.'
}
if ($secaoFinal -match '\bwhile\s*\(') {
  throw 'Loop de provisionamento Deno detectado. Nada foi executado.'
}
if (-not $secaoFinal.Contains("Start-Process 'https://console.deno.com'")) {
  throw 'Recuperacao da organizacao Deno nao foi inserida.'
}
if ($texto -match '\$Pid\b') {
  throw 'Variavel PowerShell reservada PID reapareceu. Nada foi executado.'
}
if (-not $texto.Contains('function Stop-Tree([int]$ProcessId)')) {
  throw 'Hotfix ProcessId ausente. Nada foi executado.'
}
if (-not $texto.Contains('UTF8Encoding($false)') -or -not $texto.Contains('WriteAllLines($envFile')) {
  throw 'Protecao UTF-8 sem BOM ausente. Nada foi executado.'
}

$utf8Bom = New-Object Text.UTF8Encoding($true)
[IO.File]::WriteAllText($Destino,$texto,$utf8Bom)

$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile($Destino,[ref]$tokens,[ref]$errors) | Out-Null
if ($errors.Count -gt 0) {
  $msg = ($errors | ForEach-Object { $_.Message + ' @ ' + $_.Extent.StartLineNumber + ':' + $_.Extent.StartColumnNumber }) -join "`n"
  throw "Bootstrap transformado nao passou no parser. Nada foi executado.`n$msg"
}

Write-Host 'PASS: ISOLAMENTO VALIDADO.' -ForegroundColor Green
Write-Host 'PASS: TURSO LOGIN = BROWSER + CALLBACK LOCAL, SEM COPIAR TOKEN.' -ForegroundColor Green
Write-Host 'PASS: PROCESSID VALIDADO.' -ForegroundColor Green
Write-Host 'PASS: ENV UTF-8 SEM BOM VALIDADO.' -ForegroundColor Green
Write-Host 'PASS: DENO = TENTATIVA INICIAL + UMA RECUPERACAO.' -ForegroundColor Green
Write-Host 'PASS: PARSER POWERSHELL VALIDADO.' -ForegroundColor Green

if ($ValidateOnly) {
  Write-Host 'FINAL_LAUNCHER_TRANSFORM_PASS' -ForegroundColor Green
  return
}

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Destino
$codigo = $LASTEXITCODE
if ($codigo -ne 0) {
  throw "Implantacao parou no erro real. Codigo de saida: $codigo"
}
