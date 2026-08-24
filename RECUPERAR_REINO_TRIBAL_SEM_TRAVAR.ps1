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
$WorkRoot = Join-Path $env:TEMP ('reino-tribal-safe-' + [Guid]::NewGuid().ToString('N'))
$CredDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'ReinoTribal'
$CredFile = Join-Path $CredDir 'CREDENCIAIS_ADMIN_REINO_TRIBAL.txt'
$ForbiddenProjectPattern = '(?i)\bbw-v151\b|bacathegas|bacaworld'

function Etapa([string]$Texto) { Write-Host "`n=== $Texto ===" -ForegroundColor Cyan }
function Ok([string]$Texto) { Write-Host "PASS: $Texto" -ForegroundColor Green }
function Aviso([string]$Texto) { Write-Host "AVISO: $Texto" -ForegroundColor Yellow }
function Falhar([string]$Texto) { throw $Texto }

function Quote-Arg([string]$Value) {
  if ($null -eq $Value) { return '""' }
  if ($Value -notmatch '[\s"]') { return $Value }
  return '"' + ($Value -replace '"','\"') + '"'
}

function Stop-Tree([int]$Pid) {
  try { & "$env:SystemRoot\System32\taskkill.exe" /PID $Pid /T /F *> $null } catch {}
}

function Executar-ComTimeout {
  param(
    [Parameter(Mandatory=$true)][string]$Exe,
    [string[]]$Args = @(),
    [int]$TimeoutSec = 60,
    [string]$Entrada = '',
    [switch]$Interativo,
    [string]$Rotulo = ''
  )

  $display = if ($Rotulo) { $Rotulo } else { (Split-Path $Exe -Leaf) + ' ' + (($Args | ForEach-Object { Quote-Arg $_ }) -join ' ') }
  Write-Host "EXECUTANDO [limite ${TimeoutSec}s]: $display" -ForegroundColor DarkCyan

  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $isCmd = $Exe -match '\.(cmd|bat)$'
  if ($isCmd) {
    $psi.FileName = $env:ComSpec
    $argText = ($Args | ForEach-Object { Quote-Arg $_ }) -join ' '
    $psi.Arguments = '/d /s /c ""' + $Exe + '" ' + $argText + '"'
  } else {
    $psi.FileName = $Exe
    $psi.Arguments = ($Args | ForEach-Object { Quote-Arg $_ }) -join ' '
  }
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $false

  if (-not $Interativo) {
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    if ($Entrada) { $psi.RedirectStandardInput = $true }
  }

  $p = New-Object System.Diagnostics.Process
  $p.StartInfo = $psi
  if (-not $p.Start()) { Falhar "Não consegui iniciar: $display" }

  $stdoutTask = $null
  $stderrTask = $null
  if (-not $Interativo) {
    $stdoutTask = $p.StandardOutput.ReadToEndAsync()
    $stderrTask = $p.StandardError.ReadToEndAsync()
    if ($Entrada) {
      $p.StandardInput.Write($Entrada)
      if (-not $Entrada.EndsWith("`n")) { $p.StandardInput.WriteLine() }
      $p.StandardInput.Close()
    }
  }

  $sw = [Diagnostics.Stopwatch]::StartNew()
  $nextBeat = 5
  while (-not $p.HasExited) {
    Start-Sleep -Milliseconds 250
    $sec = [int]$sw.Elapsed.TotalSeconds
    if ($sec -ge $nextBeat) {
      Write-Host "... ainda executando: $display (${sec}s/${TimeoutSec}s)" -ForegroundColor DarkGray
      $nextBeat += 5
    }
    if ($sw.Elapsed.TotalSeconds -ge $TimeoutSec) {
      Stop-Tree $p.Id
      Falhar "TIMEOUT após ${TimeoutSec}s: $display`nA etapa foi encerrada; não haverá repetição automática."
    }
  }

  $p.WaitForExit()
  $code = [int]$p.ExitCode
  $text = ''
  if (-not $Interativo) {
    $stdout = $stdoutTask.Result
    $stderr = $stderrTask.Result
    $text = (($stdout,$stderr | Where-Object { $_ }) -join "`n").Trim()
  }
  [pscustomobject]@{ Code=$code; Text=$text; Seconds=[math]::Round($sw.Elapsed.TotalSeconds,1) }
}

function Exigir-Sucesso($Resultado,[string]$Mensagem) {
  if ($Resultado.Code -ne 0) { Falhar "$Mensagem`n$($Resultado.Text)" }
}

function Novo-Segredo([int]$Bytes=32) {
  $buf = New-Object byte[] $Bytes
  $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
  try { $rng.GetBytes($buf) } finally { $rng.Dispose() }
  ([Convert]::ToBase64String($buf).TrimEnd('=').Replace('+','-').Replace('/','_'))
}

function Encontrar-Node {
  $n = Get-ChildItem -Path $ToolRoot -Filter node.exe -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.FullName -match 'node-v24\.19\.0-win-x64' } | Select-Object -First 1
  if (-not $n) { Falhar 'Node portátil anterior não encontrado. Este recovery NÃO instala nada.' }
  $env:Path = "$($n.DirectoryName);$env:Path"
  $r = Executar-ComTimeout $n.FullName @('--version') 15 -Rotulo 'validar Node existente'
  Exigir-Sucesso $r 'Node existente não executa.'
  $n.FullName
}

function Encontrar-Vercel {
  $bin = Join-Path $ToolRoot 'vercel-59.3.0\node_modules\.bin\vercel.cmd'
  if (-not (Test-Path $bin)) {
    $f = Get-ChildItem -Path $ToolRoot -Filter vercel.cmd -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($f) { $bin = $f.FullName }
  }
  if (-not (Test-Path $bin)) { Falhar 'Vercel CLI anterior não encontrada. Este recovery NÃO instala nada.' }
  $r = Executar-ComTimeout $bin @('--version') 20 -Rotulo 'validar Vercel CLI existente'
  Exigir-Sucesso $r 'Vercel CLI existente não executa.'
  $bin
}

function Encontrar-Gh {
  $system = Get-Command gh.exe -ErrorAction SilentlyContinue
  if ($system) {
    $r = Executar-ComTimeout $system.Source @('--version') 15 -Rotulo 'validar GitHub CLI existente'
    if ($r.Code -eq 0) { return $system.Source }
  }
  $f = Get-ChildItem -Path $ToolRoot -Filter gh.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $f) { Falhar 'GitHub CLI anterior não encontrado. Este recovery NÃO instala nada.' }
  $r = Executar-ComTimeout $f.FullName @('--version') 15 -Rotulo 'validar GitHub CLI portátil existente'
  Exigir-Sucesso $r 'GitHub CLI existente não executa.'
  $f.FullName
}

function Ler-Env([string]$Path,[string]$Nome) {
  if (-not (Test-Path $Path)) { return '' }
  $rx = '^' + [regex]::Escape($Nome) + '=(.*)$'
  $line = Get-Content $Path | Where-Object { $_ -match $rx } | Select-Object -Last 1
  if (-not $line) { return '' }
  $value = [regex]::Match($line,$rx).Groups[1].Value.Trim()
  if ($value.Length -ge 2 -and (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'")))) { $value=$value.Substring(1,$value.Length-2) }
  $value
}

function Set-GitHubSecret([string]$Gh,[string]$Nome,[string]$Valor) {
  $r = Executar-ComTimeout $Gh @('secret','set',$Nome,'-R',$Repositorio) 45 $Valor -Rotulo "GitHub secret $Nome"
  Exigir-Sucesso $r "Falha gravando GitHub Secret $Nome."
}
function Set-GitHubVariable([string]$Gh,[string]$Nome,[string]$Valor) {
  $r = Executar-ComTimeout $Gh @('variable','set',$Nome,'-R',$Repositorio) 45 $Valor -Rotulo "GitHub variable $Nome"
  Exigir-Sucesso $r "Falha gravando GitHub Variable $Nome."
}
function Set-VercelEnv([string]$Vercel,[string]$ProjectId,[string]$Nome,[string]$Valor) {
  $null = Executar-ComTimeout $Vercel @('env','rm',$Nome,'production','--yes','--project',$ProjectId,'--scope',$VercelScope) 45 -Rotulo "limpar env $Nome no projeto correto"
  $help = Executar-ComTimeout $Vercel @('env','add','--help') 20 -Rotulo 'ler ajuda env add'
  $args = @('env','add',$Nome,'production','--project',$ProjectId,'--scope',$VercelScope)
  if ($help.Text -match '(?m)--yes\b') { $args += '--yes' }
  if ($help.Text -match '(?m)--force\b') { $args += '--force' }
  if ($help.Text -match '(?m)--sensitive\b') { $args += '--sensitive' }
  $r = Executar-ComTimeout $Vercel $args 60 $Valor -Rotulo "gravar env $Nome no reino-tribal-api"
  Exigir-Sucesso $r "Falha configurando $Nome na Vercel."
}
function Post-Json([string]$Uri,[hashtable]$Body,[string]$Bearer='') {
  $headers=@{}; if($Bearer){$headers.Authorization="Bearer $Bearer"}
  Invoke-RestMethod -Uri $Uri -Method Post -Headers $headers -ContentType 'application/json' -Body ($Body|ConvertTo-Json -Depth 50 -Compress) -TimeoutSec 30
}

function Esperar-Checks([string]$Gh) {
  Etapa 'Checks da PR (com progresso)'
  for($i=1;$i -le 60;$i++) {
    Write-Host "checagem $i/60" -ForegroundColor DarkGray
    $r=Executar-ComTimeout $Gh @('pr','checks',"$PullRequest",'-R',$Repositorio,'--json','name,bucket') 30 -Rotulo 'consultar checks da PR'
    if($r.Code -eq 0 -and $r.Text){
      try{$checks=@($r.Text|ConvertFrom-Json)}catch{$checks=@()}
      if($checks.Count -gt 0){
        $falhas=@($checks|Where-Object{$_.bucket -in @('fail','cancel')}); if($falhas.Count){Falhar('Checks falharam: '+(($falhas.name)-join ', '))}
        $pend=@($checks|Where-Object{$_.bucket -eq 'pending'}); if($pend.Count -eq 0){Ok 'Checks concluídos sem falha.';return}
      }
    }
    Start-Sleep -Seconds 10
  }
  Falhar 'Checks não terminaram no limite; merge não executado.'
}

New-Item -ItemType Directory -Force -Path $CredDir,$WorkRoot | Out-Null

Etapa 'Reutilizando ferramentas existentes; nenhuma instalação'
$node=Encontrar-Node; $vercel=Encontrar-Vercel; $gh=Encontrar-Gh
Ok 'Ferramentas existentes validadas.'

Etapa 'Autenticação'
$g=Executar-ComTimeout $gh @('auth','status') 20 -Rotulo 'verificar login GitHub'
if($g.Code -ne 0){
  Write-Host 'Faça somente a confirmação de login do GitHub que aparecer.' -ForegroundColor Yellow
  $g=Executar-ComTimeout $gh @('auth','login','--web','--git-protocol','https') 300 -Interativo -Rotulo 'LOGIN GITHUB (máximo 5 min)'
  Exigir-Sucesso $g 'Login GitHub falhou.'
}
$g=Executar-ComTimeout $gh @('repo','view',$Repositorio) 30 -Rotulo 'validar acesso ao repositório'
Exigir-Sucesso $g 'GitHub autenticado não acessa o repositório.'

$v=Executar-ComTimeout $vercel @('whoami','--scope',$VercelScope) 30 -Rotulo 'verificar login Vercel'
if($v.Code -ne 0){
  Write-Host 'Faça somente a confirmação de login da Vercel que aparecer.' -ForegroundColor Yellow
  $v=Executar-ComTimeout $vercel @('login') 300 -Interativo -Rotulo 'LOGIN VERCEL (máximo 5 min)'
  Exigir-Sucesso $v 'Login Vercel falhou.'
}
$v=Executar-ComTimeout $vercel @('whoami','--scope',$VercelScope) 30 -Rotulo 'confirmar login Vercel'
Exigir-Sucesso $v 'Vercel continua sem autenticação.'
Ok 'Autenticação confirmada.'

Etapa 'Baixando branch limpa'
$zip=Join-Path $WorkRoot 'source.zip'
Invoke-WebRequest -UseBasicParsing -Uri "https://codeload.github.com/$Repositorio/zip/refs/heads/$Branch" -OutFile $zip -TimeoutSec 120
Expand-Archive -Path $zip -DestinationPath $WorkRoot -Force
$work=Get-ChildItem $WorkRoot -Directory|Where-Object{Test-Path(Join-Path $_.FullName 'vercel.json')}|Select-Object -First 1
if(-not $work){Falhar 'Raiz do Reino Tribal não encontrada.'}
Remove-Item (Join-Path $work.FullName '.vercel') -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item Env:VERCEL_PROJECT_ID,Env:VERCEL_ORG_ID -ErrorAction SilentlyContinue
Push-Location $work.FullName

try {
  Etapa 'Criando/validando SOMENTE reino-tribal-api'
  $inspect=Executar-ComTimeout $vercel @('project','inspect',$ProjetoVercel,'--scope',$VercelScope) 45 -Rotulo 'inspecionar reino-tribal-api'
  if($inspect.Code -ne 0){
    $add=Executar-ComTimeout $vercel @('project','add',$ProjetoVercel,'--scope',$VercelScope) 90 -Rotulo 'CRIAR projeto reino-tribal-api'
    Exigir-Sucesso $add 'Não consegui criar reino-tribal-api.'
  }
  $link=Executar-ComTimeout $vercel @('link','--yes','--project',$ProjetoVercel,'--scope',$VercelScope) 90 -Rotulo 'ligar pasta limpa a reino-tribal-api'
  Exigir-Sucesso $link 'Falha no link do projeto correto.'
  $pjPath=Join-Path $work.FullName '.vercel\project.json'
  if(-not(Test-Path $pjPath)){Falhar '.vercel/project.json não foi criado.'}
  $pj=Get-Content $pjPath -Raw|ConvertFrom-Json; $projectId=[string]$pj.projectId; $orgId=[string]$pj.orgId
  if(-not $projectId.StartsWith('prj_')){Falhar 'Project ID inválido.'}
  if($orgId -ne $VercelTeamId){Falhar "Team ID errado: $orgId"}
  $check=Executar-ComTimeout $vercel @('project','inspect',$projectId,'--scope',$VercelScope) 45 -Rotulo 'confirmar ID do reino-tribal-api'
  Exigir-Sucesso $check 'Project ID não pôde ser confirmado.'
  if($check.Text -match $ForbiddenProjectPattern -or $check.Text -notmatch [regex]::Escape($ProjetoVercel)){Falhar 'BLOQUEIO: projeto Vercel não é o Reino Tribal.'}
  $env:VERCEL_PROJECT_ID=$projectId; $env:VERCEL_ORG_ID=$orgId
  Ok "Isolamento confirmado: $ProjetoVercel / $projectId"

  Etapa 'Turso exclusivo'
  $envList=Executar-ComTimeout $vercel @('env','ls','production','--project',$projectId,'--scope',$VercelScope) 45 -Rotulo 'listar envs Turso'
  $temTurso=($envList.Text -match 'TURSO_DATABASE_URL') -and ($envList.Text -match 'TURSO_AUTH_TOKEN')
  if(-not $temTurso){
    $help=Executar-ComTimeout $vercel @('integration','add','tursocloud/database','--help') 30 -Rotulo 'ler opções da integração Turso'
    $args=@('integration','add','tursocloud/database','--name','reino-tribal-prod','--environment','production','--environment','preview','--project',$projectId,'--scope',$VercelScope)
    if($help.Text -match '(?m)--yes\b'){$args+='--yes'}
    Write-Host 'Se a Vercel/Turso pedir confirmação, confirme na tela. Esta etapa tem limite de 3 minutos.' -ForegroundColor Yellow
    $addT=Executar-ComTimeout $vercel $args 180 -Interativo -Rotulo 'PROVISIONAR Turso reino-tribal-prod'
    Exigir-Sucesso $addT 'Provisionamento Turso falhou.'
  } else { Ok 'Turso já está conectado ao projeto correto.' }

  $envList=Executar-ComTimeout $vercel @('env','ls','production','--project',$projectId,'--scope',$VercelScope) 45 -Rotulo 'confirmar envs Turso'
  Exigir-Sucesso $envList 'Falha listando envs após Turso.'
  if($envList.Text -notmatch 'TURSO_DATABASE_URL' -or $envList.Text -notmatch 'TURSO_AUTH_TOKEN'){Falhar 'Turso não expôs as duas variáveis esperadas.'}

  Etapa 'Lendo envs do projeto correto'
  $envFile=Join-Path $WorkRoot 'production.env'; Remove-Item $envFile -Force -ErrorAction SilentlyContinue
  $pull=Executar-ComTimeout $vercel @('env','pull',$envFile,'--environment','production','--yes','--project',$projectId,'--scope',$VercelScope) 60 -Rotulo 'vercel env pull production.env'
  Exigir-Sucesso $pull 'env pull falhou.'
  if(-not(Test-Path $envFile)){Falhar "env pull não criou production.env.`n$($pull.Text)"}
  if((Get-Item $envFile).Length -le 0){Falhar 'production.env vazio.'}
  $dbUrl=Ler-Env $envFile 'TURSO_DATABASE_URL'; $dbToken=Ler-Env $envFile 'TURSO_AUTH_TOKEN'
  if(-not $dbUrl -or -not $dbToken){Falhar 'production.env não contém as credenciais Turso.'}
  Ok 'Credenciais Turso obtidas do projeto correto.'

  $adminPassword='RT!'+(Novo-Segredo 30); $recoveryKey=Novo-Segredo 48
  Etapa 'Secrets do Reino Tribal'
  Set-VercelEnv $vercel $projectId 'RT_ADMIN_PASSWORD' $adminPassword
  Set-VercelEnv $vercel $projectId 'RT_ADMIN_RECOVERY_KEY' $recoveryKey
  Set-GitHubSecret $gh 'TURSO_DATABASE_URL' $dbUrl; Set-GitHubSecret $gh 'TURSO_AUTH_TOKEN' $dbToken
  Set-GitHubSecret $gh 'RT_ADMIN_PASSWORD' $adminPassword; Set-GitHubSecret $gh 'RT_ADMIN_RECOVERY_KEY' $recoveryKey
  Set-GitHubSecret $gh 'VERCEL_ORG_ID' $orgId; Set-GitHubSecret $gh 'VERCEL_PROJECT_ID' $projectId

  Etapa 'Deploy produção'
  $pre=Executar-ComTimeout $vercel @('project','inspect',$projectId,'--scope',$VercelScope) 30 -Rotulo 'último bloqueio antes do deploy'
  Exigir-Sucesso $pre 'Validação pré-deploy falhou.'
  if($pre.Text -match $ForbiddenProjectPattern -or $pre.Text -notmatch [regex]::Escape($ProjetoVercel)){Falhar 'BLOQUEIO: destino do deploy incorreto.'}
  $dep=Executar-ComTimeout $vercel @('deploy','--prod','--yes','--project',$projectId,'--scope',$VercelScope) 240 -Rotulo 'DEPLOY PRODUÇÃO reino-tribal-api'
  Exigir-Sucesso $dep 'Deploy falhou.'
  if($dep.Text -match $ForbiddenProjectPattern){Falhar 'Saída do deploy citou outro jogo.'}
  $urls=[regex]::Matches($dep.Text,'https://[A-Za-z0-9.-]+\.vercel\.app')|ForEach-Object{$_.Value.TrimEnd('/')}|Where-Object{$_ -match [regex]::Escape($ProjetoVercel)}
  $deployUrl=@($urls)|Select-Object -Last 1
  if(-not $deployUrl){Falhar "Deploy sem URL do reino-tribal-api.`n$($dep.Text)"}
  Ok "Backend: $deployUrl"

  Etapa 'Testes reais'
  $health=$null
  for($i=1;$i -le 12;$i++){Write-Host "health $i/12" -ForegroundColor DarkGray;try{$health=Post-Json "$deployUrl/api/reino" @{action='health'};if($health.ok){break}}catch{};Start-Sleep 3}
  if(-not $health -or -not $health.ok){Falhar 'Health Turso/API falhou.'}
  $stamp=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds(); $u="rtprobe_$stamp"; $email="$u@example.invalid"; $pass='Probe!'+(Novo-Segredo 24)
  $reg=Post-Json "$deployUrl/api/reino" @{action='register';email=$email;username=$u;password=$pass}; if(-not $reg.access_token){Falhar 'Registro falhou.'}; $pt=[string]$reg.access_token
  $wid='d5a546fb-316d-4332-ae92-1886d80b07df'; $join=Post-Json "$deployUrl/api/reino" @{action='join_world';world_id=$wid;player_name=$u} $pt; if(-not $join.ok){Falhar 'Join world falhou.'}
  $save=Post-Json "$deployUrl/api/reino" @{action='save';world_id=$wid;state=@{probe='reino-tribal-turso';stamp=$stamp}} $pt; if(-not $save.ok){Falhar 'Save falhou.'}
  $load=Post-Json "$deployUrl/api/reino" @{action='load_save';world_id=$wid} $pt; if(-not $load.state -or $load.state.probe -ne 'reino-tribal-turso'){Falhar 'Load falhou.'}
  $adm=Post-Json "$deployUrl/api/reino" @{action='login';identifier='reinos_admin';password=$adminPassword}; if(-not $adm.access_token -or $adm.user.role -ne 'admin'){Falhar 'Login ADM falhou.'}; $at=[string]$adm.access_token
  $status=Post-Json "$deployUrl/api/reino" @{action='admin_status'} $at; if(-not $status.ok){Falhar 'admin_status falhou.'}
  $dash=Post-Json "$deployUrl/api/admin" @{action='dashboard'} $at; if(-not $dash){Falhar 'Dashboard ADM falhou.'}
  Ok 'Health + registro + mundo + save/load + ADM passaram.'

  Set-GitHubVariable $gh 'REINO_TRIBAL_API_BASE' $deployUrl
  Etapa 'PR e merge'
  $ready=Executar-ComTimeout $gh @('pr','ready',"$PullRequest",'-R',$Repositorio) 45 -Rotulo 'marcar PR ready'; Exigir-Sucesso $ready 'PR ready falhou.'
  Esperar-Checks $gh
  $merge=Executar-ComTimeout $gh @('pr','merge',"$PullRequest",'-R',$Repositorio,'--squash') 90 -Rotulo 'merge PR Turso'; Exigir-Sucesso $merge 'Merge falhou.'

  Etapa 'GitHub Pages'
  $run=Executar-ComTimeout $gh @('workflow','run','deploy-reino-tribal-pages.yml','-R',$Repositorio,'--ref','main') 45 -Rotulo 'disparar Pages'; Exigir-Sucesso $run 'Falha disparando Pages.'
  Start-Sleep 5
  $last=Executar-ComTimeout $gh @('run','list','-R',$Repositorio,'--workflow','deploy-reino-tribal-pages.yml','--branch','main','--limit','1','--json','databaseId,status,conclusion') 45 -Rotulo 'obter run Pages'; Exigir-Sucesso $last 'Falha consultando Pages.'
  $arr=@($last.Text|ConvertFrom-Json); if($arr.Count -lt 1){Falhar 'Run Pages não apareceu.'}; $runId=[string]$arr[0].databaseId
  for($i=1;$i -le 60;$i++){Write-Host "Pages $i/60" -ForegroundColor DarkGray;$view=Executar-ComTimeout $gh @('run','view',$runId,'-R',$Repositorio,'--json','status,conclusion') 30 -Rotulo 'consultar Pages';if($view.Code -eq 0 -and $view.Text){$obj=$view.Text|ConvertFrom-Json;if($obj.status -eq 'completed'){if($obj.conclusion -ne 'success'){Falhar "Pages terminou $($obj.conclusion)."};break}};if($i -eq 60){Falhar 'Pages excedeu limite.'};Start-Sleep 10}
  $publicUrl='https://kaalflash12.github.io/reinos-tribais-online/'; $public=$null
  for($i=1;$i -le 12;$i++){Write-Host "site $i/12" -ForegroundColor DarkGray;try{$public=Invoke-WebRequest -UseBasicParsing -Uri $publicUrl -TimeoutSec 20;if($public.StatusCode -eq 200 -and $public.Content -match '1\.0\.4-turso'){break}}catch{};Start-Sleep 3}
  if(-not $public -or $public.StatusCode -ne 200 -or $public.Content -notmatch '1\.0\.4-turso'){Falhar 'Site público não confirmou Turso.'}
  $cred=@"
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
  Set-Content $CredFile $cred -Encoding UTF8
  Ok "Credenciais: $CredFile"; Ok "JOGO ONLINE: $publicUrl"; Ok "BACKEND ONLINE: $deployUrl"
} finally {
  Pop-Location -ErrorAction SilentlyContinue
  Remove-Item $WorkRoot -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item Env:VERCEL_PROJECT_ID,Env:VERCEL_ORG_ID -ErrorAction SilentlyContinue
}
