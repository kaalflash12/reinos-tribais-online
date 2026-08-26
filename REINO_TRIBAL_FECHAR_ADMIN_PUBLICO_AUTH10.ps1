param(
  [switch]$PackageValidateOnly
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12

$Repo='kaalflash12/reinos-tribais-online'
$BundleCommit='975da8d0cfdc436080ce42462166e0c97fc4ed24'
$AuthFile='REINO_TRIBAL_ADMIN_FINAL_RT91_AUTH10.ps1'
$HelperRepoPath='tools/rt91_process_helpers.ps1'
$BrowserRepoPath='tools/rt90_admin_public_proof.mjs'
$Frontend='https://kaalflash12.github.io/reinos-tribais-online/'
$Api='https://reino-tribal-api.mestrederpg35.deno.net'
$CredDir=Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'ReinoTribal'
$CredFile=Join-Path $CredDir 'CREDENCIAIS_ADMIN_REINO_TRIBAL.txt'
$ProofDir=Join-Path $CredDir 'PROVA_ADMIN_PUBLICA_RT90'
$Tmp=Join-Path $env:TEMP ('reino-tribal-final-auth10-'+[Guid]::NewGuid().ToString('N'))
$AuthScript=Join-Path $Tmp $AuthFile
$HelperScript=Join-Path $Tmp 'rt91_process_helpers.ps1'
$BrowserTest=Join-Path $Tmp 'rt90_admin_public_proof.mjs'

function Pass([string]$Text){Write-Host ('PASS: '+$Text) -ForegroundColor Green}
function Fail([string]$Text){throw $Text}
function Download-Pinned([string]$RepoPath,[string]$Out){
  $url="https://raw.githubusercontent.com/$Repo/$BundleCommit/$RepoPath"
  $last=$null
  for($i=1;$i -le 4;$i++){
    try{
      Remove-Item -LiteralPath $Out -Force -ErrorAction SilentlyContinue
      Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $Out -TimeoutSec 120
      if((Test-Path -LiteralPath $Out) -and (Get-Item -LiteralPath $Out).Length -gt 0){return}
      $last='arquivo vazio'
    }catch{
      $last=$_.Exception.Message
    }
    Start-Sleep -Seconds 2
  }
  Fail ('Falha baixando bundle pinado: '+$RepoPath+' :: '+$last)
}
function Assert-Parser([string]$Path,[string]$Label){
  $tokens=$null;$errors=$null
  [Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tokens,[ref]$errors)|Out-Null
  if($errors.Count){$errors|Format-List|Out-String|Write-Host;Fail ($Label+' nao passou no parser PowerShell 5.1.')}
}

try{
  New-Item -ItemType Directory -Force -Path $Tmp,$CredDir,$ProofDir|Out-Null
  Write-Host '=== REINOS TRIBAIS - FECHAMENTO TOTAL AUTH10 + ADM + MOBILE ===' -ForegroundColor Cyan
  Write-Host ('BUNDLE WINDOWS-GREEN PINADO: '+$BundleCommit) -ForegroundColor DarkGray

  Download-Pinned $AuthFile $AuthScript
  Download-Pinned $HelperRepoPath $HelperScript
  Download-Pinned $BrowserRepoPath $BrowserTest

  Assert-Parser $AuthScript 'AUTH10 FINAL'
  Assert-Parser $HelperScript 'helper nativo RT91'
  . $HelperScript

  $authText=[IO.File]::ReadAllText($AuthScript)
  foreach($needle in @(
    "`$ExecutorRevision = 'SAFE-CLI-AUTH-10-FINAL'",
    "`$ExecutorContract = 'ADMIN_AUTHORITY_NO_SOURCE_DEPLOY_RT91'",
    "`$ExpectedBackend = 'https://reino-tribal-api.mestrederpg35.deno.net'",
    'DENO_ORG_AUTO_DISCOVERY_CONTRACT',
    'DENO_CANONICAL_APP_DOMAIN_MATCH_CONTRACT',
    'WINDOWS_POWERSHELL_START_PROCESS_STDERR_CONTRACT',
    "@('deploy','whoami')",
    "@('deploy','orgs','list')",
    "@('deploy','apps','get','--org',`$candidate,'--app',`$DenoApp,'--non-interactive')",
    "@('deploy','env','update-value','RT_ADMIN_PASSWORD',`$adminPassword,'--org',`$ResolvedDenoOrg,'--app',`$DenoApp,'--non-interactive')",
    "@('deploy','env','update-value','RT_ADMIN_RECOVERY_KEY',`$recoveryKey,'--org',`$ResolvedDenoOrg,'--app',`$DenoApp,'--non-interactive')",
    'REINO_TRIBAL_ADMIN_RT91_VALIDADO'
  )){if(-not $authText.Contains($needle)){Fail ('AUTH10 FINAL sem contrato esperado: '+$needle)}}
  if($authText.Contains("@('deploy','--org'")){Fail 'AUTH10 FINAL contem assinatura de source deploy antigo.'}
  foreach($forbidden in @('console.deno.com/auth/interactive','console.deno.com/auth/exchange')){
    if($authText.Contains($forbidden)){Fail ('AUTH10 FINAL contem auth HTTP manual proibida: '+$forbidden)}
  }

  $runnerText=[IO.File]::ReadAllText($BrowserTest)
  foreach($needle in @(
    'real admin session created by public UI',
    'real admin dashboard rendered',
    'temporary player registered in production',
    'temporary player joined Mundo 1',
    'mobile viewport 390x844',
    'mobile player login through public UI',
    'mobile production health Turso',
    'mobile player save routed to Turso',
    'mobile player load matches marker',
    'mobile zero legacy Supabase network',
    'RT90_MOBILE_PLAYER_TURSO_E2E.png',
    'setEdgeService'
  )){if(-not $runnerText.Contains($needle)){Fail ('Runner publico sem contrato: '+$needle)}}

  Pass 'AUTH10 + helper empacotados lado a lado e parseados'
  Pass 'bundle pinado no commit Windows-green'
  Pass 'runner Edge ADM + mobile pinado e validado'
  Pass 'ANTI_DOWNGRADE_NO_SOURCE_DEPLOY_CONTRACT'

  if($PackageValidateOnly){
    Write-Host 'RT91_AUTH10_FINAL_PACKAGE_WINDOWS_VALIDATE_PASS' -ForegroundColor Green
    return
  }

  $psExe=(Get-Command powershell.exe -ErrorAction Stop).Source
  Write-Host ''
  Write-Host '=== EXECUTANDO AUTH10 FINAL ===' -ForegroundColor Cyan
  $authCode=Invoke-RTProcessInteractive -FilePath $psExe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$AuthScript)
  if($authCode -ne 0){Fail ('AUTH10 FINAL terminou com exit code '+$authCode)}
  if(-not(Test-Path -LiteralPath $CredFile)){Fail ('Credencial final nao foi criada: '+$CredFile)}

  $cred=[IO.File]::ReadAllLines($CredFile)
  if(-not($cred -match '^Executor: RT91 / SAFE-CLI-AUTH-10-FINAL$')){Fail 'Credencial final nao confirma AUTH10 FINAL.'}
  if(-not($cred -match '^VALIDACAO: login \+ admin_status \+ dashboard = PASS$')){Fail 'Credencial final nao possui VALIDACAO PASS.'}
  if(-not($cred -match '^ANTI_DOWNGRADE: nenhum source deploy executado = PASS$')){Fail 'Credencial final nao possui prova anti-downgrade.'}
  if(-not($cred -match '^Contrato: ADMIN_AUTHORITY_NO_SOURCE_DEPLOY_RT91$')){Fail 'Credencial final nao confirma contrato RT91.'}
  $orgLine=@($cred|Where-Object{$_ -match '^Deno org resolvido:\s*'})|Select-Object -First 1
  if(-not $orgLine){Fail 'Credencial final nao registra org Deno resolvido automaticamente.'}
  $userLine=@($cred|Where-Object{$_ -match '^Usuario ADM:\s*'})|Select-Object -First 1
  $passLine=@($cred|Where-Object{$_ -match '^Senha ADM:\s*'})|Select-Object -First 1
  if(-not $userLine -or -not $passLine){Fail 'Credencial final sem usuario/senha.'}
  $username=($userLine -replace '^Usuario ADM:\s*','').Trim()
  $password=($passLine -replace '^Senha ADM:\s*','').Trim()
  if($username -ne 'reinos_admin' -or [string]::IsNullOrWhiteSpace($password)){Fail 'Credencial final invalida.'}
  Pass 'AUTH10 FINAL validou org/app + login + admin_status + dashboard sem imprimir senha'

  $Deno=Join-Path (Join-Path $env:LOCALAPPDATA 'ReinoTribalTools\deno-2.9.5') 'deno.exe'
  if(-not(Test-Path -LiteralPath $Deno)){
    $dc=Get-Command deno.exe -ErrorAction SilentlyContinue
    if($dc){$Deno=$dc.Source}else{Fail 'Deno 2.9.5 nao encontrado apos AUTH10.'}
  }
  $dv=Invoke-RTDenoText -DenoExe $Deno -CommandArgs @('--version')
  if($dv.Code -ne 0 -or $dv.Stdout -notmatch '^deno 2\.9\.5\b'){Fail ('Deno 2.9.5 nao confirmado para prova Edge. '+$dv.Stdout+' '+$dv.Stderr)}

  $env:RT_FINAL_ADMIN_PASSWORD=$password
  $env:RT_FINAL_FRONTEND=$Frontend
  $env:RT_FINAL_API=$Api
  $env:RT_FINAL_PROOF_DIR=$ProofDir
  try{
    Write-Host ''
    Write-Host '=== PROVA PUBLICA EDGE: ADM + MOBILE ===' -ForegroundColor Cyan
    $browser=Invoke-RTProcessCapture -FilePath $Deno -ArgumentList @('run','--allow-all',$BrowserTest)
    if($browser.Stdout){Write-Host $browser.Stdout}
    if($browser.Stderr){Write-Host $browser.Stderr -ForegroundColor DarkGray}
    if($browser.Code -ne 0){Fail ('Prova publica do navegador falhou com exit code '+$browser.Code)}
  }finally{
    $env:RT_FINAL_ADMIN_PASSWORD=''
    $env:RT_FINAL_FRONTEND=''
    $env:RT_FINAL_API=''
    $env:RT_FINAL_PROOF_DIR=''
    $password=$null
  }

  $proofFile=Join-Path $ProofDir 'PROVA_RT90_ADMIN_PUBLICO.json'
  if(-not(Test-Path -LiteralPath $proofFile)){Fail 'JSON da prova publica nao foi criado.'}
  $proof=Get-Content -LiteralPath $proofFile -Raw|ConvertFrom-Json
  if(-not $proof.pass){Fail ('Prova publica nao marcou PASS: '+($proof|ConvertTo-Json -Depth 20))}
  foreach($required in @(
    'public final Turso bridge',
    'public login UI visible',
    'real admin session created by public UI',
    'real admin dashboard rendered',
    'dashboard identifies reinos_admin',
    'admin overview exists',
    'authenticated admin_status from public browser',
    'zero legacy Supabase network',
    'public admin screenshot captured',
    'temporary player registered in production',
    'temporary player joined Mundo 1',
    'mobile viewport 390x844',
    'mobile Turso bridge active',
    'mobile public login UI visible',
    'mobile player login through public UI',
    'mobile production health Turso',
    'mobile player save routed to Turso',
    'mobile player load matches marker',
    'mobile zero legacy Supabase network',
    'mobile screenshot captured'
  )){if(-not @($proof.checks|Where-Object{$_.name -eq $required -and $_.pass}).Count){Fail ('Checkpoint ausente: '+$required)}}

  $adminShot=Join-Path $ProofDir 'RT90_ADMIN_DASHBOARD_PUBLICO.png'
  $mobileShot=Join-Path $ProofDir 'RT90_MOBILE_PLAYER_TURSO_E2E.png'
  if(-not(Test-Path -LiteralPath $adminShot)){Fail 'Screenshot ADM ausente.'}
  if(-not(Test-Path -LiteralPath $mobileShot)){Fail 'Screenshot mobile ausente.'}

  Pass 'login reinos_admin no GitHub Pages'
  Pass 'dashboard ADM publico real'
  Pass 'admin_status publico autenticado'
  Pass 'jogador mobile autenticado pela UI publica'
  Pass 'save/load mobile persistido no Turso'
  Pass 'zero trafego Supabase legado no ADM e mobile'
  Write-Host ''
  Write-Host 'REINO_TRIBAL_ADMIN_PUBLICO_RT90_PASS' -ForegroundColor Green
  Write-Host 'REINO_TRIBAL_MOBILE_PLAYER_TURSO_E2E_PASS' -ForegroundColor Green
  Write-Host 'ANTI_DOWNGRADE_NO_SOURCE_DEPLOY_PASS' -ForegroundColor Green
  Write-Host ('PROVA: '+$proofFile) -ForegroundColor Green
}finally{
  $env:RT_FINAL_ADMIN_PASSWORD=''
  Remove-Item -LiteralPath $Tmp -Recurse -Force -ErrorAction SilentlyContinue
}
