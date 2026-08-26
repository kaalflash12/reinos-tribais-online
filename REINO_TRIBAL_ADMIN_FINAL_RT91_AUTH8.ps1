param(
  [string]$Repositorio = 'kaalflash12/reinos-tribais-online',
  [string]$DenoApp = 'reino-tribal-api',
  [string]$PreferredDenoOrg = 'mestrederpg35',
  [string]$DenoVersion = '2.9.5',
  [string]$DenoExeOverride = '',
  [switch]$ValidateOnly,
  [switch]$PreflightOnly,
  [switch]$IdentityOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$ExecutorVersion = 'RT91'
$ExecutorRevision = 'SAFE-CLI-AUTH-8-FINAL'
$ExecutorContract = 'ADMIN_AUTHORITY_NO_SOURCE_DEPLOY_RT91'
$ExpectedBackend = 'https://reino-tribal-api.mestrederpg35.deno.net'
$ExpectedHost = 'reino-tribal-api.mestrederpg35.deno.net'
$Frontend = 'https://kaalflash12.github.io/reinos-tribais-online/'
$ToolRoot = Join-Path $env:LOCALAPPDATA 'ReinoTribalTools'
$PortableDeno = Join-Path (Join-Path $ToolRoot ("deno-$DenoVersion")) 'deno.exe'
$DenoExe = if($DenoExeOverride){$DenoExeOverride}elseif(Test-Path $PortableDeno){$PortableDeno}else{$cmd=Get-Command deno.exe -ErrorAction SilentlyContinue;if($cmd){$cmd.Source}else{$PortableDeno}}
$CurlCmd = Get-Command curl.exe -ErrorAction SilentlyContinue
$WorkRoot = Join-Path $env:TEMP ('reino-tribal-admin-final-auth8-' + [Guid]::NewGuid().ToString('N'))
$CredDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'ReinoTribal'
$CredFile = Join-Path $CredDir 'CREDENCIAIS_ADMIN_REINO_TRIBAL.txt'
$PendingCredFile = Join-Path $CredDir 'CREDENCIAIS_ADMIN_REINO_TRIBAL_PENDENTES.txt'
$ExecutionMarker = Join-Path $env:TEMP 'REINO_TRIBAL_EXECUTOR_ATIVO.txt'
$MainCommit = ''
$ResolvedDenoOrg = ''

function Etapa([string]$Texto){Write-Host "`n=== $Texto ===" -ForegroundColor Cyan}
function Ok([string]$Texto){Write-Host ('PASS: '+$Texto) -ForegroundColor Green}
function Falhar([string]$Texto){throw $Texto}

function Novo-Segredo([int]$Bytes=32){
  $buf=New-Object byte[] $Bytes
  $rng=[Security.Cryptography.RandomNumberGenerator]::Create()
  try{$rng.GetBytes($buf)}finally{$rng.Dispose()}
  return ([Convert]::ToBase64String($buf).TrimEnd('=').Replace('+','-').Replace('/','_'))
}

function Invoke-DenoJson {
  param([Parameter(Mandatory=$true)][string[]]$CommandArgs,[switch]$QuietErrors)
  $errFile=Join-Path $env:TEMP ('rt91-deno-'+[Guid]::NewGuid().ToString('N')+'.err')
  $oldEap=$ErrorActionPreference
  try{
    $ErrorActionPreference='Continue'
    $raw=@(& $DenoExe @CommandArgs --json 2>$errFile)
    $code=$LASTEXITCODE
    $stdout=(($raw|ForEach-Object{[string]$_}) -join [Environment]::NewLine).Trim()
    $stderr=if(Test-Path $errFile){[IO.File]::ReadAllText($errFile).Trim()}else{''}
    if($code -ne 0){return [pscustomobject]@{Ok=$false;Code=$code;Text=(($stdout+"`n"+$stderr).Trim());Data=$null}}
    if([string]::IsNullOrWhiteSpace($stdout)){return [pscustomobject]@{Ok=$false;Code=1;Text=('JSON vazio. stderr='+$stderr);Data=$null}}
    try{$data=$stdout|ConvertFrom-Json}catch{return [pscustomobject]@{Ok=$false;Code=1;Text=('JSON invalido: '+$stdout+' stderr='+$stderr);Data=$null}}
    return [pscustomobject]@{Ok=$true;Code=0;Text=$stdout;Data=$data;Stderr=$stderr}
  }finally{
    $ErrorActionPreference=$oldEap
    Remove-Item $errFile -Force -ErrorAction SilentlyContinue
  }
}

function Invoke-DenoInteractive {
  param([Parameter(Mandatory=$true)][string[]]$CommandArgs)
  $oldEap=$ErrorActionPreference
  try{
    $ErrorActionPreference='Continue'
    & $DenoExe @CommandArgs 2>&1 | ForEach-Object { Write-Host ([string]$_) }
    return [int]$LASTEXITCODE
  }finally{$ErrorActionPreference=$oldEap}
}

function Invoke-DenoText {
  param([Parameter(Mandatory=$true)][string[]]$CommandArgs,[string]$WorkingDirectory='')
  $oldEap=$ErrorActionPreference
  $oldLocation=$null
  try{
    $ErrorActionPreference='Continue'
    if($WorkingDirectory){$oldLocation=Get-Location;Set-Location $WorkingDirectory}
    $raw=@(& $DenoExe @CommandArgs 2>&1)
    $code=$LASTEXITCODE
    return [pscustomobject]@{Code=[int]$code;Text=(($raw|ForEach-Object{[string]$_}) -join [Environment]::NewLine).Trim()}
  }finally{
    if($oldLocation){Set-Location $oldLocation}
    $ErrorActionPreference=$oldEap
  }
}

function Add-OrgCandidates {
  param([object]$Node,[System.Collections.Generic.HashSet[string]]$Set)
  if($null -eq $Node){return}
  if($Node -is [string] -or $Node -is [ValueType]){return}
  if($Node -is [System.Collections.IEnumerable] -and -not ($Node -is [pscustomobject])){
    foreach($item in $Node){Add-OrgCandidates -Node $item -Set $Set}
    return
  }
  foreach($prop in $Node.PSObject.Properties){
    if(($prop.Name -eq 'slug' -or $prop.Name -eq 'name') -and $prop.Value -is [string]){
      $v=([string]$prop.Value).Trim()
      if($v -match '^[A-Za-z0-9][A-Za-z0-9._-]{1,127}$'){[void]$Set.Add($v)}
    }
    Add-OrgCandidates -Node $prop.Value -Set $Set
  }
}

function Resolver-DenoOrgEApp {
  Etapa 'Autenticacao Deno e descoberta automatica do app canonico'
  Remove-Item Env:DENO_DEPLOY_TOKEN -ErrorAction SilentlyContinue

  $orgs=Invoke-DenoJson -CommandArgs @('deploy','orgs','list') -QuietErrors
  if(-not $orgs.Ok){
    Write-Host 'Sessao Deno ausente/expirada. Abrindo autorizacao oficial no navegador.' -ForegroundColor Yellow
    $loginCode=Invoke-DenoInteractive -CommandArgs @('deploy','orgs','list')
    if($loginCode -ne 0){Falhar "Autenticacao Deno terminou com codigo $loginCode."}
    $orgs=Invoke-DenoJson -CommandArgs @('deploy','orgs','list') -QuietErrors
  }
  if(-not $orgs.Ok){Falhar ('Nao foi possivel listar orgs da conta Deno autenticada. '+$orgs.Text)}

  $who=Invoke-DenoJson -CommandArgs @('deploy','whoami') -QuietErrors
  if(-not $who.Ok){Falhar ('Deno whoami falhou. '+$who.Text)}

  $orgSet=New-Object 'System.Collections.Generic.HashSet[string]' -ArgumentList ([StringComparer]::OrdinalIgnoreCase)
  if(-not [string]::IsNullOrWhiteSpace($PreferredDenoOrg)){[void]$orgSet.Add($PreferredDenoOrg)}
  Add-OrgCandidates -Node $orgs.Data -Set $orgSet
  Add-OrgCandidates -Node $who.Data -Set $orgSet
  if($orgSet.Count -eq 0){Falhar 'A conta Deno autenticada nao retornou nenhuma organizacao acessivel.'}

  $resolved=''
  foreach($candidate in @($orgSet)){
    $probe=Invoke-DenoJson -CommandArgs @('deploy','apps','get','--org',$candidate,'--app',$DenoApp,'--non-interactive') -QuietErrors
    if($probe.Ok){
      $serialized=$probe.Data|ConvertTo-Json -Depth 40 -Compress
      if($serialized.Contains($ExpectedHost)){$resolved=$candidate;break}
    }
  }
  if([string]::IsNullOrWhiteSpace($resolved)){
    foreach($candidate in @($orgSet)){
      $apps=Invoke-DenoJson -CommandArgs @('deploy','apps','list','--org',$candidate,'--limit','100','--non-interactive') -QuietErrors
      if($apps.Ok){
        $serialized=$apps.Data|ConvertTo-Json -Depth 40 -Compress
        if($serialized.Contains($ExpectedHost)){$resolved=$candidate;break}
      }
    }
  }
  if([string]::IsNullOrWhiteSpace($resolved)){
    $visible=(@($orgSet)|Sort-Object) -join ', '
    Falhar ('AUTH DENO PASS, mas nenhum org acessivel contem o app/dominio canonico '+$ExpectedBackend+'. Orgs visiveis: '+$visible+'. Nenhum secret foi alterado.')
  }

  $script:ResolvedDenoOrg=$resolved
  $envCheck=Invoke-DenoJson -CommandArgs @('deploy','env','list','--org',$resolved,'--app',$DenoApp,'--non-interactive') -QuietErrors
  if(-not $envCheck.Ok){Falhar ('App localizado no org '+$resolved+', mas env list foi recusado. '+$envCheck.Text)}
  Ok ('DENO_ORG_AUTO_DISCOVERY_CONTRACT: '+$resolved)
  Ok 'DENO_CANONICAL_APP_DOMAIN_MATCH_CONTRACT'
  Ok 'DENO_DOCUMENTED_CLI_ONLY_CONTRACT'
  Ok 'WINDOWS_POWERSHELL_NATIVE_STDERR_SAFE_CONTRACT'
}

function Curl-Json {
  param([string]$Url,[string]$Json,[string]$Bearer='',[int]$Attempts=4)
  $id=[Guid]::NewGuid().ToString('N')
  $req=Join-Path $env:TEMP ("rt91-$id-request.json")
  $resp=Join-Path $env:TEMP ("rt91-$id-response.json")
  [IO.File]::WriteAllText($req,$Json,(New-Object Text.UTF8Encoding($false)))
  try{
    $last=''
    for($i=1;$i -le $Attempts;$i++){
      Remove-Item $resp -Force -ErrorAction SilentlyContinue
      $a=@('--silent','--show-error','--location','--http1.1','--tlsv1.2','--connect-timeout','20','--max-time','60','-H','Content-Type: application/json','-H','Accept: application/json')
      if($Bearer){$a+=@('-H',('Authorization: Bearer '+$Bearer))}
      $a+=@('--data-binary',('@'+$req),'--output',$resp,'--write-out','%{http_code}',$Url)
      $oldEap=$ErrorActionPreference
      try{$ErrorActionPreference='Continue';$http=((& $CurlCmd.Source @a 2>&1)|Out-String).Trim();$code=$LASTEXITCODE}finally{$ErrorActionPreference=$oldEap}
      $body=if(Test-Path $resp){[IO.File]::ReadAllText($resp)}else{''}
      $status=0;if($http -match '^[0-9]{3}$'){$status=[int]$http}
      if($code -eq 0 -and $status -gt 0){return [pscustomobject]@{Ok=($status -ge 200 -and $status -lt 300);Status=$status;Text=$body}}
      $last="curl exit=$code; http=$status; body=$body"
      if($i -lt $Attempts){Start-Sleep -Seconds ([Math]::Min(6,$i*2))}
    }
    return [pscustomobject]@{Ok=$false;Status=0;Text=$last}
  }finally{Remove-Item $req,$resp -Force -ErrorAction SilentlyContinue}
}

function Parse-JsonResult($Resultado,[string]$Rotulo){
  if(-not $Resultado.Ok){Falhar "$Rotulo falhou HTTP $($Resultado.Status). $($Resultado.Text)"}
  try{return ($Resultado.Text|ConvertFrom-Json)}catch{Falhar "$Rotulo retornou JSON invalido. $($Resultado.Text)"}
}

function Get-GitHubJson([string]$Url){
  $out=Join-Path $env:TEMP ('rt91-gh-'+[Guid]::NewGuid().ToString('N')+'.json')
  try{
    $oldEap=$ErrorActionPreference
    try{$ErrorActionPreference='Continue';& $CurlCmd.Source --fail --silent --show-error --location --http1.1 --tlsv1.2 --retry 4 --retry-all-errors --connect-timeout 20 --max-time 90 -H 'Accept: application/vnd.github+json' -H 'User-Agent: ReinoTribal-RT91' --output $out $Url 2>&1|Out-Null;$code=$LASTEXITCODE}finally{$ErrorActionPreference=$oldEap}
    if($code -ne 0){Falhar 'Falha consultando GitHub.'}
    return ([IO.File]::ReadAllText($out)|ConvertFrom-Json)
  }finally{Remove-Item $out -Force -ErrorAction SilentlyContinue}
}

function Baixar-E-Validar-MainAtual([string]$Destino){
  $meta=Get-GitHubJson "https://api.github.com/repos/$Repositorio/commits/main"
  $script:MainCommit=[string]$meta.sha
  if($script:MainCommit -notmatch '^[0-9a-f]{40}$'){Falhar 'Nao foi possivel fixar o SHA atual do main.'}
  foreach($relative in @('deno.json','package.json','deno/main.js','api/reino.js','api/admin.js','api/realtime.js','backend/turso/schema.sql')){
    $dest=Join-Path $Destino ($relative -replace '/','\')
    New-Item -ItemType Directory -Force -Path (Split-Path $dest -Parent)|Out-Null
    $url="https://raw.githubusercontent.com/$Repositorio/$script:MainCommit/$relative"
    $oldEap=$ErrorActionPreference
    try{$ErrorActionPreference='Continue';& $CurlCmd.Source --fail --silent --show-error --location --http1.1 --tlsv1.2 --retry 4 --retry-all-errors --connect-timeout 20 --max-time 120 --output $dest $url 2>&1|Out-Null;$code=$LASTEXITCODE}finally{$ErrorActionPreference=$oldEap}
    if($code -ne 0){Falhar "Falha baixando main atual: $relative"}
  }
  $denoMain=[IO.File]::ReadAllText((Join-Path $Destino 'deno\main.js'))
  foreach($needle in @("import realtimeHandler from '../api/realtime.js';","pathname === '/ws'","pathname === '/api/realtime/ws'")){if(-not $denoMain.Contains($needle)){Falhar "ANTI-DOWNGRADE: main atual sem realtime: $needle"}}
  $reino=[IO.File]::ReadAllText((Join-Path $Destino 'api\reino.js'))
  foreach($needle in @('const passwordMatches = verifyPassword(password, existing.password_hash);',"role='admin',disabled=0",'DELETE FROM rt_sessions WHERE user_id=?','normalizeUsername(identifier) === ADMIN_USERNAME) await ensureAdmin();')){if(-not $reino.Contains($needle)){Falhar "main atual sem contrato ADM: $needle"}}
  $check=Invoke-DenoText -CommandArgs @('check','deno/main.js') -WorkingDirectory $Destino
  if($check.Code -ne 0){Falhar ('Backend atual nao passou no deno check. '+$check.Text)}
  Ok ('ANTI-DOWNGRADE main atual validado: '+$script:MainCommit)
}

function Testar-Preflight {
  $headers=Join-Path $env:TEMP ('rt91-cors-'+[Guid]::NewGuid().ToString('N')+'.txt')
  try{
    $oldEap=$ErrorActionPreference
    try{$ErrorActionPreference='Continue';$http=((& $CurlCmd.Source --silent --show-error --http1.1 --tlsv1.2 --connect-timeout 20 --max-time 30 -X OPTIONS -D $headers -o NUL -H 'Origin: https://kaalflash12.github.io' -H 'Access-Control-Request-Method: POST' -H 'Access-Control-Request-Headers: content-type,authorization' --write-out '%{http_code}' ($ExpectedBackend+'/api/reino') 2>&1)|Out-String).Trim();$code=$LASTEXITCODE}finally{$ErrorActionPreference=$oldEap}
    if($code -ne 0 -or $http -ne '204'){Falhar "CORS preflight nao retornou 204. http=$http"}
    $h=if(Test-Path $headers){[IO.File]::ReadAllText($headers)}else{''}
    if($h -notmatch '(?im)^access-control-allow-origin:\s*https://kaalflash12\.github\.io\s*$'){Falhar ('CORS nao autorizou origem GitHub Pages. '+$h)}
    Ok 'CORS_GITHUB_PAGES_EXACT_ORIGIN_CONTRACT'
  }finally{Remove-Item $headers -Force -ErrorAction SilentlyContinue}
}

function Gravar-Checkpoint([string]$Password,[string]$Recovery,[string]$Status){
  New-Item -ItemType Directory -Force -Path $CredDir|Out-Null
  $txt=@(
    'REINO TRIBAL - CHECKPOINT DE CREDENCIAL ADMINISTRATIVA',
    ('Atualizado em: '+(Get-Date).ToString('yyyy-MM-dd HH:mm:ss')),
    ('Status: '+$Status),
    ('Executor: '+$ExecutorVersion+' / '+$ExecutorRevision),
    ('Contrato: '+$ExecutorContract),
    ('Deno org resolvido: '+$ResolvedDenoOrg),
    ('Backend source validado: '+$script:MainCommit),
    ('Backend: '+$ExpectedBackend),
    'Usuario ADM: reinos_admin',
    ('Senha ADM: '+$Password),
    ('Recovery Key: '+$Recovery),
    'ATENCAO: arquivo pendente; so e valido depois de login + admin_status + dashboard.'
  ) -join [Environment]::NewLine
  [IO.File]::WriteAllText($PendingCredFile,$txt,(New-Object Text.UTF8Encoding($true)))
}

Write-Host ''
Write-Host '=== REINO TRIBAL EXECUTOR FINAL RT91 AUTH8 ===' -ForegroundColor Cyan
Write-Host ('VERSAO: '+$ExecutorVersion) -ForegroundColor Green
Write-Host ('REVISAO: '+$ExecutorRevision) -ForegroundColor Green
Write-Host ('CONTRATO: '+$ExecutorContract) -ForegroundColor DarkGray
Write-Host ('BACKEND: '+$ExpectedBackend) -ForegroundColor DarkGray
[IO.File]::WriteAllText($ExecutionMarker,(@('version='+$ExecutorVersion,'revision='+$ExecutorRevision,'contract='+$ExecutorContract,'backend='+$ExpectedBackend,'started_utc='+[DateTime]::UtcNow.ToString('o')) -join [Environment]::NewLine),(New-Object Text.UTF8Encoding($false)))
if($IdentityOnly){Ok 'REINO_TRIBAL_RT91_IDENTITY_PASS';return}
if(-not $CurlCmd){Falhar 'curl.exe nao encontrado no Windows.'}
if(-not(Test-Path $DenoExe)){Falhar "Deno $DenoVersion nao encontrado em $DenoExe"}
$ver=Invoke-DenoText -CommandArgs @('--version')
if($ver.Code -ne 0 -or $ver.Text -notmatch "deno $([regex]::Escape($DenoVersion))"){Falhar ('Versao Deno inesperada. '+$ver.Text)}

try{
  New-Item -ItemType Directory -Force -Path $WorkRoot|Out-Null
  Baixar-E-Validar-MainAtual -Destino $WorkRoot
  if($PreflightOnly){Testar-Preflight;Ok 'RT91_PREFLIGHT_PUBLICO_PASS';return}
  if($ValidateOnly){Testar-Preflight;Ok 'RT91_VALIDATE_NO_DEPLOY_PASS';return}

  Resolver-DenoOrgEApp

  Etapa 'Validando producao antes de alterar secrets'
  $healthBefore=Parse-JsonResult (Curl-Json -Url ($ExpectedBackend+'/api/reino') -Json '{"action":"health"}' -Attempts 3) 'health pre-change'
  if(-not $healthBefore.ok -or $healthBefore.database -ne 'turso'){Falhar 'Health pre-change nao confirmou Turso.'}
  Testar-Preflight

  $adminPassword='RT!'+(Novo-Segredo 30)
  $recoveryKey=Novo-Segredo 48
  Gravar-Checkpoint -Password $adminPassword -Recovery $recoveryKey -Status 'GERADA_LOCALMENTE_ANTES_DO_DENO'

  Etapa 'Atualizando somente secrets ADM; nenhum source deploy sera executado'
  $up1=Invoke-DenoJson -CommandArgs @('deploy','env','update-value','RT_ADMIN_PASSWORD',$adminPassword,'--org',$ResolvedDenoOrg,'--app',$DenoApp,'--non-interactive') -QuietErrors
  if(-not $up1.Ok){Falhar ('Deno recusou RT_ADMIN_PASSWORD. '+$up1.Text)}
  Gravar-Checkpoint -Password $adminPassword -Recovery $recoveryKey -Status 'SENHA_DENO_ATUALIZADA_SEM_SOURCE_DEPLOY'
  $up2=Invoke-DenoJson -CommandArgs @('deploy','env','update-value','RT_ADMIN_RECOVERY_KEY',$recoveryKey,'--org',$ResolvedDenoOrg,'--app',$DenoApp,'--non-interactive') -QuietErrors
  if(-not $up2.Ok){Falhar ('Deno recusou RT_ADMIN_RECOVERY_KEY. '+$up2.Text)}
  Gravar-Checkpoint -Password $adminPassword -Recovery $recoveryKey -Status 'SECRETS_DENO_ATUALIZADOS_SEM_SOURCE_DEPLOY'
  Ok 'DENO_ALL_DEPLOY_DIRECT_ARGV_CONTRACT'
  Ok 'ANTI_DOWNGRADE_NO_SOURCE_DEPLOY_CONTRACT'

  Etapa 'Validacao publica e login ADM real'
  $login=$null
  for($i=1;$i -le 30;$i++){
    $loginJson=@{action='login';identifier='reinos_admin';password=$adminPassword}|ConvertTo-Json -Compress
    $lr=Curl-Json -Url ($ExpectedBackend+'/api/reino') -Json $loginJson -Attempts 1
    if($lr.Ok){try{$candidate=$lr.Text|ConvertFrom-Json}catch{$candidate=$null};if($candidate -and [string]$candidate.access_token){$login=$candidate;break}}
    Start-Sleep -Seconds 3
  }
  if(-not $login -or -not [string]$login.access_token){Falhar 'Nova credencial nao ficou ativa; arquivo PENDENTES foi preservado.'}
  if([string]$login.user.username -ne 'reinos_admin'){Falhar 'Login retornou usuario incorreto.'}
  $adminToken=[string]$login.access_token
  Ok 'Login reinos_admin passou com a nova senha.'

  $status=Parse-JsonResult (Curl-Json -Url ($ExpectedBackend+'/api/reino') -Json '{"action":"admin_status"}' -Bearer $adminToken -Attempts 3) 'admin_status'
  if(-not $status.ok){Falhar 'admin_status nao confirmou ok.'}
  $dash=Parse-JsonResult (Curl-Json -Url ($ExpectedBackend+'/api/admin') -Json '{"action":"dashboard"}' -Bearer $adminToken -Attempts 3) 'dashboard ADM'
  if($null -eq $dash){Falhar 'Dashboard ADM nao retornou dados.'}
  Testar-Preflight

  New-Item -ItemType Directory -Force -Path $CredDir|Out-Null
  $cred=@(
    'REINO TRIBAL - CREDENCIAIS ADMINISTRATIVAS VALIDAS',
    ('Validado em: '+(Get-Date).ToString('yyyy-MM-dd HH:mm:ss')),
    ('Executor: '+$ExecutorVersion+' / '+$ExecutorRevision),
    ('Contrato: '+$ExecutorContract),
    ('Deno org resolvido: '+$ResolvedDenoOrg),
    ('Backend source validado: '+$script:MainCommit),
    ('Backend: '+$ExpectedBackend),
    ('Frontend: '+$Frontend),
    'Usuario ADM: reinos_admin',
    ('Senha ADM: '+$adminPassword),
    ('Recovery Key: '+$recoveryKey),
    'VALIDACAO: login + admin_status + dashboard = PASS',
    'ANTI_DOWNGRADE: nenhum source deploy executado = PASS'
  ) -join [Environment]::NewLine
  [IO.File]::WriteAllText($CredFile,$cred,(New-Object Text.UTF8Encoding($true)))
  Remove-Item $PendingCredFile -Force -ErrorAction SilentlyContinue
  Ok ('Credenciais validas gravadas em: '+$CredFile)
  Write-Host ''
  Write-Host 'REINO_TRIBAL_ADMIN_RT91_VALIDADO' -ForegroundColor Green
  Write-Host 'ANTI_DOWNGRADE_NO_SOURCE_DEPLOY_PASS' -ForegroundColor Green
}catch{
  if(Test-Path $PendingCredFile){Write-Host '';Write-Host 'CREDENCIAL PRESERVADA APOS A FALHA:' -ForegroundColor Yellow;Write-Host $PendingCredFile -ForegroundColor Yellow}
  throw
}finally{
  Remove-Item Env:DENO_DEPLOY_TOKEN -ErrorAction SilentlyContinue
  Remove-Item $WorkRoot -Recurse -Force -ErrorAction SilentlyContinue
}
