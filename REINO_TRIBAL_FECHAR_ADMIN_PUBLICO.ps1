$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12

$Repo='kaalflash12/reinos-tribais-online'
$AuthCommit='d15be053212eed320d269a193e95eb3a0645f6da'
$AuthFile='REINO_TRIBAL_ADMIN_SAFE_RT91_CLI_AUTH6.ps1'
$BrowserCommit='da2076a2afe4fca85e3eba2f419ecdb417458894'
$Frontend='https://kaalflash12.github.io/reinos-tribais-online/'
$Api='https://reino-tribal-api.mestrederpg35.deno.net'
$CredDir=Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'ReinoTribal'
$CredFile=Join-Path $CredDir 'CREDENCIAIS_ADMIN_REINO_TRIBAL.txt'
$ProofDir=Join-Path $CredDir 'PROVA_ADMIN_PUBLICA_RT90'
$Tmp=Join-Path $env:TEMP ('reino-tribal-final-auth6-'+[Guid]::NewGuid().ToString('N'))
$AuthScript=Join-Path $Tmp $AuthFile
$BrowserTest=Join-Path $Tmp 'rt90_admin_public_proof.mjs'
$Curl=(Get-Command curl.exe -ErrorAction Stop).Source

function Pass([string]$x){Write-Host ('PASS: '+$x) -ForegroundColor Green}
function Fail([string]$x){throw $x}
function Download([string]$Url,[string]$Out){
  & $Curl --fail --silent --show-error --location --http1.1 --tlsv1.2 --retry 4 --retry-all-errors --connect-timeout 20 --max-time 120 --output $Out $Url
  if($LASTEXITCODE -ne 0 -or -not (Test-Path $Out) -or (Get-Item $Out).Length -eq 0){Fail ('Falha baixando '+$Url)}
}

try{
  New-Item -ItemType Directory -Force -Path $Tmp,$CredDir,$ProofDir | Out-Null
  Write-Host '=== REINOS TRIBAIS - FECHAMENTO TOTAL AUTH6 + ADM + MOBILE ===' -ForegroundColor Cyan
  Write-Host ('AUTH6 PINADO: '+$AuthCommit) -ForegroundColor DarkGray
  Write-Host ('BROWSER PINADO: '+$BrowserCommit) -ForegroundColor DarkGray

  Download "https://raw.githubusercontent.com/$Repo/$AuthCommit/$AuthFile" $AuthScript
  $tokens=$null;$errors=$null
  [Management.Automation.Language.Parser]::ParseFile($AuthScript,[ref]$tokens,[ref]$errors)|Out-Null
  if($errors.Count){$errors|Format-List|Out-String|Write-Host;Fail 'AUTH6 nao passou no parser PowerShell.'}
  $authText=[IO.File]::ReadAllText($AuthScript)
  foreach($needle in @(
    "`$ExecutorVersion = 'RT91'",
    "`$ExecutorRevision = 'SAFE-CLI-AUTH-6'",
    "`$ExecutorContract = 'ADMIN_AUTHORITY_NO_SOURCE_DEPLOY_RT91'",
    "`$ExpectedBackend = 'https://reino-tribal-api.mestrederpg35.deno.net'",
    '& $DenoExe deploy env list --org $DenoOrg --app $DenoApp',
    '& $DenoExe deploy env update-value RT_ADMIN_PASSWORD $adminPassword --org $DenoOrg --app $DenoApp',
    '& $DenoExe deploy env update-value RT_ADMIN_RECOVERY_KEY $recoveryKey --org $DenoOrg --app $DenoApp',
    'DENO_ALL_DEPLOY_DIRECT_ARGV_CONTRACT',
    'REINO_TRIBAL_ADMIN_RT91_VALIDADO'
  )){if(-not $authText.Contains($needle)){Fail ('AUTH6 sem contrato positivo esperado: '+$needle)}}
  Pass 'AUTH6 pinado, parseado e com todos os comandos deno deploy em argv direto'

  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $AuthScript
  if($LASTEXITCODE -ne 0){Fail ('AUTH6 terminou com exit code '+$LASTEXITCODE)}
  if(-not (Test-Path $CredFile)){Fail ('Credencial final nao foi criada: '+$CredFile)}

  $cred=[IO.File]::ReadAllLines($CredFile)
  if(-not ($cred -match '^Executor: RT91 / SAFE-CLI-AUTH-6$')){Fail 'Credencial final nao confirma SAFE-CLI-AUTH-6.'}
  if(-not ($cred -match '^VALIDACAO: login \+ admin_status \+ dashboard = PASS$')){Fail 'Credencial final nao possui VALIDACAO PASS.'}
  if(-not ($cred -match '^ANTI_DOWNGRADE: nenhum source deploy executado = PASS$')){Fail 'Credencial final nao possui prova anti-downgrade.'}
  if(-not ($cred -match '^Contrato: ADMIN_AUTHORITY_NO_SOURCE_DEPLOY_RT91$')){Fail 'Credencial final nao confirma contrato RT91.'}
  $userLine=@($cred|Where-Object{$_ -match '^Usuario ADM:\s*'})|Select-Object -First 1
  $passLine=@($cred|Where-Object{$_ -match '^Senha ADM:\s*'})|Select-Object -First 1
  if(-not $userLine -or -not $passLine){Fail 'Credencial final sem usuario/senha.'}
  $username=($userLine -replace '^Usuario ADM:\s*','').Trim()
  $password=($passLine -replace '^Senha ADM:\s*','').Trim()
  if($username -ne 'reinos_admin' -or [string]::IsNullOrWhiteSpace($password)){Fail 'Credencial final invalida.'}
  Pass 'AUTH6 validou login + admin_status + dashboard sem imprimir senha'

  $Deno=Join-Path (Join-Path $env:LOCALAPPDATA 'ReinoTribalTools\deno-2.9.5') 'deno.exe'
  if(-not (Test-Path $Deno)){$dc=Get-Command deno.exe -ErrorAction SilentlyContinue;if($dc){$Deno=$dc.Source}else{Fail 'Deno 2.9.5 nao encontrado apos AUTH6.'}}
  Download "https://raw.githubusercontent.com/$Repo/$BrowserCommit/tools/rt90_admin_public_proof.mjs" $BrowserTest
  $runnerText=[IO.File]::ReadAllText($BrowserTest)
  foreach($needle in @(
    'real admin session created by public UI',
    'real admin dashboard rendered',
    'temporary player registered in production',
    'temporary player joined Mundo 1',
    'mobile player login through public UI',
    'mobile player save routed to Turso',
    'mobile player load matches marker',
    'mobile zero legacy Supabase network',
    'RT90_MOBILE_PLAYER_TURSO_E2E.png',
    'setEdgeService'
  )){if(-not $runnerText.Contains($needle)){Fail ('Runner publico sem contrato: '+$needle)}}
  Pass 'runner Edge ADM + mobile pinado e validado'

  $env:RT_FINAL_ADMIN_PASSWORD=$password
  $env:RT_FINAL_FRONTEND=$Frontend
  $env:RT_FINAL_API=$Api
  $env:RT_FINAL_PROOF_DIR=$ProofDir
  try{
    & $Deno run --allow-all $BrowserTest
    if($LASTEXITCODE -ne 0){Fail ('Prova publica do navegador falhou com exit code '+$LASTEXITCODE)}
  }finally{
    $env:RT_FINAL_ADMIN_PASSWORD=''
    $env:RT_FINAL_FRONTEND=''
    $env:RT_FINAL_API=''
    $env:RT_FINAL_PROOF_DIR=''
    $password=$null
  }

  $proofFile=Join-Path $ProofDir 'PROVA_RT90_ADMIN_PUBLICO.json'
  if(-not (Test-Path $proofFile)){Fail 'JSON da prova publica nao foi criado.'}
  $proof=Get-Content $proofFile -Raw | ConvertFrom-Json
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
  if(-not (Test-Path $adminShot)){Fail 'Screenshot ADM ausente.'}
  if(-not (Test-Path $mobileShot)){Fail 'Screenshot mobile ausente.'}

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
  Remove-Item $Tmp -Recurse -Force -ErrorAction SilentlyContinue
}
