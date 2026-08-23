param(
  [string]$Repositorio = 'kaalflash12/reinos-tribais-online',
  [string]$Branch = 'rt-turso-migration',
  [string]$ProjetoVercel = 'reino-tribal-api',
  [string]$VercelScope = 'kaalflash12s-projects',
  [int]$PullRequest = 53
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$NodeVersion = '24.19.0'
$VercelVersion = '59.3.0'
$ToolRoot = Join-Path $env:LOCALAPPDATA 'ReinoTribalTools'
$WorkRoot = Join-Path $env:TEMP ('reino-tribal-' + [Guid]::NewGuid().ToString('N'))
$CredDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'ReinoTribal'
$CredFile = Join-Path $CredDir 'CREDENCIAIS_ADMIN_REINO_TRIBAL.txt'

function Etapa([string]$Texto) { Write-Host "`n=== $Texto ===" -ForegroundColor Cyan }
function Ok([string]$Texto) { Write-Host "PASS: $Texto" -ForegroundColor Green }
function Aviso([string]$Texto) { Write-Host "AVISO: $Texto" -ForegroundColor Yellow }
function Falhar([string]$Texto) { throw $Texto }

function Baixar-Uma-Vez([string]$Uri, [string]$Destino) {
  if (Test-Path $Destino) {
    $item = Get-Item $Destino -ErrorAction SilentlyContinue
    if ($item -and $item.Length -gt 0) { return }
    Remove-Item $Destino -Force -ErrorAction SilentlyContinue
  }
  $dir = Split-Path $Destino -Parent
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  Write-Host "Baixando uma vez: $Uri"
  Invoke-WebRequest -UseBasicParsing -Uri $Uri -OutFile $Destino -TimeoutSec 180
  if (-not (Test-Path $Destino) -or (Get-Item $Destino).Length -le 0) {
    Falhar "Download falhou: $Uri"
  }
}

function Novo-Segredo([int]$Bytes = 32) {
  $buf = New-Object byte[] $Bytes
  $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
  try { $rng.GetBytes($buf) } finally { $rng.Dispose() }
  return ([Convert]::ToBase64String($buf).TrimEnd('=').Replace('+','-').Replace('/','_'))
}

function Garantir-NodePortatil {
  $nodeDir = Join-Path $ToolRoot "node-v$NodeVersion-win-x64"
  $node = Join-Path $nodeDir 'node.exe'
  $npm = Join-Path $nodeDir 'npm.cmd'
  if ((Test-Path $node) -and (Test-Path $npm)) {
    $v = (& $node --version 2>$null | Out-String).Trim()
    if ($v -eq "v$NodeVersion") {
      $env:Path = "$nodeDir;$env:Path"
      return [pscustomobject]@{ Node=$node; Npm=$npm; Dir=$nodeDir }
    }
  }

  Etapa "Node portátil v$NodeVersion (sem instalar no Windows)"
  New-Item -ItemType Directory -Force -Path $ToolRoot | Out-Null
  $zipName = "node-v$NodeVersion-win-x64.zip"
  $zip = Join-Path $ToolRoot $zipName
  $base = "https://nodejs.org/dist/v$NodeVersion"
  Baixar-Uma-Vez "$base/$zipName" $zip

  $sums = Invoke-RestMethod -Uri "$base/SHASUMS256.txt" -TimeoutSec 60
  $m = [regex]::Match([string]$sums, "(?m)^([a-fA-F0-9]{64})\s+$([regex]::Escape($zipName))$")
  if (-not $m.Success) { Falhar 'Não consegui obter o SHA256 oficial do Node.' }
  $real = (Get-FileHash -Algorithm SHA256 $zip).Hash.ToLowerInvariant()
  $esperado = $m.Groups[1].Value.ToLowerInvariant()
  if ($real -ne $esperado) {
    Remove-Item $zip -Force -ErrorAction SilentlyContinue
    Falhar 'SHA256 do Node não confere. O arquivo foi removido e o processo parou.'
  }

  Remove-Item $nodeDir -Recurse -Force -ErrorAction SilentlyContinue
  Expand-Archive -Path $zip -DestinationPath $ToolRoot -Force
  if (-not (Test-Path $node) -or -not (Test-Path $npm)) { Falhar 'Node portátil foi extraído, mas os executáveis não apareceram.' }
  $env:Path = "$nodeDir;$env:Path"
  $v = (& $node --version 2>$null | Out-String).Trim()
  if ($v -ne "v$NodeVersion") { Falhar "Node portátil inválido: $v" }
  Ok "Node portátil $v"
  return [pscustomobject]@{ Node=$node; Npm=$npm; Dir=$nodeDir }
}

function Garantir-GhPortatil {
  $system = Get-Command gh.exe -ErrorAction SilentlyContinue
  if ($system) {
    & $system.Source --version *> $null
    if ($LASTEXITCODE -eq 0) { return $system.Source }
  }

  $existing = Get-ChildItem -Path (Join-Path $ToolRoot 'gh-*') -Filter gh.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($existing) {
    & $existing.FullName --version *> $null
    if ($LASTEXITCODE -eq 0) { return $existing.FullName }
  }

  Etapa 'GitHub CLI portátil (sem winget/instalador)'
  $rel = Invoke-RestMethod -Headers @{ 'User-Agent'='ReinoTribalBootstrap' } -Uri 'https://api.github.com/repos/cli/cli/releases/latest' -TimeoutSec 60
  $tag = [string]$rel.tag_name
  $ver = $tag.TrimStart('v')
  $assetName = "gh_${ver}_windows_amd64.zip"
  $asset = @($rel.assets | Where-Object { $_.name -eq $assetName }) | Select-Object -First 1
  if (-not $asset) { Falhar "GitHub CLI portátil não encontrado na release $tag." }
  $zip = Join-Path $ToolRoot $assetName
  Baixar-Uma-Vez ([string]$asset.browser_download_url) $zip
  $dest = Join-Path $ToolRoot "gh-$ver"
  Remove-Item $dest -Recurse -Force -ErrorAction SilentlyContinue
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  Expand-Archive -Path $zip -DestinationPath $dest -Force
  $gh = Get-ChildItem -Path $dest -Filter gh.exe -Recurse | Select-Object -First 1
  if (-not $gh) { Falhar 'gh.exe não apareceu após extrair o ZIP portátil.' }
  & $gh.FullName --version *> $null
  if ($LASTEXITCODE -ne 0) { Falhar 'gh.exe portátil não executa.' }
  Ok 'GitHub CLI portátil validado.'
  return $gh.FullName
}

function Garantir-VercelPortatil([string]$Npm) {
  $home = Join-Path $ToolRoot "vercel-$VercelVersion"
  $bin = Join-Path $home 'node_modules\.bin\vercel.cmd'
  if (Test-Path $bin) {
    & $bin --version *> $null
    if ($LASTEXITCODE -eq 0) { return $bin }
  }

  Etapa "Vercel CLI local $VercelVersion (uma única cópia)"
  New-Item -ItemType Directory -Force -Path $home | Out-Null
  $env:NPM_CONFIG_CACHE = Join-Path $ToolRoot 'npm-cache'
  & $Npm install --prefix $home "vercel@$VercelVersion" --no-audit --no-fund --loglevel=error
  if ($LASTEXITCODE -ne 0) { Falhar 'Falha ao preparar a cópia local da Vercel CLI. O processo parou; não haverá nova tentativa automática.' }
  if (-not (Test-Path $bin)) { Falhar 'Vercel CLI terminou sem criar vercel.cmd.' }
  & $bin --version *> $null
  if ($LASTEXITCODE -ne 0) { Falhar 'Vercel CLI local não executa.' }
  Ok "Vercel CLI $VercelVersion validada."
  return $bin
}

function Executar([string]$Exe, [string[]]$Args, [string]$Erro) {
  & $Exe @Args
  if ($LASTEXITCODE -ne 0) { Falhar $Erro }
}

function Capturar([string]$Exe, [string[]]$Args) {
  $out = & $Exe @Args 2>&1
  [pscustomobject]@{ Code=$LASTEXITCODE; Text=(($out | ForEach-Object { "$_" }) -join "`n").Trim() }
}

function Ler-Env([string]$Path, [string]$Nome) {
  $rx = '^' + [regex]::Escape($Nome) + '=(.*)$'
  $line = Get-Content $Path -ErrorAction Stop | Where-Object { $_ -match $rx } | Select-Object -Last 1
  if (-not $line) { return '' }
  $value = [regex]::Match($line,$rx).Groups[1].Value.Trim()
  if ($value.Length -ge 2 -and (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'")))) {
    $value = $value.Substring(1,$value.Length-2)
  }
  return $value
}

function Set-GitHubSecret([string]$Gh, [string]$Nome, [string]$Valor) {
  $Valor | & $Gh secret set $Nome -R $Repositorio
  if ($LASTEXITCODE -ne 0) { Falhar "Falha gravando GitHub Secret $Nome." }
}

function Set-GitHubVariable([string]$Gh, [string]$Nome, [string]$Valor) {
  $Valor | & $Gh variable set $Nome -R $Repositorio
  if ($LASTEXITCODE -ne 0) { Falhar "Falha gravando GitHub Variable $Nome." }
}

function Set-VercelEnv([string]$Vercel, [string]$Nome, [string]$Valor) {
  $help = (Capturar $Vercel @('env','add','--help')).Text
  $args = @('env','add',$Nome,'production','--scope',$VercelScope)
  if ($help -match '(?m)--yes\b') { $args += '--yes' }
  if ($help -match '(?m)--force\b') { $args += '--force' }
  if ($help -match '(?m)--sensitive\b') { $args += '--sensitive' }
  if ($help -notmatch '(?m)--force\b') {
    & $Vercel env rm $Nome production --yes --scope $VercelScope *> $null
  }
  $Valor | & $Vercel @args
  if ($LASTEXITCODE -ne 0) { Falhar "Falha configurando $Nome na Vercel." }
}

function Post-Json([string]$Uri, [hashtable]$Body, [string]$Bearer = '') {
  $headers = @{}
  if ($Bearer) { $headers.Authorization = "Bearer $Bearer" }
  Invoke-RestMethod -Uri $Uri -Method Post -Headers $headers -ContentType 'application/json' -Body ($Body | ConvertTo-Json -Depth 50 -Compress) -TimeoutSec 60
}

function Esperar-Checks([string]$Gh) {
  Etapa 'Checks da PR (limite de 10 minutos)'
  for ($i=1; $i -le 60; $i++) {
    $r = Capturar $Gh @('pr','checks',"$PullRequest",'-R',$Repositorio,'--json','name,bucket')
    if ($r.Code -eq 0 -and $r.Text) {
      try { $checks = @($r.Text | ConvertFrom-Json) } catch { $checks = @() }
      if ($checks.Count -gt 0) {
        $falhas = @($checks | Where-Object { $_.bucket -in @('fail','cancel') })
        if ($falhas.Count -gt 0) { Falhar ('Checks falharam: ' + (($falhas.name) -join ', ')) }
        $pendentes = @($checks | Where-Object { $_.bucket -eq 'pending' })
        if ($pendentes.Count -eq 0) { Ok 'Todos os checks terminaram sem falha.'; return }
      }
    }
    Start-Sleep -Seconds 10
  }
  Falhar 'Os checks não terminaram em 10 minutos. O script parou sem fazer merge.'
}

New-Item -ItemType Directory -Force -Path $ToolRoot,$CredDir | Out-Null

Etapa 'Ferramentas portáteis'
$nodeInfo = Garantir-NodePortatil
$gh = Garantir-GhPortatil
$vercel = Garantir-VercelPortatil $nodeInfo.Npm

Etapa 'Login GitHub'
& $gh auth status *> $null
if ($LASTEXITCODE -ne 0) {
  Write-Host 'Confirme o login do GitHub no navegador.' -ForegroundColor Yellow
  Executar $gh @('auth','login','--web','--git-protocol','https') 'Login GitHub falhou.'
}
& $gh repo view $Repositorio *> $null
if ($LASTEXITCODE -ne 0) { Falhar "A conta GitHub autenticada não acessa $Repositorio." }
Ok 'GitHub autenticado.'

Etapa 'Login Vercel'
& $vercel whoami --scope $VercelScope *> $null
if ($LASTEXITCODE -ne 0) {
  Write-Host 'Confirme o login da Vercel no navegador.' -ForegroundColor Yellow
  Executar $vercel @('login') 'Login Vercel falhou.'
}
& $vercel whoami --scope $VercelScope *> $null
if ($LASTEXITCODE -ne 0) { Falhar 'A Vercel continua sem autenticação após o login.' }
Ok 'Vercel autenticada.'

Etapa 'Baixando a branch do Reino Tribal sem Git/instalador'
New-Item -ItemType Directory -Force -Path $WorkRoot | Out-Null
$sourceZip = Join-Path $WorkRoot 'source.zip'
$codeload = "https://codeload.github.com/$Repositorio/zip/refs/heads/$Branch"
Baixar-Uma-Vez $codeload $sourceZip
Expand-Archive -Path $sourceZip -DestinationPath $WorkRoot -Force
$work = Get-ChildItem $WorkRoot -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'vercel.json') } | Select-Object -First 1
if (-not $work) { Falhar 'Não encontrei a raiz do projeto depois de extrair a branch.' }
Push-Location $work.FullName

try {
  Etapa "Projeto Vercel exclusivo: $ProjetoVercel"
  $inspect = Capturar $vercel @('project','inspect',$ProjetoVercel,'--scope',$VercelScope)
  if ($inspect.Code -ne 0) {
    Executar $vercel @('project','add',$ProjetoVercel,'--scope',$VercelScope) 'Falha criando o projeto Vercel exclusivo. O script não tentará criar de novo nesta execução.'
  }
  Executar $vercel @('link','--yes','--project',$ProjetoVercel,'--scope',$VercelScope) 'Falha ligando a pasta ao projeto Vercel.'
  Ok 'Projeto Vercel dedicado ligado.'

  Etapa 'Turso nativo da Vercel'
  $envLs = Capturar $vercel @('env','ls','production','--scope',$VercelScope)
  $temTurso = ($envLs.Text -match 'TURSO_DATABASE_URL') -and ($envLs.Text -match 'TURSO_AUTH_TOKEN')
  if (-not $temTurso) {
    Write-Host 'Será provisionado UM banco Turso exclusivo pelo Marketplace nativo da Vercel.' -ForegroundColor Yellow
    Write-Host 'Se Vercel/Turso abrir confirmação de conta ou plano gratuito, apenas confirme.' -ForegroundColor Yellow
    $help = (Capturar $vercel @('integration','add','tursocloud/database','--help')).Text
    $args = @('integration','add','tursocloud/database')
    if ($help -match '(?m)--yes\b') { $args += '--yes' }
    if ($help -match '(?m)--no-claim\b') { $args += '--no-claim' }
    & $vercel @args --scope $VercelScope
    if ($LASTEXITCODE -ne 0) { Falhar 'Provisionamento Turso pela Vercel falhou. O processo parou aqui e NÃO repetirá instalação/provisionamento.' }
  } else {
    Ok 'Turso já está conectado a este projeto; nenhuma reinstalação foi feita.'
  }

  $envFile = Join-Path $WorkRoot 'production.env'
  Remove-Item $envFile -Force -ErrorAction SilentlyContinue
  Executar $vercel @('env','pull',$envFile,'--environment=production','--yes','--scope',$VercelScope) 'Falha puxando as variáveis de produção da Vercel.'
  $dbUrl = Ler-Env $envFile 'TURSO_DATABASE_URL'
  $dbToken = Ler-Env $envFile 'TURSO_AUTH_TOKEN'
  if (-not $dbUrl -or -not $dbToken) { Falhar 'A integração terminou, mas TURSO_DATABASE_URL/TURSO_AUTH_TOKEN não apareceram no ambiente de produção.' }
  Ok 'Credenciais Turso reais obtidas da integração nativa.'

  $adminPassword = 'RT!' + (Novo-Segredo 30)
  $recoveryKey = Novo-Segredo 48

  Etapa 'Secrets privados da aplicação'
  Set-VercelEnv $vercel 'RT_ADMIN_PASSWORD' $adminPassword
  Set-VercelEnv $vercel 'RT_ADMIN_RECOVERY_KEY' $recoveryKey
  Set-GitHubSecret $gh 'TURSO_DATABASE_URL' $dbUrl
  Set-GitHubSecret $gh 'TURSO_AUTH_TOKEN' $dbToken
  Set-GitHubSecret $gh 'RT_ADMIN_PASSWORD' $adminPassword
  Set-GitHubSecret $gh 'RT_ADMIN_RECOVERY_KEY' $recoveryKey

  if (Test-Path '.vercel/project.json') {
    $pj = Get-Content '.vercel/project.json' -Raw | ConvertFrom-Json
    if ($pj.orgId) { Set-GitHubSecret $gh 'VERCEL_ORG_ID' ([string]$pj.orgId) }
    if ($pj.projectId) { Set-GitHubSecret $gh 'VERCEL_PROJECT_ID' ([string]$pj.projectId) }
  }
  Ok 'Secrets gravados sem colocá-los no código.'

  Etapa 'Deploy de produção'
  $deploy = Capturar $vercel @('deploy','--prod','--yes','--scope',$VercelScope)
  if ($deploy.Code -ne 0) { Falhar "Deploy Vercel falhou.`n$($deploy.Text)" }
  $urls = [regex]::Matches($deploy.Text,'https://[A-Za-z0-9.-]+\.vercel\.app')
  if ($urls.Count -eq 0) { Falhar "Deploy terminou sem URL detectável.`n$($deploy.Text)" }
  $deployUrl = $urls[$urls.Count-1].Value.TrimEnd('/')
  Ok "Backend: $deployUrl"

  Etapa 'Teste real: Turso + conta + mundo + save/load + ADM'
  $health = $null
  for ($i=1; $i -le 20; $i++) {
    try {
      $health = Post-Json "$deployUrl/api/reino" @{ action='health' }
      if ($health.ok) { break }
    } catch {}
    Start-Sleep -Seconds 3
  }
  if (-not $health -or -not $health.ok) { Falhar 'Health real da API/Turso não passou em 60 segundos.' }

  $stamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  $testUser = "rtprobe_$stamp"
  $testEmail = "$testUser@example.invalid"
  $testPass = 'Probe!' + (Novo-Segredo 24)
  $reg = Post-Json "$deployUrl/api/reino" @{ action='register'; email=$testEmail; username=$testUser; password=$testPass }
  if (-not $reg.access_token) { Falhar 'Registro real não retornou sessão.' }
  $playerToken = [string]$reg.access_token
  $worldId = 'd5a546fb-316d-4332-ae92-1886d80b07df'
  $join = Post-Json "$deployUrl/api/reino" @{ action='join_world'; world_id=$worldId; player_name=$testUser } $playerToken
  if (-not $join.ok) { Falhar 'Entrada no Mundo 1 falhou.' }
  $probeState = @{ probe='reino-tribal-turso'; stamp=$stamp; ok=$true }
  $save = Post-Json "$deployUrl/api/reino" @{ action='save'; world_id=$worldId; state=$probeState } $playerToken
  if (-not $save.ok) { Falhar 'Save real falhou.' }
  $load = Post-Json "$deployUrl/api/reino" @{ action='load_save'; world_id=$worldId } $playerToken
  if (-not $load.state -or $load.state.probe -ne 'reino-tribal-turso') { Falhar 'Load real falhou.' }
  $adm = Post-Json "$deployUrl/api/reino" @{ action='login'; identifier='reinos_admin'; password=$adminPassword }
  if (-not $adm.access_token -or $adm.user.role -ne 'admin') { Falhar 'Login ADM real falhou.' }
  $adminToken = [string]$adm.access_token
  $status = Post-Json "$deployUrl/api/reino" @{ action='admin_status' } $adminToken
  if (-not $status.ok) { Falhar 'admin_status real falhou.' }
  $dash = Post-Json "$deployUrl/api/admin" @{ action='dashboard' } $adminToken
  if (-not $dash) { Falhar 'Dashboard ADM real falhou.' }
  Ok 'Testes reais completos passaram.'

  Etapa 'Configuração pública'
  Set-GitHubVariable $gh 'REINO_TRIBAL_API_BASE' $deployUrl

  $gitHelp = (Capturar $vercel @('git','--help')).Text
  if ($gitHelp -match '(?m)\bconnect\b') {
    $gitConnect = Capturar $vercel @('git','connect',"https://github.com/$Repositorio",'--yes','--scope',$VercelScope)
    if ($gitConnect.Code -ne 0) { Aviso 'O deploy está funcional, mas a conexão Git automática foi ignorada porque a Vercel não a aceitou.' }
  }

  Etapa 'PR 53: ready, checks e merge somente após testes reais'
  Executar $gh @('pr','ready',"$PullRequest",'-R',$Repositorio) 'Não consegui marcar a PR como pronta.'
  Esperar-Checks $gh
  Executar $gh @('pr','merge',"$PullRequest",'-R',$Repositorio,'--squash') 'Merge da PR falhou. Nada será repetido automaticamente.'
  Ok 'PR mesclada.'

  Etapa 'Publicação GitHub Pages'
  Executar $gh @('workflow','run','deploy-reino-tribal-pages.yml','-R',$Repositorio,'--ref','main') 'Falha disparando o deploy do GitHub Pages.'
  Start-Sleep -Seconds 5
  $run = Capturar $gh @('run','list','-R',$Repositorio,'--workflow','deploy-reino-tribal-pages.yml','--branch','main','--limit','1','--json','databaseId,status,conclusion')
  if ($run.Code -eq 0 -and $run.Text) {
    try {
      $arr = @($run.Text | ConvertFrom-Json)
      if ($arr.Count -gt 0) {
        $runId = [string]$arr[0].databaseId
        for ($i=1; $i -le 60; $i++) {
          $view = Capturar $gh @('run','view',$runId,'-R',$Repositorio,'--json','status,conclusion')
          if ($view.Code -eq 0 -and $view.Text) {
            $obj = $view.Text | ConvertFrom-Json
            if ($obj.status -eq 'completed') {
              if ($obj.conclusion -ne 'success') { Falhar "GitHub Pages terminou com: $($obj.conclusion)" }
              break
            }
          }
          if ($i -eq 60) { Falhar 'GitHub Pages não terminou em 10 minutos.' }
          Start-Sleep -Seconds 10
        }
      }
    } catch { Falhar "Falha verificando GitHub Pages: $($_.Exception.Message)" }
  }

  $publicUrl = 'https://kaalflash12.github.io/reinos-tribais-online/'
  $public = $null
  for ($i=1; $i -le 20; $i++) {
    try {
      $public = Invoke-WebRequest -UseBasicParsing -Uri $publicUrl -TimeoutSec 30
      if ($public.StatusCode -eq 200 -and $public.Content -match '1\.0\.4-turso') { break }
    } catch {}
    Start-Sleep -Seconds 3
  }
  if (-not $public -or $public.StatusCode -ne 200 -or $public.Content -notmatch '1\.0\.4-turso') { Falhar 'Página pública não confirmou a versão Turso em 60 segundos.' }

  $cred = @"
REINO TRIBAL - PRODUÇÃO
Data: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Usuário ADM: reinos_admin
Senha ADM: $adminPassword
Backend: $deployUrl
Jogo: $publicUrl
Projeto Vercel: $ProjetoVercel
Banco: Turso exclusivo provisionado pela integração nativa da Vercel
"@
  Set-Content -Path $CredFile -Value $cred -Encoding UTF8
  Ok "Credenciais ADM salvas em: $CredFile"
  Ok "JOGO ONLINE: $publicUrl"
  Ok "BACKEND ONLINE: $deployUrl"

} finally {
  Pop-Location -ErrorAction SilentlyContinue
  Remove-Item (Join-Path $WorkRoot 'production.env') -Force -ErrorAction SilentlyContinue
  Remove-Item $WorkRoot -Recurse -Force -ErrorAction SilentlyContinue
  $dbToken = $null
  $recoveryKey = $null
  $testPass = $null
}
