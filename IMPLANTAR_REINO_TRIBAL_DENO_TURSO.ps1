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
    if ($r.Code -eq 0 -and $r.Text) {
      try { $checks = @($r.Text | ConvertFrom-Json) } catch { $checks = @() }
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

  Etapa 'Baixando branch isolada do Reino Tribal'
  $zip = Join-Path $WorkRoot 'source.zip'
  Invoke-WebRequest -UseBasicParsing -Uri "https://codeload.github.com/$Repositorio/zip/refs/heads/$Branch" -OutFile $zip -TimeoutSec 180
  Expand-Archive -Path $zip -DestinationPath $WorkRoot -Force
  $work = Get-ChildItem $WorkRoot -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'deno\main.js') } | Select-Object -First 1
  if (-not $work) { Falhar 'Raiz com deno/main.js não foi encontrada.' }
  $workPath = $work.FullName
  foreach ($required in @('deno.json','deno\main.js','api\reino.js','api\admin.js','backend\turso\schema.sql')) {
    if (-not (Test-Path (Join-Path $workPath $required))) { Falhar "Arquivo obrigatório ausente: $required" }
  }
  $check = Executar-Nativo -Exe $DenoExe -Args @('check','deno/main.js') -Diretorio $workPath -TimeoutSec 180 -Rotulo 'Deno check do backend'
  Exigir-Sucesso $check 'Backend não passou no deno check.'
  Ok 'Backend Deno/Turso validado localmente.'

  Etapa 'Turso: organização isolada e banco exclusivo'
  $platformToken = [string]$env:TURSO_PLATFORM_API_TOKEN
  if (-not $platformToken) {
    Write-Host 'Cole o Platform API Token da sua conta Turso. A entrada fica oculta.' -ForegroundColor Yellow
    $secure = Read-Host 'Turso Platform API Token' -AsSecureString
    $platformToken = Secure-ToText $secure
  }
  if ($platformToken.Length -lt 20) { Falhar 'Turso Platform API Token ausente ou curto demais.' }

  $orgs = @(Turso-Request -Method GET -Path '/v1/organizations' -Token $platformToken)
  $managed = @($orgs | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.platform) })
  if ($managed.Count -lt 1) { Falhar 'Nenhuma organização Turso independente foi encontrada nessa conta.' }
  if ($managed.Count -eq 1) {
    $org = $managed[0]
  } else {
    Write-Host 'Organizações Turso independentes:' -ForegroundColor Cyan
    for ($i=0; $i -lt $managed.Count; $i++) { Write-Host "[$($i+1)] $($managed[$i].slug)" }
    $choice = 0
    while ($choice -lt 1 -or $choice -gt $managed.Count) {
      $raw = Read-Host 'Escolha o número da organização para o Reino Tribal'
      [void][int]::TryParse($raw,[ref]$choice)
    }
    $org = $managed[$choice-1]
  }
  $orgSlug = [string]$org.slug
  Ok "Organização Turso selecionada: $orgSlug"

  $groupsResp = Turso-Request -Method GET -Path "/v1/organizations/$orgSlug/groups" -Token $platformToken
  $groups = @($groupsResp.groups)
  if ($groups.Count -lt 1) {
    $locResp = Turso-Request -Method GET -Path 'https://api.turso.tech/v1/locations' -Token $platformToken
    $keys = @($locResp.locations.PSObject.Properties.Name)
    if ($keys.Count -lt 1) { Falhar 'Turso não retornou localizações.' }
    $location = if ($keys -contains 'aws-us-east-1') { 'aws-us-east-1' } else { $keys[0] }
    $createdGroup = Turso-Request -Method POST -Path "/v1/organizations/$orgSlug/groups" -Token $platformToken -Body @{ name='default'; location=$location }
    $groups = @($createdGroup.group)
  }
  $groupName = [string]$groups[0].name

  $dbList = Turso-Request -Method GET -Path "/v1/organizations/$orgSlug/databases" -Token $platformToken
  $db = @($dbList.databases | Where-Object { $_.Name -eq $TursoDatabase }) | Select-Object -First 1
  if (-not $db) {
    $created = Turso-Request -Method POST -Path "/v1/organizations/$orgSlug/databases" -Token $platformToken -Body @{ name=$TursoDatabase; group=$groupName }
    $db = $created.database
    Ok "Banco Turso criado: $TursoDatabase"
  } else {
    Ok "Banco Turso reutilizado: $TursoDatabase"
  }
  $hostname = [string]$db.Hostname
  if (-not $hostname) {
    $detail = Turso-Request -Method GET -Path "/v1/organizations/$orgSlug/databases/$TursoDatabase" -Token $platformToken
    $hostname = [string]$detail.database.Hostname
  }
  if (-not $hostname) { Falhar 'Turso não retornou hostname do banco.' }
  $dbUrl = 'libsql://' + ($hostname -replace '^https?://','' -replace '^libsql://','')
  $dbTokenResp = Turso-Request -Method POST -Path "/v1/organizations/$orgSlug/databases/$TursoDatabase/auth/tokens?expiration=never&authorization=full-access" -Token $platformToken -Body @{}
  $dbToken = [string]$dbTokenResp.jwt
  if ($dbToken.Length -lt 20) { Falhar 'Turso não retornou token de banco válido.' }
  Ok 'URL e token do banco Turso obtidos sem expor valores.'

  $adminPassword = 'RT!' + (Novo-Segredo 30)
  $recoveryKey = Novo-Segredo 48

  Etapa 'Deno Deploy: app exclusivo do Reino Tribal'
  $probe = Executar-Nativo -Exe $DenoExe -Args @('deploy','env','list','--app',$DenoApp) -TimeoutSec 20 -Rotulo 'Procurar app Deno existente'
  if ($probe.Code -ne 0) {
    Aviso 'Se o Deno pedir autenticação, confirme somente no login oficial. Esta é a única etapa interativa do Deno.'
    Push-Location $workPath
    try {
      & $DenoExe deploy create . --app $DenoApp --source local --runtime-mode dynamic --entrypoint deno/main.js --build-timeout 5 --build-memory-limit 1024 --region global --no-wait
      $createCode = $LASTEXITCODE
    } finally { Pop-Location }
    if ($createCode -ne 0) { Falhar 'Não foi possível criar o app Deno exclusivo do Reino Tribal.' }
  } else {
    Ok "App Deno já existe: $DenoApp"
  }

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
    $loadEnv = Executar-Nativo -Exe $DenoExe -Args @('deploy','env','load',$envFile,'--app',$DenoApp) -TimeoutSec 120 -Rotulo 'Carregar secrets no Deno Deploy'
    Exigir-Sucesso $loadEnv 'Falha carregando variáveis no Deno Deploy.'
    foreach ($name in @('TURSO_DATABASE_URL','TURSO_AUTH_TOKEN','RT_ADMIN_PASSWORD','RT_ADMIN_RECOVERY_KEY','RT_ALLOWED_ORIGINS')) {
      $ctx = Executar-Nativo -Exe $DenoExe -Args @('deploy','env','update-contexts',$name,'production','development','--app',$DenoApp) -TimeoutSec 60 -Rotulo "Contextos Deno $name"
      Exigir-Sucesso $ctx "Falha configurando contextos de $name."
    }
  } finally {
    Remove-Item $envFile -Force -ErrorAction SilentlyContinue
  }

  Etapa 'Deploy de produção Deno'
  $deploy = Executar-Nativo -Exe $DenoExe -Args @('deploy','--app',$DenoApp,'--prod') -Diretorio $workPath -TimeoutSec 600 -Rotulo 'Deno deploy produção'
  Exigir-Sucesso $deploy 'Deploy Deno falhou.'
  $urls = [regex]::Matches($deploy.Text,'https://[A-Za-z0-9.-]+\.deno\.net') | ForEach-Object { $_.Value.TrimEnd('/') }
  $backend = @($urls) | Select-Object -Last 1
  if (-not $backend) { Falhar "Deploy terminou, mas a URL .deno.net não foi identificada.`n$($deploy.Text)" }
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
  $pr = $prView.Text | ConvertFrom-Json
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
    if ($last.Code -eq 0 -and $last.Text) {
      $runs = @($last.Text | ConvertFrom-Json)
      if ($runs.Count -gt 0) { $runId = [string]$runs[0].databaseId }
    }
    if (-not $runId) { Start-Sleep -Seconds 5 }
  }
  if (-not $runId) { Falhar 'Workflow do GitHub Pages não apareceu.' }
  for ($i=1; $i -le 60; $i++) {
    $view = Executar-Nativo -Exe $gh -Args @('run','view',$runId,'-R',$Repositorio,'--json','status,conclusion') -TimeoutSec 30 -Rotulo 'Acompanhar GitHub Pages'
    if ($view.Code -eq 0 -and $view.Text) {
      $obj = $view.Text | ConvertFrom-Json
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
