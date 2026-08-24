param(
  [string]$Repositorio = 'kaalflash12/reinos-tribais-online',
  [string]$Branch = 'rt-turso-migration',
  [string]$ProjetoVercel = 'reino-tribal-api',
  [string]$VercelScope = 'kaalflash12s-projects',
  [string]$VercelTeamId = 'team_o1RxZX0hDIO9c7SnuFozCmAB',
  [int]$PullRequest = 53
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$ToolRoot = Join-Path $env:LOCALAPPDATA 'ReinoTribalTools'
$WorkRoot = Join-Path $env:TEMP ('reino-tribal-recovery-' + [Guid]::NewGuid().ToString('N'))
$CredDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'ReinoTribal'
$CredFile = Join-Path $CredDir 'CREDENCIAIS_ADMIN_REINO_TRIBAL.txt'
$ForbiddenProjectPattern = '(?i)\bbw-v151\b|bacathegas|bacaworld'

function Etapa([string]$Texto) { Write-Host "`n=== $Texto ===" -ForegroundColor Cyan }
function Ok([string]$Texto) { Write-Host "PASS: $Texto" -ForegroundColor Green }
function Aviso([string]$Texto) { Write-Host "AVISO: $Texto" -ForegroundColor Yellow }
function Falhar([string]$Texto) { throw $Texto }

function Executar-Nativo([string]$Exe, [string[]]$Args) {
  $prev = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    $out = & $Exe @Args 2>&1
    $code = [int]$LASTEXITCODE
  } finally {
    $ErrorActionPreference = $prev
  }
  [pscustomobject]@{
    Code = $code
    Text = (($out | ForEach-Object { "$_" }) -join "`n").Trim()
  }
}

function Executar-NativoComEntrada([string]$Exe, [string[]]$Args, [string]$Entrada) {
  $prev = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    $out = $Entrada | & $Exe @Args 2>&1
    $code = [int]$LASTEXITCODE
  } finally {
    $ErrorActionPreference = $prev
  }
  [pscustomobject]@{
    Code = $code
    Text = (($out | ForEach-Object { "$_" }) -join "`n").Trim()
  }
}

function Exigir-Sucesso($Resultado, [string]$Mensagem) {
  if ($Resultado.Code -ne 0) {
    Falhar "$Mensagem`n$($Resultado.Text)"
  }
}

function Novo-Segredo([int]$Bytes = 32) {
  $buf = New-Object byte[] $Bytes
  $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
  try { $rng.GetBytes($buf) } finally { $rng.Dispose() }
  return ([Convert]::ToBase64String($buf).TrimEnd('=').Replace('+','-').Replace('/','_'))
}

function Encontrar-Node {
  $node = Get-ChildItem -Path $ToolRoot -Filter node.exe -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match 'node-v24\.19\.0-win-x64' } |
    Select-Object -First 1
  if (-not $node) { Falhar 'Node portátil anterior não foi encontrado. Este recovery NÃO reinstala nada.' }
  $env:Path = "$($node.DirectoryName);$env:Path"
  $r = Executar-Nativo $node.FullName @('--version')
  Exigir-Sucesso $r 'Node portátil existente não executa.'
  return $node.FullName
}

function Encontrar-Vercel {
  $bin = Join-Path $ToolRoot 'vercel-59.3.0\node_modules\.bin\vercel.cmd'
  if (-not (Test-Path $bin)) {
    $achado = Get-ChildItem -Path $ToolRoot -Filter vercel.cmd -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($achado) { $bin = $achado.FullName }
  }
  if (-not (Test-Path $bin)) { Falhar 'Vercel CLI portátil anterior não foi encontrada. Este recovery NÃO reinstala nada.' }
  $r = Executar-Nativo $bin @('--version')
  Exigir-Sucesso $r 'Vercel CLI existente não executa.'
  return $bin
}

function Encontrar-Gh {
  $system = Get-Command gh.exe -ErrorAction SilentlyContinue
  if ($system) {
    $r = Executar-Nativo $system.Source @('--version')
    if ($r.Code -eq 0) { return $system.Source }
  }
  $gh = Get-ChildItem -Path $ToolRoot -Filter gh.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $gh) { Falhar 'GitHub CLI anterior não foi encontrado. Este recovery NÃO reinstala nada.' }
  $r = Executar-Nativo $gh.FullName @('--version')
  Exigir-Sucesso $r 'GitHub CLI existente não executa.'
  return $gh.FullName
}

function Ler-Env([string]$Path, [string]$Nome) {
  if (-not (Test-Path $Path)) { return '' }
  $rx = '^' + [regex]::Escape($Nome) + '=(.*)$'
  $line = Get-Content $Path -ErrorAction Stop | Where-Object { $_ -match $rx } | Select-Object -Last 1
  if (-not $line) { return '' }
  $value = [regex]::Match($line,$rx).Groups[1].Value.Trim()
  if ($value.Length -ge 2 -and (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'")))) {
    $value = $value.Substring(1,$value.Length-2)
  }
  return $value
}

function Set-GitHubSecret([string]$Gh,[string]$Nome,[string]$Valor) {
  $r = Executar-NativoComEntrada $Gh @('secret','set',$Nome,'-R',$Repositorio) $Valor
  Exigir-Sucesso $r "Falha gravando GitHub Secret $Nome."
}

function Set-GitHubVariable([string]$Gh,[string]$Nome,[string]$Valor) {
  $r = Executar-NativoComEntrada $Gh @('variable','set',$Nome,'-R',$Repositorio) $Valor
  Exigir-Sucesso $r "Falha gravando GitHub Variable $Nome."
}

function Set-VercelEnv([string]$Vercel,[string]$ProjectId,[string]$Nome,[string]$Valor) {
  $null = Executar-Nativo $Vercel @('env','rm',$Nome,'production','--yes','--project',$ProjectId,'--scope',$VercelScope)
  $help = Executar-Nativo $Vercel @('env','add','--help')
  $args = @('env','add',$Nome,'production','--project',$ProjectId,'--scope',$VercelScope)
  if ($help.Text -match '(?m)--yes\b') { $args += '--yes' }
  if ($help.Text -match '(?m)--force\b') { $args += '--force' }
  if ($help.Text -match '(?m)--sensitive\b') { $args += '--sensitive' }
  $r = Executar-NativoComEntrada $Vercel $args $Valor
  Exigir-Sucesso $r "Falha configurando $Nome na Vercel."
}

function Post-Json([string]$Uri,[hashtable]$Body,[string]$Bearer='') {
  $headers = @{}
  if ($Bearer) { $headers.Authorization = "Bearer $Bearer" }
  Invoke-RestMethod -Uri $Uri -Method Post -Headers $headers -ContentType 'application/json' -Body ($Body | ConvertTo-Json -Depth 50 -Compress) -TimeoutSec 60
}

function Esperar-Checks([string]$Gh) {
  Etapa 'Checks da PR'
  for ($i=1; $i -le 60; $i++) {
    $r = Executar-Nativo $Gh @('pr','checks',"$PullRequest",'-R',$Repositorio,'--json','name,bucket')
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
  Falhar 'Checks não terminaram no limite. Nada foi mesclado.'
}

New-Item -ItemType Directory -Force -Path $CredDir,$WorkRoot | Out-Null

Etapa 'Reutilizando ferramentas existentes; nenhuma instalação'
$node = Encontrar-Node
$vercel = Encontrar-Vercel
$gh = Encontrar-Gh
Ok 'Node/Vercel/GitHub existentes validados.'

Etapa 'Autenticação existente'
$g = Executar-Nativo $gh @('auth','status')
if ($g.Code -ne 0) {
  Write-Host 'Confirme o login GitHub no navegador.' -ForegroundColor Yellow
  $g = Executar-Nativo $gh @('auth','login','--web','--git-protocol','https')
  Exigir-Sucesso $g 'Login GitHub falhou.'
}
$g = Executar-Nativo $gh @('repo','view',$Repositorio)
Exigir-Sucesso $g "Conta GitHub não acessa $Repositorio."

$v = Executar-Nativo $vercel @('whoami','--scope',$VercelScope)
if ($v.Code -ne 0) {
  Write-Host 'Confirme o login Vercel no navegador.' -ForegroundColor Yellow
  $v = Executar-Nativo $vercel @('login')
  Exigir-Sucesso $v 'Login Vercel falhou.'
}
$v = Executar-Nativo $vercel @('whoami','--scope',$VercelScope)
Exigir-Sucesso $v 'Vercel continua sem autenticação.'
Ok 'GitHub e Vercel autenticados.'

Etapa 'Pasta limpa do Reino Tribal'
$zip = Join-Path $WorkRoot 'source.zip'
Invoke-WebRequest -UseBasicParsing -Uri "https://codeload.github.com/$Repositorio/zip/refs/heads/$Branch" -OutFile $zip -TimeoutSec 180
Expand-Archive -Path $zip -DestinationPath $WorkRoot -Force
$work = Get-ChildItem $WorkRoot -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'vercel.json') } | Select-Object -First 1
if (-not $work) { Falhar 'Raiz do Reino Tribal não foi encontrada no ZIP.' }
Remove-Item (Join-Path $WorkRoot '.vercel') -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $work.FullName '.vercel') -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item Env:VERCEL_PROJECT_ID -ErrorAction SilentlyContinue
Remove-Item Env:VERCEL_ORG_ID -ErrorAction SilentlyContinue
Push-Location $work.FullName

try {
  Etapa "Projeto Vercel EXATO: $ProjetoVercel"
  $inspectByName = Executar-Nativo $vercel @('project','inspect',$ProjetoVercel,'--scope',$VercelScope)
  if ($inspectByName.Code -ne 0) {
    $add = Executar-Nativo $vercel @('project','add',$ProjetoVercel,'--scope',$VercelScope)
    Exigir-Sucesso $add 'Falha criando o projeto Vercel exclusivo.'
    $inspectByName = Executar-Nativo $vercel @('project','inspect',$ProjetoVercel,'--scope',$VercelScope)
  }
  Exigir-Sucesso $inspectByName 'Projeto reino-tribal-api não pôde ser inspecionado.'
  if ($inspectByName.Text -match $ForbiddenProjectPattern) { Falhar 'Vercel retornou referência de outro jogo. Abortado antes de qualquer deploy.' }

  $link = Executar-Nativo $vercel @('link','--yes','--project',$ProjetoVercel,'--scope',$VercelScope)
  Exigir-Sucesso $link 'Falha ligando a pasta limpa ao projeto reino-tribal-api.'
  $projectJsonPath = Join-Path $work.FullName '.vercel\project.json'
  if (-not (Test-Path $projectJsonPath)) { Falhar '.vercel/project.json não foi criado; abortado.' }
  $pj = Get-Content $projectJsonPath -Raw | ConvertFrom-Json
  $projectId = [string]$pj.projectId
  $orgId = [string]$pj.orgId
  if (-not $projectId.StartsWith('prj_')) { Falhar 'Project ID Vercel inválido.' }
  if ($orgId -ne $VercelTeamId) { Falhar "Team ID inesperado: $orgId" }

  $inspectById = Executar-Nativo $vercel @('project','inspect',$projectId,'--scope',$VercelScope)
  Exigir-Sucesso $inspectById 'Project ID recém-ligado não pôde ser inspecionado.'
  if ($inspectById.Text -match $ForbiddenProjectPattern) { Falhar 'Project ID aponta para Bacaworld/Bacathegas. Abortado.' }
  if ($inspectById.Text -notmatch [regex]::Escape($ProjetoVercel)) { Falhar "Project ID não confirmou o nome $ProjetoVercel. Abortado." }

  $env:VERCEL_PROJECT_ID = $projectId
  $env:VERCEL_ORG_ID = $orgId
  Ok "Isolamento confirmado: $ProjetoVercel / $projectId"

  Etapa 'Turso exclusivo'
  $envList = Executar-Nativo $vercel @('env','ls','production','--project',$projectId,'--scope',$VercelScope)
  $temTurso = ($envList.Text -match 'TURSO_DATABASE_URL') -and ($envList.Text -match 'TURSO_AUTH_TOKEN')
  if (-not $temTurso) {
    Write-Host 'Provisionando UM recurso Turso chamado reino-tribal-prod para este projeto exato.' -ForegroundColor Yellow
    $help = Executar-Nativo $vercel @('integration','add','tursocloud/database','--help')
    $args = @('integration','add','tursocloud/database','--name','reino-tribal-prod','--environment','production','--environment','preview','--project',$projectId,'--scope',$VercelScope)
    if ($help.Text -match '(?m)--yes\b') { $args += '--yes' }
    $addTurso = Executar-Nativo $vercel $args
    Exigir-Sucesso $addTurso 'Provisionamento Turso falhou. Não haverá segunda tentativa automática.'
  } else {
    Ok 'Turso já estava ligado ao projeto correto.'
  }

  $envList = Executar-Nativo $vercel @('env','ls','production','--project',$projectId,'--scope',$VercelScope)
  Exigir-Sucesso $envList 'Não consegui listar envs do projeto correto.'
  if ($envList.Text -notmatch 'TURSO_DATABASE_URL' -or $envList.Text -notmatch 'TURSO_AUTH_TOKEN') {
    Falhar 'A integração Turso terminou sem expor as duas variáveis esperadas no projeto correto.'
  }

  Etapa 'Obtendo envs do projeto correto'
  $envFile = Join-Path $WorkRoot 'production.env'
  Remove-Item $envFile -Force -ErrorAction SilentlyContinue
  $pull = Executar-Nativo $vercel @('env','pull',$envFile,'--environment','production','--yes','--project',$projectId,'--scope',$VercelScope)
  Exigir-Sucesso $pull 'vercel env pull falhou.'
  if (-not (Test-Path $envFile)) {
    Falhar "vercel env pull retornou sucesso, mas não criou $envFile.`nSAÍDA:`n$($pull.Text)"
  }
  if ((Get-Item $envFile).Length -le 0) {
    Falhar 'production.env foi criado vazio; abortado antes do deploy.'
  }
  $dbUrl = Ler-Env $envFile 'TURSO_DATABASE_URL'
  $dbToken = Ler-Env $envFile 'TURSO_AUTH_TOKEN'
  if (-not $dbUrl -or -not $dbToken) {
    Falhar 'production.env existe, mas não contém TURSO_DATABASE_URL/TURSO_AUTH_TOKEN.'
  }
  Ok 'Turso real lido do projeto correto.'

  $adminPassword = 'RT!' + (Novo-Segredo 30)
  $recoveryKey = Novo-Segredo 48

  Etapa 'Secrets somente do Reino Tribal'
  Set-VercelEnv $vercel $projectId 'RT_ADMIN_PASSWORD' $adminPassword
  Set-VercelEnv $vercel $projectId 'RT_ADMIN_RECOVERY_KEY' $recoveryKey
  Set-GitHubSecret $gh 'TURSO_DATABASE_URL' $dbUrl
  Set-GitHubSecret $gh 'TURSO_AUTH_TOKEN' $dbToken
  Set-GitHubSecret $gh 'RT_ADMIN_PASSWORD' $adminPassword
  Set-GitHubSecret $gh 'RT_ADMIN_RECOVERY_KEY' $recoveryKey
  Set-GitHubSecret $gh 'VERCEL_ORG_ID' $orgId
  Set-GitHubSecret $gh 'VERCEL_PROJECT_ID' $projectId
  Ok 'Secrets gravados.'

  Etapa 'Deploy de produção com bloqueio de projeto'
  $preDeploy = Executar-Nativo $vercel @('project','inspect',$projectId,'--scope',$VercelScope)
  Exigir-Sucesso $preDeploy 'Falha na validação imediatamente anterior ao deploy.'
  if ($preDeploy.Text -match $ForbiddenProjectPattern -or $preDeploy.Text -notmatch [regex]::Escape($ProjetoVercel)) {
    Falhar 'Bloqueio de segurança impediu deploy em projeto diferente do Reino Tribal.'
  }

  $deploy = Executar-Nativo $vercel @('deploy','--prod','--yes','--project',$projectId,'--scope',$VercelScope)
  Exigir-Sucesso $deploy 'Deploy de produção falhou.'
  if ($deploy.Text -match $ForbiddenProjectPattern) { Falhar 'Saída de deploy citou outro jogo. Abortado.' }
  $urls = [regex]::Matches($deploy.Text,'https://[A-Za-z0-9.-]+\.vercel\.app') |
    ForEach-Object { $_.Value.TrimEnd('/') } |
    Where-Object { $_ -match [regex]::Escape($ProjetoVercel) }
  $deployUrl = @($urls) | Select-Object -Last 1
  if (-not $deployUrl) { Falhar "Deploy terminou sem URL identificada do reino-tribal-api.`n$($deploy.Text)" }
  Ok "Backend correto: $deployUrl"

  Etapa 'Teste real Turso + conta + save/load + ADM'
  $health = $null
  for ($i=1; $i -le 20; $i++) {
    try {
      $health = Post-Json "$deployUrl/api/reino" @{ action='health' }
      if ($health.ok) { break }
    } catch {}
    Start-Sleep -Seconds 3
  }
  if (-not $health -or -not $health.ok) { Falhar 'Health da API/Turso não passou.' }

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
  $save = Post-Json "$deployUrl/api/reino" @{ action='save'; world_id=$worldId; state=@{ probe='reino-tribal-turso'; stamp=$stamp; ok=$true } } $playerToken
  if (-not $save.ok) { Falhar 'Save real falhou.' }
  $load = Post-Json "$deployUrl/api/reino" @{ action='load_save'; world_id=$worldId } $playerToken
  if (-not $load.state -or $load.state.probe -ne 'reino-tribal-turso') { Falhar 'Load real falhou.' }

  $adm = Post-Json "$deployUrl/api/reino" @{ action='login'; identifier='reinos_admin'; password=$adminPassword }
  if (-not $adm.access_token -or $adm.user.role -ne 'admin') { Falhar 'Login ADM real falhou.' }
  $adminToken = [string]$adm.access_token
  $status = Post-Json "$deployUrl/api/reino" @{ action='admin_status' } $adminToken
  if (-not $status.ok) { Falhar 'admin_status falhou.' }
  $dash = Post-Json "$deployUrl/api/admin" @{ action='dashboard' } $adminToken
  if (-not $dash) { Falhar 'Dashboard ADM falhou.' }
  Ok 'Health + registro + mundo + save/load + ADM passaram.'

  Etapa 'Ligando site público ao backend'
  Set-GitHubVariable $gh 'REINO_TRIBAL_API_BASE' $deployUrl

  Etapa 'PR: ready + checks + merge'
  $ready = Executar-Nativo $gh @('pr','ready',"$PullRequest",'-R',$Repositorio)
  Exigir-Sucesso $ready 'Não consegui marcar a PR como pronta.'
  Esperar-Checks $gh
  $merge = Executar-Nativo $gh @('pr','merge',"$PullRequest",'-R',$Repositorio,'--squash')
  Exigir-Sucesso $merge 'Merge falhou. Nada será repetido automaticamente.'
  Ok 'PR mesclada.'

  Etapa 'GitHub Pages'
  $run = Executar-Nativo $gh @('workflow','run','deploy-reino-tribal-pages.yml','-R',$Repositorio,'--ref','main')
  Exigir-Sucesso $run 'Falha disparando GitHub Pages.'
  Start-Sleep -Seconds 5
  $last = Executar-Nativo $gh @('run','list','-R',$Repositorio,'--workflow','deploy-reino-tribal-pages.yml','--branch','main','--limit','1','--json','databaseId,status,conclusion')
  Exigir-Sucesso $last 'Falha consultando deploy Pages.'
  $arr = @($last.Text | ConvertFrom-Json)
  if ($arr.Count -lt 1) { Falhar 'Workflow Pages não apareceu.' }
  $runId = [string]$arr[0].databaseId
  for ($i=1; $i -le 60; $i++) {
    $view = Executar-Nativo $gh @('run','view',$runId,'-R',$Repositorio,'--json','status,conclusion')
    if ($view.Code -eq 0 -and $view.Text) {
      $obj = $view.Text | ConvertFrom-Json
      if ($obj.status -eq 'completed') {
        if ($obj.conclusion -ne 'success') { Falhar "GitHub Pages terminou com $($obj.conclusion)." }
        break
      }
    }
    if ($i -eq 60) { Falhar 'GitHub Pages não terminou no limite.' }
    Start-Sleep -Seconds 10
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
  if (-not $public -or $public.StatusCode -ne 200 -or $public.Content -notmatch '1\.0\.4-turso') {
    Falhar 'Página pública não confirmou a versão Turso.'
  }

  $cred = @"
REINO TRIBAL - PRODUÇÃO
Data: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Usuário ADM: reinos_admin
Senha ADM: $adminPassword
Backend: $deployUrl
Jogo: $publicUrl
Projeto Vercel: $ProjetoVercel
Project ID: $projectId
Banco: reino-tribal-prod / Turso
"@
  Set-Content -Path $CredFile -Value $cred -Encoding UTF8
  Ok "Credenciais ADM: $CredFile"
  Ok "JOGO ONLINE: $publicUrl"
  Ok "BACKEND ONLINE: $deployUrl"

} finally {
  Pop-Location -ErrorAction SilentlyContinue
  Remove-Item $WorkRoot -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item Env:VERCEL_PROJECT_ID -ErrorAction SilentlyContinue
  Remove-Item Env:VERCEL_ORG_ID -ErrorAction SilentlyContinue
}
