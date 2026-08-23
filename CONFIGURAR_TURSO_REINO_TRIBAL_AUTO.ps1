param(
  [string]$Repositorio = 'kaalflash12/reinos-tribais-online',
  [string]$Branch = 'rt-turso-migration',
  [string]$BancoTurso = 'reino-tribal-prod',
  [string]$ProjetoVercel = 'reino-tribal-api',
  [string]$VercelScope = 'kaalflash12s-projects',
  [int]$PullRequest = 53
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Etapa([string]$Texto) { Write-Host "`n=== $Texto ===" -ForegroundColor Cyan }
function Ok([string]$Texto) { Write-Host "PASS: $Texto" -ForegroundColor Green }
function Aviso([string]$Texto) { Write-Host "AVISO: $Texto" -ForegroundColor Yellow }

function Atualizar-Path {
  $machine = [Environment]::GetEnvironmentVariable('Path','Machine')
  $user = [Environment]::GetEnvironmentVariable('Path','User')
  $env:Path = "$machine;$user"
}

function Exigir-Comando([string]$Nome, [string]$WingetId) {
  $cmd = Get-Command $Nome -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) { throw "$Nome não encontrado e winget não está disponível." }
  Etapa "Instalando $Nome"
  & winget.exe install --id $WingetId --exact --source winget --accept-package-agreements --accept-source-agreements --silent
  if ($LASTEXITCODE -ne 0) { throw "Falha instalando $Nome pelo winget." }
  Atualizar-Path
  $cmd = Get-Command $Nome -ErrorAction SilentlyContinue
  if (-not $cmd) { throw "$Nome foi instalado, mas ainda não entrou no PATH. Feche e reabra o PowerShell e execute novamente." }
  return $cmd.Source
}

function Turso-Capturar([string]$Comando) {
  $full = 'export PATH="$HOME/.turso:$HOME/.local/bin:$PATH"; ' + $Comando
  $saida = & wsl.exe bash -lc $full 2>&1
  $codigo = $LASTEXITCODE
  [pscustomobject]@{ Codigo=$codigo; Texto=(($saida | ForEach-Object { "$_" }) -join "`n").Trim() }
}

function Novo-Segredo([int]$Bytes = 32) {
  $buf = New-Object byte[] $Bytes
  [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($buf)
  return ([Convert]::ToBase64String($buf).TrimEnd('=').Replace('+','-').Replace('/','_'))
}

function Post-Json([string]$Uri, [hashtable]$Body, [string]$Bearer = '') {
  $headers = @{}
  if ($Bearer) { $headers.Authorization = "Bearer $Bearer" }
  Invoke-RestMethod -Uri $Uri -Method Post -ContentType 'application/json' -Headers $headers -Body ($Body | ConvertTo-Json -Depth 50 -Compress) -TimeoutSec 60
}

function Set-GitHubSecret([string]$Nome, [string]$Valor, [string]$Gh) {
  $Valor | & $Gh secret set $Nome -R $Repositorio
  if ($LASTEXITCODE -ne 0) { throw "Falha gravando GitHub Secret $Nome." }
}

function Set-GitHubVariable([string]$Nome, [string]$Valor, [string]$Gh) {
  $Valor | & $Gh variable set $Nome -R $Repositorio
  if ($LASTEXITCODE -ne 0) { throw "Falha gravando GitHub Variable $Nome." }
}

function Vercel([string[]]$Args) {
  & $script:Npx --yes vercel@latest @Args
  if ($LASTEXITCODE -ne 0) { throw "Vercel falhou: $($Args -join ' ')" }
}

function Set-VercelEnv([string]$Nome, [string]$Valor) {
  & $script:Npx --yes vercel@latest env rm $Nome production --yes --scope $VercelScope *> $null
  $help = (& $script:Npx --yes vercel@latest env add --help 2>&1 | Out-String)
  $args = @('--yes','vercel@latest','env','add',$Nome,'production','--scope',$VercelScope)
  if ($help -match '--sensitive') { $args += '--sensitive' }
  if ($help -match '--force') { $args += '--force' }
  $Valor | & $script:Npx @args
  if ($LASTEXITCODE -ne 0) { throw "Falha gravando variável Vercel $Nome." }
}

Etapa 'Pré-requisitos'
$gh = Exigir-Comando 'gh.exe' 'GitHub.cli'
$git = Exigir-Comando 'git.exe' 'Git.Git'
$script:Npx = Exigir-Comando 'npx.cmd' 'OpenJS.NodeJS.LTS'

if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
  Etapa 'Instalando WSL/Ubuntu'
  & wsl.exe --install -d Ubuntu
  throw 'O Windows iniciou a instalação do WSL. Se pedir reinicialização, reinicie e cole o mesmo comando novamente; depois ele continuará sozinho.'
}
$wslList = (& wsl.exe -l -q 2>$null | Out-String).Trim()
if (-not $wslList) {
  Etapa 'Instalando Ubuntu no WSL'
  & wsl.exe --install -d Ubuntu
  throw 'O Ubuntu/WSL foi solicitado. Se o Windows pedir reinicialização, reinicie e cole o mesmo comando novamente.'
}

Etapa 'Turso CLI'
$probe = Turso-Capturar 'command -v turso >/dev/null 2>&1'
if ($probe.Codigo -ne 0) {
  & wsl.exe bash -lc 'curl -sSfL https://get.tur.so/install.sh | bash'
  if ($LASTEXITCODE -ne 0) { throw 'Falha instalando o Turso CLI.' }
}
$probe = Turso-Capturar 'turso --version'
if ($probe.Codigo -ne 0) { throw 'Turso CLI não ficou disponível no WSL.' }
Ok $probe.Texto

Etapa 'Login Turso'
$who = Turso-Capturar 'turso auth whoami'
if ($who.Codigo -ne 0) {
  Write-Host 'O Turso mostrará URL/código de login. Apenas confirme no navegador.' -ForegroundColor Yellow
  & wsl.exe bash -lc 'export PATH="$HOME/.turso:$HOME/.local/bin:$PATH"; turso auth login --headless'
  if ($LASTEXITCODE -ne 0) { throw 'Login Turso falhou.' }
}
$who = Turso-Capturar 'turso auth whoami'
if ($who.Codigo -ne 0) { throw 'Turso continua sem autenticação.' }
Ok "Turso autenticado: $($who.Texto)"

Etapa "Banco Turso exclusivo: $BancoTurso"
$db = Turso-Capturar "turso db show $BancoTurso --url"
if ($db.Codigo -ne 0 -or -not $db.Texto) {
  $create = Turso-Capturar "turso db create $BancoTurso"
  if ($create.Codigo -ne 0) { throw "Falha criando $BancoTurso.`n$($create.Texto)" }
  $db = Turso-Capturar "turso db show $BancoTurso --url"
}
$dbUrl = (($db.Texto -split "`n") | ForEach-Object {$_.Trim()} | Where-Object { $_ -match '^(libsql|https)://' } | Select-Object -Last 1)
if (-not $dbUrl) { throw 'Não consegui obter a URL Turso.' }
$tok = Turso-Capturar "turso db tokens create $BancoTurso"
if ($tok.Codigo -ne 0) { throw "Falha criando token Turso.`n$($tok.Texto)" }
$tokenLines = @($tok.Texto -split "`n" | ForEach-Object {$_.Trim()} | Where-Object {$_})
$dbToken = $tokenLines | Where-Object { $_ -match '^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$' } | Select-Object -Last 1
if (-not $dbToken -and $tokenLines.Count -gt 0) { $dbToken = $tokenLines[-1] }
if (-not $dbToken -or $dbToken.Length -lt 20) { throw 'Token Turso retornado em formato inesperado.' }
Ok 'Banco e token Turso obtidos.'

$adminPassword = 'RT!' + (Novo-Segredo 30)
$recoveryKey = Novo-Segredo 48

Etapa 'Login GitHub'
& $gh auth status *> $null
if ($LASTEXITCODE -ne 0) {
  & $gh auth login --web --git-protocol https
  if ($LASTEXITCODE -ne 0) { throw 'Login GitHub falhou.' }
}
& $gh repo view $Repositorio *> $null
if ($LASTEXITCODE -ne 0) { throw "A conta GitHub autenticada não acessa $Repositorio." }
Ok 'GitHub autenticado.'

Etapa 'Gravando secrets no GitHub'
Set-GitHubSecret 'TURSO_DATABASE_URL' $dbUrl $gh
Set-GitHubSecret 'TURSO_AUTH_TOKEN' $dbToken $gh
Set-GitHubSecret 'RT_ADMIN_PASSWORD' $adminPassword $gh
Set-GitHubSecret 'RT_ADMIN_RECOVERY_KEY' $recoveryKey $gh
Ok 'Secrets GitHub gravados sem commitá-los.'

Etapa 'Login Vercel'
& $script:Npx --yes vercel@latest whoami *> $null
if ($LASTEXITCODE -ne 0) {
  & $script:Npx --yes vercel@latest login
  if ($LASTEXITCODE -ne 0) { throw 'Login Vercel falhou.' }
}
Ok 'Vercel autenticada.'

Etapa 'Checkout isolado da migração'
$work = Join-Path $env:TEMP ('reino-tribal-turso-' + [Guid]::NewGuid().ToString('N'))
& $gh repo clone $Repositorio $work -- --branch $Branch --single-branch
if ($LASTEXITCODE -ne 0) { throw "Falha clonando $Branch." }

try {
  Push-Location $work
  try {
    Etapa "Projeto Vercel exclusivo: $ProjetoVercel"
    & $script:Npx --yes vercel@latest project inspect $ProjetoVercel --scope $VercelScope *> $null
    if ($LASTEXITCODE -ne 0) {
      & $script:Npx --yes vercel@latest project add $ProjetoVercel --scope $VercelScope
      if ($LASTEXITCODE -ne 0) { throw 'Falha criando projeto Vercel exclusivo.' }
    }
    Vercel @('link','--yes','--project',$ProjetoVercel,'--scope',$VercelScope)
    Vercel @('project','inspect','--non-interactive','--scope',$VercelScope)

    if (Test-Path '.vercel/project.json') {
      $pj = Get-Content '.vercel/project.json' -Raw | ConvertFrom-Json
      if ($pj.orgId) { Set-GitHubSecret 'VERCEL_ORG_ID' ([string]$pj.orgId) $gh }
      if ($pj.projectId) { Set-GitHubSecret 'VERCEL_PROJECT_ID' ([string]$pj.projectId) $gh }
    }

    Etapa 'Variáveis privadas Vercel'
    Set-VercelEnv 'TURSO_DATABASE_URL' $dbUrl
    Set-VercelEnv 'TURSO_AUTH_TOKEN' $dbToken
    Set-VercelEnv 'RT_ADMIN_PASSWORD' $adminPassword
    Set-VercelEnv 'RT_ADMIN_RECOVERY_KEY' $recoveryKey
    Ok 'Variáveis de produção configuradas.'

    Etapa 'Deploy de produção da API'
    $deployOut = & $script:Npx --yes vercel@latest deploy --prod --yes --scope $VercelScope 2>&1
    $deployCode = $LASTEXITCODE
    $deployText = (($deployOut | ForEach-Object {"$_"}) -join "`n")
    if ($deployCode -ne 0) { throw "Deploy Vercel falhou.`n$deployText" }
    $matches = [regex]::Matches($deployText,'https://[A-Za-z0-9.-]+\.vercel\.app')
    if ($matches.Count -lt 1) { throw "Não consegui identificar URL do deploy.`n$deployText" }
    $deployUrl = $matches[$matches.Count-1].Value.TrimEnd('/')
    Ok "Backend online: $deployUrl"

    Etapa 'Teste real Turso + usuário + save + ADM'
    $health = $null
    for ($i=1; $i -le 20; $i++) {
      try { $health = Post-Json "$deployUrl/api/reino" @{action='health'}; if ($health.ok) { break } } catch { Start-Sleep -Seconds 3 }
    }
    if (-not $health -or -not $health.ok) { throw 'Health da API/Turso não passou.' }

    $stamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $testUser = "rtprobe_$stamp"
    $testEmail = "$testUser@example.invalid"
    $testPass = 'Probe!' + (Novo-Segredo 24)
    $reg = Post-Json "$deployUrl/api/reino" @{action='register';email=$testEmail;username=$testUser;password=$testPass}
    if (-not $reg.access_token) { throw 'Registro real não retornou sessão.' }
    $playerToken = [string]$reg.access_token

    $worlds = Post-Json "$deployUrl/api/reino" @{action='list_worlds'} $playerToken
    $defaultWorldId = 'd5a546fb-316d-4332-ae92-1886d80b07df'
    $join = Post-Json "$deployUrl/api/reino" @{action='join_world';world_id=$defaultWorldId;player_name=$testUser} $playerToken
    if (-not $join.ok) { throw 'Entrada no Mundo 1 falhou.' }

    $probeState = @{probe='reino-tribal-turso';stamp=$stamp;ok=$true}
    $save = Post-Json "$deployUrl/api/reino" @{action='save';world_id=$defaultWorldId;state=$probeState} $playerToken
    if (-not $save.ok) { throw 'Save real falhou.' }
    $load = Post-Json "$deployUrl/api/reino" @{action='load_save';world_id=$defaultWorldId} $playerToken
    if (-not $load.state -or $load.state.probe -ne 'reino-tribal-turso') { throw 'Load real falhou.' }

    $adm = Post-Json "$deployUrl/api/reino" @{action='login';identifier='reinos_admin';password=$adminPassword}
    if (-not $adm.access_token -or $adm.user.role -ne 'admin') { throw 'Login ADM real falhou.' }
    $adminToken = [string]$adm.access_token
    $status = Post-Json "$deployUrl/api/reino" @{action='admin_status'} $adminToken
    if (-not $status.ok) { throw 'admin_status falhou.' }
    $dash = Post-Json "$deployUrl/api/admin" @{action='dashboard'} $adminToken
    if (-not $dash) { throw 'Dashboard ADM falhou.' }
    Ok 'health + registro + mundo + save/load + login ADM + dashboard ADM.'

    Etapa 'Ligando GitHub Pages ao backend'
    Set-GitHubVariable 'REINO_TRIBAL_API_BASE' $deployUrl $gh
    Ok 'REINO_TRIBAL_API_BASE configurada.'

    Etapa 'Conectando Vercel ao GitHub quando suportado'
    $gitHelp = (& $script:Npx --yes vercel@latest git --help 2>&1 | Out-String)
    if ($gitHelp -match '\bconnect\b') {
      & $script:Npx --yes vercel@latest git connect "https://github.com/$Repositorio" --scope $VercelScope *> $null
      if ($LASTEXITCODE -eq 0) { Ok 'GitHub conectado ao projeto Vercel.' } else { Aviso 'Deploy atual está pronto; conexão Git automática não foi aceita pela CLI.' }
    }

    Etapa 'Checks e merge da PR'
    $headSha = (& $gh pr view $PullRequest -R $Repositorio --json headRefOid --jq '.headRefOid').Trim()
    if (-not $headSha) { throw 'Não consegui obter HEAD da PR.' }
    & $gh pr ready $PullRequest -R $Repositorio *> $null
    if ($LASTEXITCODE -ne 0) { throw 'Não consegui marcar PR como pronta.' }
    & $gh pr checks $PullRequest -R $Repositorio --watch --fail-fast
    if ($LASTEXITCODE -ne 0) { throw 'Checks da PR falharam; merge cancelado.' }
    & $gh pr merge $PullRequest -R $Repositorio --squash --match-head-commit $headSha
    if ($LASTEXITCODE -ne 0) { throw 'Merge da PR falhou.' }
    Ok 'Migração Turso mesclada em main.'

    Etapa 'Publicando GitHub Pages'
    & $gh workflow run deploy-reino-tribal-pages.yml -R $Repositorio --ref main
    if ($LASTEXITCODE -ne 0) { throw 'Não consegui disparar o deploy Pages.' }
    Start-Sleep -Seconds 6
    $runId = (& $gh run list -R $Repositorio --workflow deploy-reino-tribal-pages.yml --branch main --event workflow_dispatch --limit 1 --json databaseId --jq '.[0].databaseId').Trim()
    if (-not $runId) { throw 'Run do GitHub Pages não encontrado.' }
    & $gh run watch $runId -R $Repositorio --exit-status --compact
    if ($LASTEXITCODE -ne 0) { throw 'Deploy GitHub Pages falhou.' }

    $publicUrl = 'https://kaalflash12.github.io/reinos-tribais-online/'
    $html = (Invoke-WebRequest -Uri ($publicUrl + '?turso=' + [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) -UseBasicParsing -TimeoutSec 60).Content
    if ($html -notmatch 'reino-tribal-config\.js\?v=1\.0\.4-turso' -or $html -notmatch 'rt85-auth-bridge\.js\?v=1\.0\.4-turso') { throw 'Página pública respondeu, mas não contém a release Turso esperada.' }
    Ok "Reino Tribal público: $publicUrl"

    Etapa 'Salvando credenciais administrativas locais'
    $credDir = Join-Path $env:USERPROFILE 'Documents\ReinoTribal'
    New-Item -ItemType Directory -Force -Path $credDir | Out-Null
    $credFile = Join-Path $credDir 'CREDENCIAIS_ADMIN_REINO_TRIBAL.txt'
    @"
REINO TRIBAL - PRODUÇÃO TURSO
Gerado: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Site: $publicUrl
Backend: $deployUrl
Banco Turso: $BancoTurso
Usuário ADM: reinos_admin
Senha ADM: $adminPassword
Chave de recuperação: $recoveryKey
"@ | Set-Content -Path $credFile -Encoding UTF8
    try {
      & icacls.exe $credFile /inheritance:r /grant:r "$($env:USERNAME):(F)" *> $null
    } catch {}
    Ok "Credenciais salvas em: $credFile"

    Start-Process $publicUrl
    Write-Host "`n============================================================" -ForegroundColor Green
    Write-Host 'REINO TRIBAL TURSO: CONFIGURAÇÃO COMPLETA E TESTADA' -ForegroundColor Green
    Write-Host "SITE: $publicUrl" -ForegroundColor Green
    Write-Host "BACKEND: $deployUrl" -ForegroundColor Green
    Write-Host "ADM: reinos_admin" -ForegroundColor Green
    Write-Host "SENHA: salva em $credFile" -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Green
  }
  finally { Pop-Location }
}
finally {
  if (Test-Path $work) { Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue }
}
