param(
  [string]$Repositorio = 'kaalflash12/reinos-tribais-online',
  [string]$BancoTurso = 'reino-tribal-prod',
  [string]$ProjetoVercel = 'reino-tribal-api',
  [int]$PullRequest = 53
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Etapa([string]$Texto) {
  Write-Host "`n=== $Texto ===" -ForegroundColor Cyan
}

function Atualizar-Path {
  $machine = [Environment]::GetEnvironmentVariable('Path','Machine')
  $user = [Environment]::GetEnvironmentVariable('Path','User')
  $env:Path = "$machine;$user"
}

function Exigir-Comando([string]$Nome, [string]$WingetId) {
  $cmd = Get-Command $Nome -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
    throw "$Nome não encontrado e winget não está disponível."
  }
  Etapa "Instalando $Nome"
  & winget.exe install --id $WingetId --exact --source winget --accept-package-agreements --accept-source-agreements --silent
  if ($LASTEXITCODE -ne 0) { throw "Falha instalando $Nome pelo winget." }
  Atualizar-Path
  $cmd = Get-Command $Nome -ErrorAction SilentlyContinue
  if (-not $cmd) {
    throw "$Nome foi instalado, mas ainda não entrou no PATH. Reabra o PowerShell e execute este arquivo novamente."
  }
  return $cmd.Source
}

function Executar-ComEntrada(
  [string]$Arquivo,
  [string]$Argumentos,
  [string]$Entrada,
  [string]$Diretorio = ''
) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  if ($Arquivo -match '\.(cmd|bat)$') {
    $psi.FileName = $env:ComSpec
    $psi.Arguments = '/d /s /c ""' + $Arquivo + '" ' + $Argumentos + '"'
  } else {
    $psi.FileName = $Arquivo
    $psi.Arguments = $Argumentos
  }
  $psi.UseShellExecute = $false
  $psi.RedirectStandardInput = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.CreateNoWindow = $true
  if ($Diretorio) { $psi.WorkingDirectory = $Diretorio }

  $p = [System.Diagnostics.Process]::Start($psi)
  if (-not $p) { throw "Não foi possível iniciar $Arquivo." }
  $p.StandardInput.Write($Entrada)
  $p.StandardInput.Close()
  $stdout = $p.StandardOutput.ReadToEnd()
  $stderr = $p.StandardError.ReadToEnd()
  $p.WaitForExit()
  if ($p.ExitCode -ne 0) {
    throw "Comando falhou ($($p.ExitCode)): $Arquivo $Argumentos`n$stdout`n$stderr"
  }
  return $stdout.Trim()
}

function Turso-Capturar([string]$Comando) {
  $full = 'export PATH="$HOME/.turso:$HOME/.local/bin:$PATH"; ' + $Comando
  $saida = & wsl.exe bash -lc $full 2>&1
  $codigo = $LASTEXITCODE
  return [pscustomobject]@{
    Codigo = $codigo
    Texto = (($saida | ForEach-Object { "$_" }) -join "`n").Trim()
  }
}

function Ler-Segredo([string]$Prompt) {
  $secure = Read-Host $Prompt -AsSecureString
  $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

function Post-Json([string]$Uri, [hashtable]$Body, [string]$Bearer = '') {
  $headers = @{}
  if ($Bearer) { $headers.Authorization = "Bearer $Bearer" }
  return Invoke-RestMethod `
    -Uri $Uri `
    -Method Post `
    -ContentType 'application/json' `
    -Headers $headers `
    -Body ($Body | ConvertTo-Json -Depth 30 -Compress) `
    -TimeoutSec 45
}

Etapa 'Pré-requisitos locais'
$gh = Exigir-Comando 'gh.exe' 'GitHub.cli'
$git = Exigir-Comando 'git.exe' 'Git.Git'
$npx = Exigir-Comando 'npx.cmd' 'OpenJS.NodeJS.LTS'

if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
  throw 'WSL não está disponível. O Turso Cloud CLI oficial no Windows usa WSL.'
}
$wslList = & wsl.exe -l -q 2>$null
if ($LASTEXITCODE -ne 0 -or -not (($wslList | Out-String).Trim())) {
  Etapa 'Instalando WSL/Ubuntu'
  & wsl.exe --install -d Ubuntu
  throw 'O Windows iniciou a instalação do WSL. Se pedir reinicialização, reinicie e execute este arquivo novamente.'
}

Etapa 'Turso CLI'
$probe = Turso-Capturar 'command -v turso >/dev/null 2>&1'
if ($probe.Codigo -ne 0) {
  & wsl.exe bash -lc 'curl -sSfL https://get.tur.so/install.sh | bash'
  if ($LASTEXITCODE -ne 0) { throw 'Falha instalando o Turso CLI.' }
}
$probe = Turso-Capturar 'turso --version'
if ($probe.Codigo -ne 0) { throw 'Turso CLI não ficou disponível no WSL.' }
Write-Host $probe.Texto

Etapa 'Autenticação Turso'
$who = Turso-Capturar 'turso auth whoami'
if ($who.Codigo -ne 0) {
  Write-Host 'O Turso mostrará uma URL/código para autenticação. Nenhum token será colocado no script.' -ForegroundColor Yellow
  & wsl.exe bash -lc 'export PATH="$HOME/.turso:$HOME/.local/bin:$PATH"; turso auth login --headless'
  if ($LASTEXITCODE -ne 0) { throw 'Login no Turso falhou.' }
}
$who = Turso-Capturar 'turso auth whoami'
if ($who.Codigo -ne 0) { throw 'Turso ainda não autenticado.' }
Write-Host "Turso autenticado como: $($who.Texto)"

Etapa "Banco Turso exclusivo: $BancoTurso"
if ($BancoTurso -notmatch '^[a-zA-Z0-9._-]+$') { throw 'Nome de banco Turso inválido.' }
$db = Turso-Capturar "turso db show $BancoTurso --url"
if ($db.Codigo -ne 0 -or -not $db.Texto) {
  $create = Turso-Capturar "turso db create $BancoTurso --wait"
  if ($create.Codigo -ne 0) { throw "Falha criando $BancoTurso.`n$($create.Texto)" }
  $db = Turso-Capturar "turso db show $BancoTurso --url"
}
$dbUrlRaw = $db.Texto -split "`n" | Where-Object { $_ -match '^(libsql|https)://' } | Select-Object -Last 1
$dbUrl = if ($dbUrlRaw) { ([string]$dbUrlRaw).Trim() } else { '' }
if (-not $dbUrl) { throw "Não consegui obter a URL do banco $BancoTurso." }

$tok = Turso-Capturar "turso db tokens create $BancoTurso --expiration never"
if ($tok.Codigo -ne 0) { throw "Falha criando token do banco.`n$($tok.Texto)" }
$tokenLines = @($tok.Texto -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$dbToken = $tokenLines | Where-Object { $_ -match '^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$' } | Select-Object -Last 1
if (-not $dbToken -and $tokenLines.Count -gt 0) { $dbToken = $tokenLines[-1] }
$dbToken = [string]$dbToken
if (-not $dbToken -or $dbToken.Length -lt 20) { throw 'Token Turso retornado em formato inesperado.' }
Write-Host 'Banco e token Turso obtidos sem expor o token.' -ForegroundColor Green

Etapa 'Senha administrativa do Reino Tribal'
do {
  $admin1 = Ler-Segredo 'Digite a senha do ADM reinos_admin (mínimo 12 caracteres)'
  $admin2 = Ler-Segredo 'Repita a senha do ADM'
  if ($admin1.Length -lt 12) {
    Write-Host 'Senha curta demais.' -ForegroundColor Yellow
    continue
  }
  if ($admin1 -cne $admin2) {
    Write-Host 'As senhas não coincidem.' -ForegroundColor Yellow
    continue
  }
  break
} while ($true)

Etapa 'GitHub CLI / Secrets'
& $gh auth status *> $null
if ($LASTEXITCODE -ne 0) {
  & $gh auth login --web --git-protocol https
  if ($LASTEXITCODE -ne 0) { throw 'Login do GitHub CLI falhou.' }
}
Executar-ComEntrada $gh "secret set TURSO_DATABASE_URL -R $Repositorio" $dbUrl | Out-Null
Executar-ComEntrada $gh "secret set TURSO_AUTH_TOKEN -R $Repositorio" $dbToken | Out-Null
Executar-ComEntrada $gh "secret set RT_ADMIN_PASSWORD -R $Repositorio" $admin1 | Out-Null
Write-Host 'Secrets Turso/ADM gravados no GitHub Actions.' -ForegroundColor Green

Etapa 'Autenticação Vercel'
& $npx --yes vercel@latest project ls --json *> $null
if ($LASTEXITCODE -ne 0) {
  & $npx --yes vercel@latest login --github
  if ($LASTEXITCODE -ne 0) { throw 'Login na Vercel falhou.' }
}

Etapa 'Preparando checkout isolado'
$work = Join-Path $env:TEMP ('reino-tribal-turso-' + [Guid]::NewGuid().ToString('N'))
& $gh repo clone $Repositorio $work -- --branch rt-turso-migration --single-branch
if ($LASTEXITCODE -ne 0) { throw 'Falha clonando a branch rt-turso-migration.' }

try {
  Push-Location $work
  try {
    Etapa "Projeto Vercel exclusivo: $ProjetoVercel"
    & $npx --yes vercel@latest project inspect $ProjetoVercel *> $null
    if ($LASTEXITCODE -ne 0) {
      & $npx --yes vercel@latest project add $ProjetoVercel
      if ($LASTEXITCODE -ne 0) { throw 'Falha criando o projeto Vercel exclusivo do Reino Tribal.' }
    }
    & $npx --yes vercel@latest link --yes --project $ProjetoVercel
    if ($LASTEXITCODE -ne 0) { throw 'Falha vinculando o projeto Vercel.' }

    Etapa 'Gravando variáveis sensíveis na Vercel'
    Executar-ComEntrada $npx '--yes vercel@latest env add TURSO_DATABASE_URL production --sensitive --force' $dbUrl $work | Out-Null
    Executar-ComEntrada $npx '--yes vercel@latest env add TURSO_AUTH_TOKEN production --sensitive --force' $dbToken $work | Out-Null
    Executar-ComEntrada $npx '--yes vercel@latest env add RT_ADMIN_PASSWORD production --sensitive --force' $admin1 $work | Out-Null

    Etapa 'Deploy de produção da API'
    $deployOut = & $npx --yes vercel@latest deploy --prod --yes 2>&1
    $deployCode = $LASTEXITCODE
    $deployText = (($deployOut | ForEach-Object { "$_" }) -join "`n")
    if ($deployCode -ne 0) { throw "Deploy Vercel falhou.`n$deployText" }
    $matches = [regex]::Matches($deployText, 'https://[A-Za-z0-9.-]+\.vercel\.app')
    if ($matches.Count -lt 1) { throw "Não consegui identificar a URL do deploy.`n$deployText" }
    $deployUrl = $matches[$matches.Count - 1].Value.TrimEnd('/')
    Write-Host "Backend: $deployUrl" -ForegroundColor Green

    Etapa 'Teste real Turso/API'
    $health = $null
    for ($i=1; $i -le 12; $i++) {
      try {
        $health = Post-Json "$deployUrl/api/reino" @{ action='health' }
        if ($health -and $health.ok -and $health.database -eq 'turso') { break }
      } catch {
        $health = $null
        Start-Sleep -Seconds 3
      }
    }
    if (-not $health -or -not $health.ok) { throw 'API/Turso não respondeu ao health check.' }

    $stamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $testUser = "rtprobe_$stamp"
    $testEmail = "$testUser@example.invalid"
    $testPass = 'RTp!' + [Guid]::NewGuid().ToString('N') + '9z'
    $reg = Post-Json "$deployUrl/api/reino" @{
      action='register'
      email=$testEmail
      username=$testUser
      password=$testPass
    }
    if (-not $reg.access_token) { throw 'Registro normal não retornou sessão.' }
    $playerToken = [string]$reg.access_token

    $saveProbe = @{ probe='reino-tribal-turso'; value=$stamp; ok=$true }
    $save = Post-Json "$deployUrl/api/reino" @{ action='save'; state=$saveProbe } $playerToken
    if (-not $save.ok) { throw 'Save normal falhou.' }
    $load = Post-Json "$deployUrl/api/reino" @{ action='load_save' } $playerToken
    if (-not $load.state -or $load.state.probe -ne 'reino-tribal-turso') { throw 'Leitura do save falhou.' }

    $admin = Post-Json "$deployUrl/api/reino" @{
      action='login'
      identifier='reinos_admin'
      password=$admin1
    }
    if (-not $admin.access_token -or $admin.user.role -ne 'admin') { throw 'Login ADM real falhou.' }
    Write-Host 'PASS: registro normal + sessão + save + load + login ADM.' -ForegroundColor Green

    Etapa 'Ligando GitHub Pages ao backend'
    Executar-ComEntrada $gh "variable set REINO_TRIBAL_API_BASE -R $Repositorio" $deployUrl | Out-Null
    Write-Host 'REINO_TRIBAL_API_BASE gravada como variável do repositório.' -ForegroundColor Green

    Etapa 'Revalidando PR'
    & $gh pr ready $PullRequest -R $Repositorio *> $null
    if ($LASTEXITCODE -ne 0) { throw 'Não consegui marcar o PR como pronto.' }
    & $gh pr checks $PullRequest -R $Repositorio --watch --fail-fast
    if ($LASTEXITCODE -ne 0) { throw 'Algum check do PR falhou; merge cancelado.' }

    Etapa 'Merge da migração Turso'
    & $gh pr merge $PullRequest -R $Repositorio --squash
    if ($LASTEXITCODE -ne 0) { throw 'Merge do PR falhou.' }

    Etapa 'Publicando GitHub Pages conectado ao Turso'
    & $gh workflow run deploy-reino-tribal-pages.yml -R $Repositorio --ref main
    if ($LASTEXITCODE -ne 0) { throw 'Falha disparando deploy do GitHub Pages.' }

    $runId = ''
    for ($i=1; $i -le 15; $i++) {
      Start-Sleep -Seconds 2
      $runRaw = & $gh run list `
        -R $Repositorio `
        --workflow deploy-reino-tribal-pages.yml `
        --branch main `
        --event workflow_dispatch `
        --limit 1 `
        --json databaseId `
        --jq '.[0].databaseId' 2>$null
      if ($LASTEXITCODE -eq 0 -and $runRaw) {
        $runId = ([string]($runRaw | Select-Object -First 1)).Trim()
        if ($runId) { break }
      }
    }
    if (-not $runId) { throw 'Não consegui localizar o run do deploy Pages.' }

    & $gh run watch $runId -R $Repositorio --exit-status
    if ($LASTEXITCODE -ne 0) { throw 'Deploy público do GitHub Pages falhou.' }

    $publicUrl = 'https://kaalflash12.github.io/reinos-tribais-online/'
    $html = (Invoke-WebRequest `
      -Uri ($publicUrl + '?turso=' + [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) `
      -UseBasicParsing `
      -TimeoutSec 45).Content
    if ($html -notmatch 'reino-tribal-config\.js\?v=1\.0\.4-turso' -or
        $html -notmatch 'rt85-auth-bridge\.js\?v=1\.0\.4-turso') {
      throw 'A página pública respondeu, mas não contém a configuração Turso esperada.'
    }

    Write-Host "`nREINO TRIBAL TURSO ONLINE" -ForegroundColor Green
    Write-Host "Jogo: $publicUrl"
    Write-Host "API:  $deployUrl"
    Write-Host 'Login normal, save/load e ADM foram testados antes da publicação.'
  }
  finally {
    Pop-Location
  }
}
finally {
  $admin1 = $null
  $admin2 = $null
  $dbToken = $null
  if (Test-Path $work) {
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
  }
}
