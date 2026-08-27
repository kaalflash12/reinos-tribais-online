param(
  [string]$DenoApp='reino-tribal-api',
  [string]$PreferredDenoOrg='mestrederpg35',
  [string]$DenoVersion='2.9.5',
  [string]$DenoExeOverride='',
  [switch]$DiscoveryTestOnly
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12

$ExecutorVersion='RT91'
$ExecutorRevision='SAFE-CLI-AUTH-FINAL-SELF-CONTAINED'
$ExecutorContract='ADMIN_AUTHORITY_NO_SOURCE_DEPLOY_RT91'
$ExpectedBackend='https://reino-tribal-api.mestrederpg35.deno.net'
$ExpectedHost='reino-tribal-api.mestrederpg35.deno.net'
$Frontend='https://kaalflash12.github.io/reinos-tribais-online/'
$ToolRoot=Join-Path $env:LOCALAPPDATA 'ReinoTribalTools'
$PortableDeno=Join-Path (Join-Path $ToolRoot ("deno-$DenoVersion")) 'deno.exe'
$DenoExe=if($DenoExeOverride){$DenoExeOverride}elseif(Test-Path $PortableDeno){$PortableDeno}else{$cmd=Get-Command deno.exe -ErrorAction SilentlyContinue;if($cmd){$cmd.Source}else{$PortableDeno}}
$CredDir=Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'ReinoTribal'
$CredFile=Join-Path $CredDir 'CREDENCIAIS_ADMIN_REINO_TRIBAL.txt'
$PendingCredFile=Join-Path $CredDir 'CREDENCIAIS_ADMIN_REINO_TRIBAL_PENDENTES.txt'
$ResolvedDenoOrg=''

function Etapa([string]$Texto){Write-Host "`n=== $Texto ===" -ForegroundColor Cyan}
function Ok([string]$Texto){Write-Host ('PASS: '+$Texto) -ForegroundColor Green}
function Falhar([string]$Texto){throw $Texto}

function Invoke-RTNative {
  param(
    [Parameter(Mandatory=$true)][string]$FilePath,
    [Parameter(Mandatory=$true)][string[]]$ArgumentList,
    [switch]$Interactive
  )
  if($Interactive){
    $p=Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -Wait -PassThru -NoNewWindow
    return [pscustomobject]@{Code=[int]$p.ExitCode;Stdout='';Stderr='';Text=''}
  }
  $id=[guid]::NewGuid().ToString('N')
  $root=if($env:TEMP){$env:TEMP}else{[IO.Path]::GetTempPath()}
  $out=Join-Path $root ('rt91-'+$id+'.out')
  $err=Join-Path $root ('rt91-'+$id+'.err')
  try{
    $p=Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -RedirectStandardOutput $out -RedirectStandardError $err -Wait -PassThru -NoNewWindow
    $stdout=if(Test-Path $out){[IO.File]::ReadAllText($out).Trim()}else{''}
    $stderr=if(Test-Path $err){[IO.File]::ReadAllText($err).Trim()}else{''}
    $text=(@($stdout,$stderr)|Where-Object{$_})-join [Environment]::NewLine
    return [pscustomobject]@{Code=[int]$p.ExitCode;Stdout=$stdout;Stderr=$stderr;Text=$text}
  }finally{
    Remove-Item $out,$err -Force -ErrorAction SilentlyContinue
  }
}

function Invoke-RTDenoText {
  param([string]$DenoExe,[string[]]$CommandArgs,[switch]$Interactive)
  return Invoke-RTNative -FilePath $DenoExe -ArgumentList $CommandArgs -Interactive:$Interactive
}

function Invoke-RTDenoJson {
  param([string]$DenoExe,[string[]]$CommandArgs)
  $args2=@($CommandArgs)
  if(-not($args2 -contains '--json')){$args2+= '--json'}
  $r=Invoke-RTNative -FilePath $DenoExe -ArgumentList $args2
  if($r.Code -ne 0){return [pscustomobject]@{Ok=$false;Code=$r.Code;Data=$null;Stdout=$r.Stdout;Stderr=$r.Stderr;Text=$r.Text}}
  if([string]::IsNullOrWhiteSpace($r.Stdout)){return [pscustomobject]@{Ok=$false;Code=0;Data=$null;Stdout='';Stderr=$r.Stderr;Text='Comando retornou stdout JSON vazio.'}}
  try{$data=$r.Stdout|ConvertFrom-Json}catch{return [pscustomobject]@{Ok=$false;Code=0;Data=$null;Stdout=$r.Stdout;Stderr=$r.Stderr;Text=('JSON invalido em stdout. '+$r.Stdout)}}
  return [pscustomobject]@{Ok=$true;Code=0;Data=$data;Stdout=$r.Stdout;Stderr=$r.Stderr;Text=$r.Text}
}

function Invoke-RTDenoInteractive {
  param([string]$DenoExe,[string[]]$CommandArgs)
  return Invoke-RTDenoText -DenoExe $DenoExe -CommandArgs $CommandArgs -Interactive
}

function Novo-Segredo([int]$Bytes=32){
  $buf=New-Object byte[] $Bytes
  $rng=[Security.Cryptography.RandomNumberGenerator]::Create()
  try{$rng.GetBytes($buf)}finally{$rng.Dispose()}
  return ([Convert]::ToBase64String($buf).TrimEnd('=').Replace('+','-').Replace('/','_'))
}

function Add-OrgCandidates {
  param([object]$Node,[System.Collections.Generic.HashSet[string]]$Set)
  if($null -eq $Node){return}
  if($Node -is [string] -or $Node -is [ValueType]){return}
  if($Node -is [System.Collections.IEnumerable] -and -not($Node -is [pscustomobject])){
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

function Test-CanonicalAppProbe {
  param([object]$Probe)
  if(-not $Probe.Ok){return $false}
  try{$serialized=$Probe.Data|ConvertTo-Json -Depth 40 -Compress}catch{return $false}
  return $serialized.Contains($ExpectedHost)
}

function Resolver-DenoOrgEApp {
  Etapa 'Autenticacao Deno e descoberta segura do app canonico'
  Remove-Item Env:DENO_DEPLOY_TOKEN -ErrorAction SilentlyContinue

  $who=Invoke-RTDenoJson -DenoExe $DenoExe -CommandArgs @('deploy','whoami')
  if(-not $who.Ok){
    Write-Host 'Sessao Deno ausente/expirada. Abrindo autorizacao oficial no navegador.' -ForegroundColor Yellow
    $null=Invoke-RTDenoInteractive -DenoExe $DenoExe -CommandArgs @('deploy','env','list','--org',$PreferredDenoOrg,'--app',$DenoApp)
    $who=Invoke-RTDenoJson -DenoExe $DenoExe -CommandArgs @('deploy','whoami')
  }
  if(-not $who.Ok){Falhar ('Deno whoami nao confirmou sessao autenticada. '+$who.Text)}

  $orgSet=New-Object 'System.Collections.Generic.HashSet[string]' -ArgumentList ([StringComparer]::OrdinalIgnoreCase)
  Add-OrgCandidates -Node $who.Data -Set $orgSet

  $orgs=Invoke-RTDenoJson -DenoExe $DenoExe -CommandArgs @('deploy','orgs','list')
  if($orgs.Ok){Add-OrgCandidates -Node $orgs.Data -Set $orgSet}
  if(-not [string]::IsNullOrWhiteSpace($PreferredDenoOrg)){[void]$orgSet.Add($PreferredDenoOrg)}
  if($orgSet.Count -eq 0){Falhar 'Conta Deno autenticada sem organizacoes detectaveis. Nenhum secret foi alterado.'}

  $resolved=''
  foreach($candidate in @($orgSet)){
    $probe=Invoke-RTDenoJson -DenoExe $DenoExe -CommandArgs @('deploy','apps','get','--org',$candidate,'--app',$DenoApp,'--non-interactive')
    if(Test-CanonicalAppProbe -Probe $probe){$resolved=$candidate;break}
    $list=Invoke-RTDenoJson -DenoExe $DenoExe -CommandArgs @('deploy','apps','list','--org',$candidate,'--non-interactive')
    if($list.Ok){
      $items=@($list.Data)
      foreach($item in $items){
        try{$j=$item|ConvertTo-Json -Depth 40 -Compress}catch{continue}
        if($j.Contains($DenoApp) -and $j.Contains($ExpectedHost)){$resolved=$candidate;break}
      }
      if($resolved){break}
    }
  }
  if([string]::IsNullOrWhiteSpace($resolved)){
    $visible=(@($orgSet)|Sort-Object)-join ', '
    Falhar ('AUTH DENO PASS, mas nenhum org acessivel contem o app canonico '+$ExpectedHost+'. Orgs visiveis: '+$visible+'. Nenhum secret foi alterado.')
  }

  $script:ResolvedDenoOrg=$resolved
  $envCheck=Invoke-RTDenoJson -DenoExe $DenoExe -CommandArgs @('deploy','env','list','--org',$resolved,'--app',$DenoApp,'--non-interactive')
  if(-not $envCheck.Ok){Falhar ('App canonico localizado em '+$resolved+', mas env list foi recusado. '+$envCheck.Text)}
  Ok ('DENO_ORG_AUTO_DISCOVERY_CONTRACT: '+$resolved)
  Ok 'DENO_CANONICAL_APP_DOMAIN_MATCH_CONTRACT'
  Ok 'WINDOWS_POWERSHELL_START_PROCESS_STDERR_CONTRACT'
}

function Invoke-HttpJson {
  param([string]$Url,[string]$Json,[string]$Bearer='',[int]$TimeoutMs=60000)
  try{
    $req=[Net.HttpWebRequest]::Create($Url)
    $req.Method='POST';$req.ContentType='application/json';$req.Accept='application/json'
    $req.Timeout=$TimeoutMs;$req.ReadWriteTimeout=$TimeoutMs
    if($Bearer){$req.Headers['Authorization']='Bearer '+$Bearer}
    $bytes=[Text.Encoding]::UTF8.GetBytes($Json);$req.ContentLength=$bytes.Length
    $s=$req.GetRequestStream();try{$s.Write($bytes,0,$bytes.Length)}finally{$s.Dispose()}
    try{$resp=$req.GetResponse()}catch[Net.WebException]{$resp=$_.Exception.Response;if($null -eq $resp){return [pscustomobject]@{Ok=$false;Status=0;Text=$_.Exception.Message}}}
    try{
      $status=[int]$resp.StatusCode
      $reader=New-Object IO.StreamReader($resp.GetResponseStream())
      try{$text=$reader.ReadToEnd()}finally{$reader.Dispose()}
      return [pscustomobject]@{Ok=($status -ge 200 -and $status -lt 300);Status=$status;Text=$text}
    }finally{$resp.Dispose()}
  }catch{return [pscustomobject]@{Ok=$false;Status=0;Text=$_.Exception.Message}}
}

function Parse-HttpJson($Result,[string]$Label){
  if(-not $Result.Ok){Falhar "$Label falhou HTTP $($Result.Status). $($Result.Text)"}
  try{return ($Result.Text|ConvertFrom-Json)}catch{Falhar "$Label retornou JSON invalido. $($Result.Text)"}
}

function Gravar-Pendente([string]$Password,[string]$Recovery,[string]$Status){
  New-Item -ItemType Directory -Force -Path $CredDir|Out-Null
  $txt=@(
    'REINO TRIBAL - CREDENCIAL ADMINISTRATIVA PENDENTE',
    ('Atualizado em: '+(Get-Date).ToString('yyyy-MM-dd HH:mm:ss')),
    ('Status: '+$Status),
    ('Executor: '+$ExecutorVersion+' / '+$ExecutorRevision),
    ('Contrato: '+$ExecutorContract),
    ('Deno org resolvido: '+$ResolvedDenoOrg),
    ('Backend: '+$ExpectedBackend),
    'Usuario ADM: reinos_admin',
    ('Senha ADM: '+$Password),
    ('Recovery Key: '+$Recovery),
    'ATENCAO: somente valido depois de login + admin_status + dashboard.'
  ) -join [Environment]::NewLine
  [IO.File]::WriteAllText($PendingCredFile,$txt,(New-Object Text.UTF8Encoding($true)))
}

Write-Host ''
Write-Host '=== REINO TRIBAL EXECUTOR FINAL RT91 ===' -ForegroundColor Cyan
Write-Host ('REVISAO: '+$ExecutorRevision) -ForegroundColor Green
Write-Host ('CONTRATO: '+$ExecutorContract) -ForegroundColor DarkGray

if(-not(Test-Path $DenoExe)){Falhar "Deno $DenoVersion nao encontrado: $DenoExe"}
$ver=Invoke-RTDenoText -DenoExe $DenoExe -CommandArgs @('--version')
if($ver.Code -ne 0 -or $ver.Stdout -notmatch "deno $([regex]::Escape($DenoVersion))"){Falhar ('Versao Deno inesperada. stdout='+$ver.Stdout+' stderr='+$ver.Stderr)}

Resolver-DenoOrgEApp

if($DiscoveryTestOnly){
  if($env:RT91_FAKE_DENO_SELFTEST -eq '1'){
    $testUpdate=Invoke-RTDenoText -DenoExe $DenoExe -CommandArgs @('deploy','env','update-value','RT_SELFTEST_ONLY','sentinel','--org',$ResolvedDenoOrg,'--app',$DenoApp,'--non-interactive')
    if($testUpdate.Code -ne 0){Falhar ('Selftest update-value falhou. '+$testUpdate.Text)}
    Ok 'DENO_UPDATE_VALUE_STDERR_SELFTEST_PASS'
  }
  Ok 'RT91_EXACT_EXECUTOR_DISCOVERY_TEST_PASS'
  return
}

Etapa 'Validando backend Turso antes de alterar secrets'
$health=Parse-HttpJson (Invoke-HttpJson -Url ($ExpectedBackend+'/api/reino') -Json '{"action":"health"}') 'health'
if(-not $health.ok -or $health.database -ne 'turso'){Falhar 'Health nao confirmou Turso. Nenhum secret foi alterado.'}
Ok 'Backend publico confirmou Turso.'

$adminPassword='RT!'+(Novo-Segredo 30)
$recoveryKey=Novo-Segredo 48
Gravar-Pendente -Password $adminPassword -Recovery $recoveryKey -Status 'GERADA_LOCALMENTE_ANTES_DO_DENO'

Etapa 'Atualizando somente RT_ADMIN_PASSWORD e RT_ADMIN_RECOVERY_KEY'
$up1=Invoke-RTDenoText -DenoExe $DenoExe -CommandArgs @('deploy','env','update-value','RT_ADMIN_PASSWORD',$adminPassword,'--org',$ResolvedDenoOrg,'--app',$DenoApp,'--non-interactive')
if($up1.Code -ne 0){Falhar ('RT_ADMIN_PASSWORD recusado. '+$up1.Text)}
Gravar-Pendente -Password $adminPassword -Recovery $recoveryKey -Status 'RT_ADMIN_PASSWORD_ATUALIZADO'
$up2=Invoke-RTDenoText -DenoExe $DenoExe -CommandArgs @('deploy','env','update-value','RT_ADMIN_RECOVERY_KEY',$recoveryKey,'--org',$ResolvedDenoOrg,'--app',$DenoApp,'--non-interactive')
if($up2.Code -ne 0){Falhar ('RT_ADMIN_RECOVERY_KEY recusado. '+$up2.Text)}
Gravar-Pendente -Password $adminPassword -Recovery $recoveryKey -Status 'DOIS_SECRETS_ATUALIZADOS_SEM_SOURCE_DEPLOY'
Ok 'ANTI_DOWNGRADE_NO_SOURCE_DEPLOY_CONTRACT'

Etapa 'Validando nova credencial ADM na producao'
$login=$null
for($i=1;$i -le 30;$i++){
  $body=@{action='login';identifier='reinos_admin';password=$adminPassword}|ConvertTo-Json -Compress
  $r=Invoke-HttpJson -Url ($ExpectedBackend+'/api/reino') -Json $body
  if($r.Ok){try{$candidate=$r.Text|ConvertFrom-Json}catch{$candidate=$null};if($candidate -and [string]$candidate.access_token){$login=$candidate;break}}
  Start-Sleep -Seconds 3
}
if(-not $login -or -not [string]$login.access_token){Falhar 'Nova credencial nao ficou ativa; arquivo PENDENTES foi preservado.'}
if([string]$login.user.username -ne 'reinos_admin'){Falhar 'Login retornou usuario diferente de reinos_admin.'}
$token=[string]$login.access_token
Ok 'Login reinos_admin passou.'

$status=Parse-HttpJson (Invoke-HttpJson -Url ($ExpectedBackend+'/api/reino') -Json '{"action":"admin_status"}' -Bearer $token) 'admin_status'
if(-not $status.ok){Falhar 'admin_status nao confirmou ok.'}
$dash=Parse-HttpJson (Invoke-HttpJson -Url ($ExpectedBackend+'/api/admin') -Json '{"action":"dashboard"}' -Bearer $token) 'dashboard'
if($null -eq $dash){Falhar 'dashboard nao retornou dados.'}

$cred=@(
  'REINO TRIBAL - CREDENCIAIS ADMINISTRATIVAS VALIDAS',
  ('Validado em: '+(Get-Date).ToString('yyyy-MM-dd HH:mm:ss')),
  ('Executor: '+$ExecutorVersion+' / '+$ExecutorRevision),
  ('Contrato: '+$ExecutorContract),
  ('Deno org resolvido: '+$ResolvedDenoOrg),
  ('Backend: '+$ExpectedBackend),
  ('Frontend: '+$Frontend),
  'Usuario ADM: reinos_admin',
  ('Senha ADM: '+$adminPassword),
  ('Recovery Key: '+$recoveryKey),
  'VALIDACAO: login + admin_status + dashboard = PASS',
  'ANTI_DOWNGRADE: nenhum source deploy executado = PASS'
) -join [Environment]::NewLine
New-Item -ItemType Directory -Force -Path $CredDir|Out-Null
[IO.File]::WriteAllText($CredFile,$cred,(New-Object Text.UTF8Encoding($true)))
Remove-Item $PendingCredFile -Force -ErrorAction SilentlyContinue
Ok ('Credenciais validas gravadas em: '+$CredFile)
Write-Host 'REINO_TRIBAL_ADMIN_RT91_VALIDADO' -ForegroundColor Green
Write-Host 'ANTI_DOWNGRADE_NO_SOURCE_DEPLOY_PASS' -ForegroundColor Green
