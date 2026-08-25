# REINO TRIBAL - SCRIPT FINAL ACHATADO
# Turso 409 + Deno device auth + GitHub API 6 arquivos com package.json. Sem git clone e sem launcher intermediario.
param(
  [string]$Repositorio = 'kaalflash12/reinos-tribais-online',
  [string]$Branch = 'rt-turso-migration',
  [string]$DenoApp = 'reino-tribal-api',
  [string]$TursoDatabase = 'reino-tribal-prod',
  [int]$PullRequest = 53
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$DenoVersion = '2.9.5'
$ToolRoot = Join-Path $env:LOCALAPPDATA 'ReinoTribalTools'
$DenoHome = Join-Path $ToolRoot ("deno-$DenoVersion")
$DenoExe = Join-Path $DenoHome 'deno.exe'
$WorkRoot = Join-Path $env:TEMP ('reino-tribal-deno-' + [Guid]::NewGuid().ToString('N'))
$CredDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'ReinoTribal'
$CredFile = Join-Path $CredDir 'CREDENCIAIS_ADMIN_REINO_TRIBAL.txt'

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
    [string]$Entrada = '',
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
  if (-not $p.Start()) { Falhar "Não foi possível iniciar $label." }
  if ($Entrada) { $p.StandardInput.Write($Entrada) }
  $p.StandardInput.Close()
  $outTask = $p.StandardOutput.ReadToEndAsync()
  $errTask = $p.StandardError.ReadToEndAsync()
  $elapsed = 0
  while (-not $p.WaitForExit(5000)) {
    $elapsed += 5
    Write-Host "... ainda executando: $label (${elapsed}s/${TimeoutSec}s)" -ForegroundColor DarkGray
    if ($elapsed -ge $TimeoutSec) {
      Stop-Tree $p.Id
      return [pscustomobject]@{ Code = 124; Text = "TIMEOUT após ${TimeoutSec}s: $label"; TimedOut = $true }
    }
  }
  $stdout = $outTask.GetAwaiter().GetResult()
  $stderr = $errTask.GetAwaiter().GetResult()
  return [pscustomobject]@{
    Code = [int]$p.ExitCode
    Stdout = ([string]$stdout).Trim()
    Stderr = ([string]$stderr).Trim()
    Text = (($stdout + "`n" + $stderr).Trim())
    TimedOut = $false
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

function Secure-ToText([Security.SecureString]$Secure) {
  $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
  try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

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
function Turso-Request {
  param(
    [Parameter(Mandatory=$true)][ValidateSet('GET','POST','PUT','PATCH','DELETE')][string]$Method,
    [Parameter(Mandatory=$true)][string]$Path,
    [Parameter(Mandatory=$true)][string]$Token,
    $Body = $null
  )
  $uri = if ($Path.StartsWith('http')) { $Path } else { 'https://api.turso.tech' + $Path }
  $headers = @{ Authorization = "Bearer $Token" }
  try {
    if ($null -eq $Body) {
      return Invoke-RestMethod -Method $Method -Uri $uri -Headers $headers -TimeoutSec 60
    }
    return Invoke-RestMethod -Method $Method -Uri $uri -Headers $headers -ContentType 'application/json' -Body ($Body | ConvertTo-Json -Depth 20 -Compress) -TimeoutSec 60
  } catch {
    $detail = $_.Exception.Message
    try {
      $resp = $_.Exception.Response
      if ($resp -and $resp.GetResponseStream()) {
        $reader = New-Object IO.StreamReader($resp.GetResponseStream())
        $bodyText = $reader.ReadToEnd()
        if ($bodyText) { $detail += "`n$bodyText" }
      }
    } catch {}
    Falhar "Turso API falhou em $Method $Path`n$detail"
  }
}

function Set-GitHubSecret([string]$Gh,[string]$Nome,[string]$Valor) {
  $r = Executar-Nativo -Exe $Gh -Args @('secret','set',$Nome,'-R',$Repositorio) -Entrada $Valor -TimeoutSec 60 -Rotulo "GitHub secret $Nome"
  Exigir-Sucesso $r "Falha gravando GitHub Secret $Nome."
}

function Set-GitHubVariable([string]$Gh,[string]$Nome,[string]$Valor) {
  $r = Executar-Nativo -Exe $Gh -Args @('variable','set',$Nome,'-R',$Repositorio,'--body',$Valor) -TimeoutSec 60 -Rotulo "GitHub variable $Nome"
  Exigir-Sucesso $r "Falha gravando GitHub Variable $Nome."
}

function Post-Json([string]$Uri,[hashtable]$Body,[string]$Bearer='') {
  $headers = @{}
  if ($Bearer) { $headers.Authorization = "Bearer $Bearer" }
  Invoke-RestMethod -Uri $Uri -Method Post -Headers $headers -ContentType 'application/json' -Body ($Body | ConvertTo-Json -Depth 50 -Compress) -TimeoutSec 60
}

function Encontrar-Gh {
  $system = Get-Command gh.exe -ErrorAction SilentlyContinue
  if ($system) { return $system.Source }
  if (Test-Path $ToolRoot) {
    $found = Get-ChildItem $ToolRoot -Filter gh.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { return $found.FullName }
  }
  Falhar 'GitHub CLI não encontrado. O bootstrap não instala GitHub CLI nem outro gerenciador.'
}

function Garantir-DenoPortatil {
  New-Item -ItemType Directory -Force -Path $ToolRoot | Out-Null
  if (Test-Path $DenoExe) {
    $v = Executar-Nativo -Exe $DenoExe -Args @('--version') -TimeoutSec 20 -Rotulo 'Deno portátil existente'
    if ($v.Code -eq 0 -and $v.Text -match "deno $([regex]::Escape($DenoVersion))") {
      Ok "Deno $DenoVersion reutilizado."
      return
    }
  }

  Etapa "Deno portátil $DenoVersion"
  $tmp = Join-Path $env:TEMP ('deno-portable-' + [Guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path $tmp | Out-Null
  try {
    $zip = Join-Path $tmp 'deno.zip'
    $sum = Join-Path $tmp 'deno.zip.sha256sum'
    $base = "https://github.com/denoland/deno/releases/download/v$DenoVersion"
    Invoke-WebRequest -UseBasicParsing -Uri "$base/deno-x86_64-pc-windows-msvc.zip" -OutFile $zip -TimeoutSec 180
    Invoke-WebRequest -UseBasicParsing -Uri "$base/deno-x86_64-pc-windows-msvc.zip.sha256sum" -OutFile $sum -TimeoutSec 60
    $sumText = [IO.File]::ReadAllText($sum)
    $m = [regex]::Match($sumText,'[A-Fa-f0-9]{64}')
    if (-not $m.Success) { Falhar 'Checksum oficial do Deno veio em formato inesperado.' }
    $expected = $m.Value.ToLowerInvariant()
    $actual = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $expected) { Falhar 'SHA256 do Deno portátil não confere. Arquivo descartado.' }
    Remove-Item $DenoHome -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $DenoHome | Out-Null
    Expand-Archive -Path $zip -DestinationPath $DenoHome -Force
    if (-not (Test-Path $DenoExe)) { Falhar 'deno.exe não apareceu após extração.' }
    $v = Executar-Nativo -Exe $DenoExe -Args @('--version') -TimeoutSec 20 -Rotulo 'Validar Deno portátil'
    Exigir-Sucesso $v 'Deno portátil não executa.'
    Ok "Deno $DenoVersion preparado sem instalação de sistema."
  } finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
  }
}

function Esperar-Checks([string]$Gh) {
  Etapa 'Checks da PR'
  for ($i=1; $i -le 60; $i++) {
    $r = Executar-Nativo -Exe $Gh -Args @('pr','checks',"$PullRequest",'-R',$Repositorio,'--json','name,bucket') -TimeoutSec 45 -Rotulo 'Consultar checks'
    if ($r.Code -eq 0 -and $r.Stdout) {
      try { $checks = @($r.Stdout | ConvertFrom-Json) } catch { $checks = @() }
      if ($checks.Count -gt 0) {
        $falhas = @($checks | Where-Object { $_.bucket -in @('fail','cancel') })
        if ($falhas.Count -gt 0) { Falhar ('Checks falharam: ' + (($falhas.name) -join ', ')) }
        $pendentes = @($checks | Where-Object { $_.bucket -eq 'pending' })
        if ($pendentes.Count -eq 0) { Ok 'Todos os checks terminaram sem falha.'; return }
      }
    }
    Write-Host "Checks ainda em execução ($i/60)..." -ForegroundColor DarkGray
    Start-Sleep -Seconds 10
  }
  Falhar 'Checks não terminaram em 10 minutos. Nada foi mesclado.'
}

New-Item -ItemType Directory -Force -Path $ToolRoot,$WorkRoot,$CredDir | Out-Null

try {
  Etapa 'Pré-validação local'
  Garantir-DenoPortatil
  $gh = Encontrar-Gh
  $ghv = Executar-Nativo -Exe $gh -Args @('--version') -TimeoutSec 20 -Rotulo 'GitHub CLI'
  Exigir-Sucesso $ghv 'GitHub CLI existente não executa.'

  $gauth = Executar-Nativo -Exe $gh -Args @('auth','status') -TimeoutSec 30 -Rotulo 'GitHub auth status'
  if ($gauth.Code -ne 0) {
    Aviso 'GitHub precisa de autenticação. Confirme a página oficial que abrir.'
    & $gh auth login --web --git-protocol https
    if ($LASTEXITCODE -ne 0) { Falhar 'Login GitHub falhou.' }
  }
  $grepo = Executar-Nativo -Exe $gh -Args @('repo','view',$Repositorio) -TimeoutSec 30 -Rotulo 'Validar repositório'
  Exigir-Sucesso $grepo "Conta GitHub não acessa $Repositorio."

  Etapa 'Obtendo backend minimo via GitHub API autenticada'
  $repoDir = Join-Path $WorkRoot 'repo'
  Remove-Item $repoDir -Recurse -Force -ErrorAction SilentlyContinue
  New-Item -ItemType Directory -Force -Path $repoDir | Out-Null

  $tokenResult = Executar-Nativo -Exe $gh -Args @('auth','token') -TimeoutSec 30 -Rotulo 'Obter credencial temporaria GitHub da sessao atual'
  Exigir-Sucesso $tokenResult 'GitHub CLI autenticado nao forneceu a credencial temporaria da sessao.'
  $githubToken = $tokenResult.Stdout.Trim()
  if ($githubToken.Length -lt 20) { Falhar 'Credencial temporaria GitHub veio vazia ou invalida.' }

  $githubHeaders = @{
    Authorization = "Bearer $githubToken"
    Accept = 'application/vnd.github+json'
    'User-Agent' = 'Reino-Tribal-Bootstrap'
    'X-GitHub-Api-Version' = '2022-11-28'
  }
  $escapedBranch = [Uri]::EscapeDataString($Branch)

  function Get-GitHubBranchFile {
    param([Parameter(Mandatory=$true)][string]$RelativePath)
    $escapedPath = (($RelativePath -split '/') | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/'
    $fileUri = ('https://api.github.com/repos/{0}/contents/{1}?ref={2}' -f $Repositorio,$escapedPath,$escapedBranch)
    try {
      $meta = Invoke-RestMethod -Method Get -Uri $fileUri -Headers $githubHeaders -TimeoutSec 60
    } catch {
      Falhar "Falha baixando arquivo GitHub $RelativePath.`n$($_.Exception.Message)"
    }
    if ($null -eq $meta -or [string]$meta.type -ne 'file' -or -not $meta.content) {
      Falhar "GitHub API nao retornou conteudo de arquivo para $RelativePath."
    }
    $base64 = ([string]$meta.content) -replace '\s',''
    try { $bytes = [Convert]::FromBase64String($base64) }
    catch { Falhar "Conteudo base64 invalido recebido do GitHub para $RelativePath." }
    if ($bytes.Length -lt 1) { Falhar "Arquivo GitHub vazio: $RelativePath" }
    $dest = Join-Path $repoDir ($RelativePath -replace '/','\')
    $parent = Split-Path $dest -Parent
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    [IO.File]::WriteAllBytes($dest,$bytes)
  }

  $requiredFiles = @(
    'deno.json',
    'package.json',
    'deno/main.js',
    'api/reino.js',
    'api/admin.js',
    'backend/turso/schema.sql'
  )
  try {
    foreach ($requiredFile in $requiredFiles) { Get-GitHubBranchFile $requiredFile }
  } finally {
    $githubToken = ''
    $githubHeaders.Authorization = ''
  }

  $workPath = $repoDir
  foreach ($required in @('deno.json','package.json','deno\main.js','api\reino.js','api\admin.js','backend\turso\schema.sql')) {
    if (-not (Test-Path (Join-Path $workPath $required))) { Falhar "Arquivo obrigatorio ausente apos download minimo: $required" }
  }
  Ok 'Backend minimo obtido pela API GitHub autenticada: 6 arquivos, incluindo package.json; zero git.exe, zero clone, zero archive.'
  $check = Executar-Nativo -Exe $DenoExe -Args @('check','deno/main.js') -Diretorio $workPath -TimeoutSec 180 -Rotulo 'Deno check do backend'
  Exigir-Sucesso $check 'Backend não passou no deno check.'
  Ok 'Backend Deno/Turso validado localmente.'
  Etapa 'Turso: organização isolada e banco exclusivo'
  $platformToken = [string]$env:TURSO_PLATFORM_API_TOKEN
  if (-not $platformToken) {
    $platformToken = Obter-TursoPlatformTokenBrowser
  } else {
    Ok 'Sessao Turso existente reutilizada.'
  }
  if ($platformToken.Length -lt 20) { Falhar 'Login Turso nao retornou token valido.' }
  $orgs = @()
  try {
    $orgResponseV2 = Turso-Request -Method GET -Path '/v2/organizations' -Token $platformToken
    if ($null -ne $orgResponseV2 -and $orgResponseV2.PSObject.Properties['organizations']) {
      $orgs = @($orgResponseV2.organizations)
    } elseif ($null -ne $orgResponseV2) {
      $orgs = @($orgResponseV2)
    }
  } catch {
    Aviso 'Listagem Turso v2 indisponivel; usando fallback v1.'
    $orgs = @()
  }

  if ($orgs.Count -lt 1) {
    $orgResponseV1 = Turso-Request -Method GET -Path '/v1/organizations' -Token $platformToken
    if ($null -ne $orgResponseV1 -and $orgResponseV1.PSObject.Properties['organizations']) {
      $orgs = @($orgResponseV1.organizations)
    } elseif ($null -ne $orgResponseV1) {
      $orgs = @($orgResponseV1)
    }
  }
  $orgs = @($orgs | Where-Object { $_ -and ([string]$_.slug) })
  if ($orgs.Count -lt 1) { Falhar 'A conta Turso autenticada nao retornou nenhuma organizacao com slug utilizavel.' }

  $me = Turso-Request -Method GET -Path '/v1/current-user' -Token $platformToken
  $username = [string]$me.user.username
  $org = $null

  if ($username) {
    $org = $orgs | Where-Object { ([string]$_.slug) -eq $username } | Select-Object -First 1
  }
  if (-not $org -and $orgs.Count -eq 1) {
    $org = $orgs | Select-Object -First 1
  }
  if (-not $org) {
    $org = $orgs | Where-Object { ([string]$_.type) -eq 'personal' } | Sort-Object slug | Select-Object -First 1
  }
  if (-not $org) {
    $org = $orgs | Sort-Object slug | Select-Object -First 1
    if ($org) { Aviso 'Turso nao marcou uma organizacao como personal; usando a primeira organizacao acessivel sem criar plano pago.' }
  }
  if (-not $org) { Falhar 'A conta Turso autenticada nao retornou organizacao utilizavel.' }

  $orgSlug = [string]$org.slug
  if (-not $orgSlug) { Falhar 'A organizacao Turso selecionada nao possui slug.' }
  Ok "Organizacao Turso gratuita selecionada automaticamente: $orgSlug"
  $dedicatedGroupName = 'reino-tribal-prod'
  $groupsResp = Turso-Request -Method GET -Path "/v1/organizations/$orgSlug/groups" -Token $platformToken
  $groups = @($groupsResp.groups)
  $dedicatedGroup = $groups | Where-Object { ([string]$_.name) -eq $dedicatedGroupName } | Select-Object -First 1

  if ($dedicatedGroup) {
    $groupName = $dedicatedGroupName
    Ok "Group Turso exclusivo reutilizado: $groupName"
  } else {
    $location = ''
    try {
      $locResp = Turso-Request -Method GET -Path 'https://api.turso.tech/v1/locations' -Token $platformToken
      $keys = @($locResp.locations.PSObject.Properties.Name)
      if ($keys.Count -gt 0) {
        if ($keys -contains 'aws-us-east-1') { $location = 'aws-us-east-1' }
        else { $location = [string]($keys | Select-Object -First 1) }
      }
    } catch {
      Aviso 'Nao foi possivel listar locations para criar group dedicado; sera tentado fallback seguro.'
    }

    if ($location) {
      try {
        $createdGroup = Turso-Request -Method POST -Path "/v1/organizations/$orgSlug/groups" -Token $platformToken -Body @{ name=$dedicatedGroupName; location=$location }
        $groupName = [string]$createdGroup.group.name
        if (-not $groupName) { $groupName = $dedicatedGroupName }
        Ok "Group Turso exclusivo criado: $groupName"
      } catch {
        $groupName = ''
        Aviso 'O plano/arquitetura Turso nao permitiu criar outro placement group. O banco continuara isolado no group existente.'
      }
    } else {
      $groupName = ''
    }

    if (-not $groupName) {
      if ($groups.Count -lt 1) { Falhar 'Turso nao possui group existente e nao permitiu criar o group do Reino Tribal.' }
      $fallbackGroup = $groups | Select-Object -First 1
      $groupName = [string]$fallbackGroup.name
      if (-not $groupName) { Falhar 'Turso retornou group existente sem nome.' }
      Aviso "Usando placement group existente ($groupName); isolamento de dados permanece no banco exclusivo $TursoDatabase."
    }
  }
  function Convert-ToTursoDatabaseList {
    param($Raw)
    if ($null -eq $Raw) { return @() }
    if ($Raw -is [System.Array]) { return @($Raw) }
    if ($Raw.PSObject.Properties['databases']) { return @($Raw.databases) }
    if ($Raw.PSObject.Properties['items']) { return @($Raw.items) }
    if ($Raw.PSObject.Properties['data']) {
      $dataNode = $Raw.data
      if ($null -eq $dataNode) { return @() }
      if ($dataNode -is [System.Array]) { return @($dataNode) }
      if ($dataNode.PSObject.Properties['databases']) { return @($dataNode.databases) }
      if ($dataNode.PSObject.Properties['items']) { return @($dataNode.items) }
      if ($dataNode.PSObject.Properties['database']) { return @($dataNode.database) }
      return @($dataNode)
    }
    if ($Raw.PSObject.Properties['database']) { return @($Raw.database) }
    return @($Raw)
  }

  function Convert-ToTursoDatabase {
    param($Raw)
    $items = @(Convert-ToTursoDatabaseList $Raw)
    return ($items | Select-Object -First 1)
  }

  function Get-TursoDatabaseField {
    param($DatabaseObject,[Parameter(Mandatory=$true)][string]$Name)
    if ($null -eq $DatabaseObject) { return '' }
    $prop = $DatabaseObject.PSObject.Properties | Where-Object { $_.Name -ieq $Name } | Select-Object -First 1
    if (-not $prop) { return '' }
    return [string]$prop.Value
  }
  $dbListRaw = Turso-Request -Method GET -Path "/v1/organizations/$orgSlug/databases" -Token $platformToken
  $dbItems = @(Convert-ToTursoDatabaseList $dbListRaw)
  $db = $dbItems | Where-Object { (Get-TursoDatabaseField $_ 'Name') -eq $TursoDatabase } | Select-Object -First 1

  if (-not $db) {
    try {
      $createdRaw = Turso-Request -Method POST -Path "/v1/organizations/$orgSlug/databases" -Token $platformToken -Body @{ name=$TursoDatabase; group=$groupName }
      $db = Convert-ToTursoDatabase $createdRaw
      if (-not $db) { Falhar 'Turso respondeu a criacao do banco sem objeto de database utilizavel.' }
      Ok "Banco Turso criado: $TursoDatabase"
    } catch {
      $createError = [string]$_.Exception.Message
      if ($createError -notmatch '(?i)(\b409\b|Conflict|Conflito)') { throw }
      Aviso "Turso informou conflito 409 ao criar $TursoDatabase; buscando o banco existente pelo nome."
      $existingRaw = Turso-Request -Method GET -Path "/v1/organizations/$orgSlug/databases/$TursoDatabase" -Token $platformToken
      $db = Convert-ToTursoDatabase $existingRaw
      if (-not $db) { Falhar 'Turso retornou 409 na criacao, mas o banco existente nao pôde ser carregado pelo nome.' }
      $existingName = Get-TursoDatabaseField $db 'Name'
      if ($existingName -and $existingName -ne $TursoDatabase) {
        Falhar "Turso retornou 409 e o detalhe carregado pertence a outro banco: $existingName"
      }
      Ok "Banco Turso reutilizado apos conflito 409: $TursoDatabase"
    }
  } else {
    Ok "Banco Turso reutilizado: $TursoDatabase"
  }

  function Get-TursoHostnameFromInstances {
    param($Raw)
    if ($null -eq $Raw) { return '' }

    $instances = @()
    if ($Raw -is [System.Array]) {
      $instances = @($Raw)
    } elseif ($Raw.PSObject.Properties['instances']) {
      $instances = @($Raw.instances)
    } elseif ($Raw.PSObject.Properties['data']) {
      $dataNode = $Raw.data
      if ($null -ne $dataNode) {
        if ($dataNode -is [System.Array]) {
          $instances = @($dataNode)
        } elseif ($dataNode.PSObject.Properties['instances']) {
          $instances = @($dataNode.instances)
        } elseif ($dataNode.PSObject.Properties['instance']) {
          $instances = @($dataNode.instance)
        }
      }
    } elseif ($Raw.PSObject.Properties['instance']) {
      $instances = @($Raw.instance)
    }

    $instances = @($instances | Where-Object { $null -ne $_ })
    if ($instances.Count -lt 1) { return '' }

    $candidate = $instances | Where-Object {
      $typeProp = $_.PSObject.Properties | Where-Object { $_.Name -ieq 'type' } | Select-Object -First 1
      $typeProp -and ([string]$typeProp.Value) -ieq 'primary'
    } | Select-Object -First 1
    if (-not $candidate) { $candidate = $instances | Select-Object -First 1 }
    if (-not $candidate) { return '' }

    $hostnameProp = $candidate.PSObject.Properties | Where-Object { $_.Name -ieq 'hostname' } | Select-Object -First 1
    if (-not $hostnameProp) { return '' }
    return ([string]$hostnameProp.Value).Trim()
  }

  $hostname = Get-TursoDatabaseField $db 'Hostname'
  if (-not $hostname) {
    $detailRaw = Turso-Request -Method GET -Path "/v1/organizations/$orgSlug/databases/$TursoDatabase" -Token $platformToken
    $detailDb = Convert-ToTursoDatabase $detailRaw
    $hostname = Get-TursoDatabaseField $detailDb 'Hostname'
  }

  if (-not $hostname) {
    $instancesRaw = Turso-Request -Method GET -Path "/v1/organizations/$orgSlug/databases/$TursoDatabase/instances" -Token $platformToken
    $hostname = Get-TursoHostnameFromInstances $instancesRaw
    if ($hostname) { Ok "Hostname Turso obtido pela instancia primaria: $hostname" }
  }

  if (-not $hostname) {
    Falhar 'Turso nao retornou hostname nem no detalhe do database nem na lista de instances.'
  }

  $dbUrl = 'libsql://' + ($hostname -replace '^https?://','' -replace '^libsql://','')
  $dbTokenResp = Turso-Request -Method POST -Path "/v1/organizations/$orgSlug/databases/$TursoDatabase/auth/tokens?expiration=never&authorization=full-access" -Token $platformToken -Body @{}
  $dbToken = ''
  if ($dbTokenResp -is [string]) {
    $dbToken = [string]$dbTokenResp
  } elseif ($null -ne $dbTokenResp) {
    $jwtProp = $dbTokenResp.PSObject.Properties | Where-Object { $_.Name -ieq 'jwt' } | Select-Object -First 1
    $tokenProp = $dbTokenResp.PSObject.Properties | Where-Object { $_.Name -ieq 'token' } | Select-Object -First 1
    if ($jwtProp) { $dbToken = [string]$jwtProp.Value }
    elseif ($tokenProp) { $dbToken = [string]$tokenProp.Value }
  }
  if ($dbToken.Length -lt 20) { Falhar 'Turso nao retornou token de banco valido em formato reconhecido.' }
  Ok 'URL e token do banco Turso obtidos sem expor valores.'
  $adminPassword = 'RT!' + (Novo-Segredo 30)
  $recoveryKey = Novo-Segredo 48

  Etapa 'Deno Deploy: app exclusivo do Reino Tribal'
  $denoOrg = [string]$env:DENO_DEPLOY_ORG
  if (-not $denoOrg) {
    $orgRepo = Executar-Nativo -Exe $gh -Args @('variable','get','DENO_DEPLOY_ORG','-R',$Repositorio) -TimeoutSec 30 -Rotulo 'Ler DENO_DEPLOY_ORG do GitHub'
    if ($orgRepo.Code -eq 0 -and $orgRepo.Text) { $denoOrg = $orgRepo.Text.Trim() }
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
  Exigir-Sucesso $orgList "Nao foi possivel autenticar/listar organizacoes do Deno Deploy.`n$($orgList.Text)"
  try { $denoOrgs = @($orgList.Stdout | ConvertFrom-Json) } catch { Falhar "Deno retornou JSON de organizacoes invalido.`n$($orgList.Text)" }

  if ($denoOrgs.Count -lt 1) {
    Aviso 'A conta Deno ainda nao possui organizacao. O console oficial sera aberto; crie/confirme uma organizacao. O script detectara automaticamente.'
    Start-Process 'https://console.deno.com'
    for ($attempt=1; $attempt -le 24 -and $denoOrgs.Count -lt 1; $attempt++) {
      Start-Sleep -Seconds 5
      $retryOrgs = Executar-Nativo -Exe $DenoExe -Args @('deploy','orgs','list','--json') -TimeoutSec 45 -Rotulo "Detectar organizacao Deno ($attempt/24)"
      if ($retryOrgs.Code -eq 0 -and $retryOrgs.Stdout) {
        try { $denoOrgs = @($retryOrgs.Stdout | ConvertFrom-Json) } catch { $denoOrgs = @() }
      }
    }
  }
  if ($denoOrgs.Count -lt 1) { Falhar 'Nenhuma organizacao Deno foi detectada apos o login/criacao no console oficial.' }

  $slugs = @($denoOrgs | ForEach-Object { [string]$_.slug } | Where-Object { $_ })
  if ($denoOrg -and $slugs -notcontains $denoOrg) {
    Aviso "DENO_DEPLOY_ORG salvo ($denoOrg) nao esta acessivel nesta conta; selecao automatica sera refeita."
    $denoOrg = ''
  }

  if (-not $denoOrg) {
    foreach ($candidate in ($slugs | Sort-Object)) {
      $existing = Executar-Nativo -Exe $DenoExe -Args @('deploy','apps','get','--org',$candidate,'--app',$DenoApp,'--json','--non-interactive') -TimeoutSec 45 -Rotulo "Procurar $DenoApp em $candidate"
      if ($existing.Code -eq 0) { $denoOrg = $candidate; break }
    }
    if (-not $denoOrg -and $slugs -contains 'kaalflash12') { $denoOrg = 'kaalflash12' }
    if (-not $denoOrg) { $denoOrg = $slugs | Sort-Object | Select-Object -First 1 }
    if (-not $denoOrg) { Falhar 'Deno retornou organizacoes sem slug utilizavel.' }
  }

  if ($denoOrg -notmatch '^[a-z0-9](?:[a-z0-9-]{1,61}[a-z0-9])?$') {
    Falhar "Slug da organizacao Deno retornado pela propria plataforma e invalido: $denoOrg"
  }
  Ok "Organizacao Deno selecionada automaticamente: $denoOrg"

  $probe = Executar-Nativo -Exe $DenoExe -Args @('deploy','apps','get','--org',$denoOrg,'--app',$DenoApp,'--json','--non-interactive') -TimeoutSec 60 -Rotulo 'Procurar app Deno existente'
  if ($probe.Code -ne 0) {
    $create = Executar-Nativo -Exe $DenoExe -Args @(
      'deploy','create','.',
      '--org',$denoOrg,
      '--app',$DenoApp,
      '--source','local',
      '--runtime-mode','dynamic',
      '--entrypoint','deno/main.js',
      '--build-timeout','5',
      '--build-memory-limit','1024',
      '--region','global',
      '--no-wait','--non-interactive'
    ) -Diretorio $workPath -TimeoutSec 600 -Rotulo 'Criar app Deno reino-tribal-api'
    Exigir-Sucesso $create "Nao foi possivel criar o app Deno exclusivo do Reino Tribal.`n$($create.Text)"
    Ok "App Deno criado: $DenoApp"
  } else {
    Ok "App Deno ja existe: $DenoApp"
  }
  Set-GitHubVariable $gh 'DENO_DEPLOY_ORG' $denoOrg
  $envFile = Join-Path $WorkRoot '.env.reino-tribal.production'
  $envLines = @(
    "TURSO_DATABASE_URL=$dbUrl",
    "TURSO_AUTH_TOKEN=$dbToken",
    "RT_ADMIN_PASSWORD=$adminPassword",
    "RT_ADMIN_RECOVERY_KEY=$recoveryKey",
    'RT_ALLOWED_ORIGINS=https://kaalflash12.github.io'
  )
  $envUtf8NoBom = New-Object Text.UTF8Encoding($false)
  [IO.File]::WriteAllLines($envFile,$envLines,$envUtf8NoBom)
  try {
    $loadEnv = Executar-Nativo -Exe $DenoExe -Args @('deploy','env','load','--replace',$envFile,'--org',$denoOrg,'--app',$DenoApp,'--non-interactive') -TimeoutSec 120 -Rotulo 'Carregar secrets no Deno Deploy'
    Exigir-Sucesso $loadEnv 'Falha carregando variáveis no Deno Deploy.'
    foreach ($name in @('TURSO_DATABASE_URL','TURSO_AUTH_TOKEN','RT_ADMIN_PASSWORD','RT_ADMIN_RECOVERY_KEY','RT_ALLOWED_ORIGINS')) {
      $ctx = Executar-Nativo -Exe $DenoExe -Args @('deploy','env','update-contexts',$name,'--org',$denoOrg,'--app',$DenoApp,'--non-interactive') -TimeoutSec 60 -Rotulo "Contextos Deno $name"
      Exigir-Sucesso $ctx "Falha configurando contextos de $name."
    }
  } finally {
    Remove-Item $envFile -Force -ErrorAction SilentlyContinue
  }

  Etapa 'Deploy de produção Deno'
  $deploy = Executar-Nativo -Exe $DenoExe -Args @('deploy','--org',$denoOrg,'--app',$DenoApp,'--prod','--non-interactive') -Diretorio $workPath -TimeoutSec 600 -Rotulo 'Deno deploy produção'
  Exigir-Sucesso $deploy 'Deploy Deno falhou.'
  $appInfo = Executar-Nativo -Exe $DenoExe -Args @('deploy','apps','get','--org',$denoOrg,'--app',$DenoApp,'--json','--non-interactive') -TimeoutSec 60 -Rotulo 'Obter URL oficial do backend Deno'
  Exigir-Sucesso $appInfo "Deploy terminou, mas apps get falhou.`n$($appInfo.Text)"
  try { $appMeta = $appInfo.Stdout | ConvertFrom-Json } catch { Falhar "apps get retornou JSON invalido.`n$($appInfo.Text)" }
  $backend = ([string]$appMeta.productionUrl).TrimEnd('/')
  if (-not $backend -or $backend -notmatch '^https://') { Falhar "Deno nao retornou productionUrl valida para $DenoApp." }
  Ok "Backend: $backend"
  Etapa 'Testes reais: Turso + conta + save/load + ADM'
  $healthWeb = $null
  for ($i=1; $i -le 20; $i++) {
    try {
      $healthWeb = Invoke-RestMethod -Uri "$backend/health" -Method Get -TimeoutSec 30
      if ($healthWeb.ok -and $healthWeb.runtime -eq 'deno-deploy') { break }
    } catch { $healthWeb = $null }
    Start-Sleep -Seconds 3
  }
  if (-not $healthWeb -or -not $healthWeb.ok) { Falhar 'Health do runtime Deno não passou.' }

  $health = Post-Json "$backend/api/reino" @{ action='health' }
  if (-not $health.ok -or $health.database -ne 'turso') { Falhar 'Health da API/Turso não passou.' }
  $stamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  $testUser = "rtprobe_$stamp"
  $testPass = 'Probe!' + (Novo-Segredo 24)
  $reg = Post-Json "$backend/api/reino" @{ action='register'; email="$testUser@example.invalid"; username=$testUser; password=$testPass }
  if (-not $reg.access_token) { Falhar 'Registro real não retornou sessão.' }
  $playerToken = [string]$reg.access_token
  $worldId = 'd5a546fb-316d-4332-ae92-1886d80b07df'
  $join = Post-Json "$backend/api/reino" @{ action='join_world'; world_id=$worldId; player_name=$testUser } $playerToken
  if (-not $join.ok) { Falhar 'Entrada no Mundo 1 falhou.' }
  $save = Post-Json "$backend/api/reino" @{ action='save'; world_id=$worldId; state=@{ probe='reino-tribal-deno-turso'; stamp=$stamp; ok=$true } } $playerToken
  if (-not $save.ok) { Falhar 'Save real falhou.' }
  $load = Post-Json "$backend/api/reino" @{ action='load_save'; world_id=$worldId } $playerToken
  if (-not $load.state -or $load.state.probe -ne 'reino-tribal-deno-turso') { Falhar 'Load real falhou.' }
  $adm = Post-Json "$backend/api/reino" @{ action='login'; identifier='reinos_admin'; password=$adminPassword }
  if (-not $adm.access_token -or $adm.user.role -ne 'admin') { Falhar 'Login ADM real falhou.' }
  $adminToken = [string]$adm.access_token
  $status = Post-Json "$backend/api/reino" @{ action='admin_status' } $adminToken
  if (-not $status.ok) { Falhar 'admin_status falhou.' }
  $dash = Post-Json "$backend/api/admin" @{ action='dashboard' } $adminToken
  if (-not $dash) { Falhar 'Dashboard ADM falhou.' }
  Ok 'Health + registro + mundo + save/load + ADM passaram.'

  Etapa 'GitHub: secrets e backend público'
  Set-GitHubSecret $gh 'TURSO_DATABASE_URL' $dbUrl
  Set-GitHubSecret $gh 'TURSO_AUTH_TOKEN' $dbToken
  Set-GitHubSecret $gh 'RT_ADMIN_PASSWORD' $adminPassword
  Set-GitHubSecret $gh 'RT_ADMIN_RECOVERY_KEY' $recoveryKey
  Set-GitHubVariable $gh 'REINO_TRIBAL_API_BASE' $backend
  Ok 'GitHub configurado para o backend Deno/Turso.'

  Etapa 'PR e publicação do frontend'
  $prView = Executar-Nativo -Exe $gh -Args @('pr','view',"$PullRequest",'-R',$Repositorio,'--json','state,isDraft,mergedAt') -TimeoutSec 30 -Rotulo 'Estado da PR'
  Exigir-Sucesso $prView 'Não consegui ler a PR.'
  $pr = $prView.Stdout | ConvertFrom-Json
  if (-not $pr.mergedAt) {
    if ($pr.isDraft) {
      $ready = Executar-Nativo -Exe $gh -Args @('pr','ready',"$PullRequest",'-R',$Repositorio) -TimeoutSec 45 -Rotulo 'Marcar PR pronta'
      Exigir-Sucesso $ready 'Não consegui marcar a PR como pronta.'
    }
    Esperar-Checks $gh
    $merge = Executar-Nativo -Exe $gh -Args @('pr','merge',"$PullRequest",'-R',$Repositorio,'--squash') -TimeoutSec 90 -Rotulo 'Merge da migração'
    Exigir-Sucesso $merge 'Merge falhou.'
    Ok 'Migração mesclada em main.'
  } else {
    Ok 'PR já estava mesclada.'
  }

  $pages = Executar-Nativo -Exe $gh -Args @('workflow','run','deploy-reino-tribal-pages.yml','-R',$Repositorio,'--ref','main') -TimeoutSec 45 -Rotulo 'Disparar GitHub Pages'
  Exigir-Sucesso $pages 'Falha disparando GitHub Pages.'
  Start-Sleep -Seconds 5
  $runId = ''
  for ($i=1; $i -le 12 -and -not $runId; $i++) {
    $last = Executar-Nativo -Exe $gh -Args @('run','list','-R',$Repositorio,'--workflow','deploy-reino-tribal-pages.yml','--branch','main','--limit','1','--json','databaseId,status,conclusion') -TimeoutSec 30 -Rotulo 'Localizar deploy Pages'
    if ($last.Code -eq 0 -and $last.Stdout) {
      $runs = @($last.Stdout | ConvertFrom-Json)
      if ($runs.Count -gt 0) { $runId = [string]$runs[0].databaseId }
    }
    if (-not $runId) { Start-Sleep -Seconds 5 }
  }
  if (-not $runId) { Falhar 'Workflow do GitHub Pages não apareceu.' }
  for ($i=1; $i -le 60; $i++) {
    $view = Executar-Nativo -Exe $gh -Args @('run','view',$runId,'-R',$Repositorio,'--json','status,conclusion') -TimeoutSec 30 -Rotulo 'Acompanhar GitHub Pages'
    if ($view.Code -eq 0 -and $view.Stdout) {
      $obj = $view.Stdout | ConvertFrom-Json
      if ($obj.status -eq 'completed') {
        if ($obj.conclusion -ne 'success') { Falhar "GitHub Pages terminou com $($obj.conclusion)." }
        break
      }
    }
    if ($i -eq 60) { Falhar 'GitHub Pages não terminou em 10 minutos.' }
    Start-Sleep -Seconds 10
  }

  $publicUrl = 'https://kaalflash12.github.io/reinos-tribais-online/'
  $public = $null
  for ($i=1; $i -le 20; $i++) {
    try {
      $public = Invoke-WebRequest -UseBasicParsing -Uri $publicUrl -TimeoutSec 30
      if ($public.StatusCode -eq 200 -and $public.Content -match '1\.0\.4-turso') { break }
    } catch { $public = $null }
    Start-Sleep -Seconds 3
  }
  if (-not $public -or $public.StatusCode -ne 200 -or $public.Content -notmatch '1\.0\.4-turso') { Falhar 'Página pública não confirmou a versão Turso.' }

  $cred = @"
REINO TRIBAL - PRODUÇÃO
Data: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Usuário ADM: reinos_admin
Senha ADM: $adminPassword
Chave de recuperação: $recoveryKey
Backend: $backend
Jogo: $publicUrl
Banco: $TursoDatabase / Turso
Runtime: Deno Deploy
"@
  Set-Content -Path $CredFile -Value $cred -Encoding UTF8
  Ok "Credenciais ADM: $CredFile"
  Ok "JOGO ONLINE: $publicUrl"
  Ok "BACKEND ONLINE: $backend"

} finally {
  Remove-Item $WorkRoot -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item Env:TURSO_PLATFORM_API_TOKEN -ErrorAction SilentlyContinue
}
