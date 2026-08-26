$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12

$Repo='kaalflash12/reinos-tribais-online'
$Frontend='https://kaalflash12.github.io/reinos-tribais-online/'
$Api='https://reino-tribal-api.mestrederpg35.deno.net'
$CredDir=Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'ReinoTribal'
$CredFile=Join-Path $CredDir 'CREDENCIAIS_ADMIN_REINO_TRIBAL.txt'
$ProofDir=Join-Path $CredDir 'PROVA_ADMIN_PUBLICA_RT90'
$Tmp=Join-Path $env:TEMP ('reino-tribal-final-admin-'+[Guid]::NewGuid().ToString('N'))
$Launcher=Join-Path $Tmp 'REINO_TRIBAL_CONTINUAR.ps1'
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
  Write-Host '=== REINOS TRIBAIS - FECHAMENTO ADM PUBLICO RT90/RT91 ===' -ForegroundColor Cyan

  Download "https://raw.githubusercontent.com/$Repo/main/REINO_TRIBAL_CONTINUAR.ps1" $Launcher
  $parsed=$null;$errs=$null
  [Management.Automation.Language.Parser]::ParseFile($Launcher,[ref]$parsed,[ref]$errs)|Out-Null
  if($errs.Count){Fail ('Launcher canonico possui erro de parser: '+($errs|Out-String))}
  $launcherText=[IO.File]::ReadAllText($Launcher)
  foreach($needle in @("`$CanonicalVersion = 'RT91'","`$CanonicalContract = 'ADMIN_AUTHORITY_NO_SOURCE_DEPLOY_RT91'",'ANTI_DOWNGRADE_NO_SOURCE_DEPLOY_CONTRACT')){
    if(-not $launcherText.Contains($needle)){Fail ('Launcher não cumpre RT91 seguro: '+$needle)}
  }
  Pass 'launcher RT91 SAFE baixado, parseado e protegido contra downgrade'

  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Launcher
  if($LASTEXITCODE -ne 0){Fail ('RT91 terminou com exit code '+$LASTEXITCODE)}
  if(-not (Test-Path $CredFile)){Fail ('Credencial final não foi criada: '+$CredFile)}

  $cred=[IO.File]::ReadAllLines($CredFile)
  if(-not ($cred -match '^VALIDACAO: login \+ admin_status \+ dashboard = PASS$')){Fail 'Arquivo de credencial não possui VALIDACAO final PASS.'}
  if(-not ($cred -match '^ANTI_DOWNGRADE: nenhum source deploy executado = PASS$')){Fail 'Arquivo de credencial não possui prova anti-downgrade RT91.'}
  if(-not ($cred -match '^Contrato: ADMIN_AUTHORITY_NO_SOURCE_DEPLOY_RT91$')){Fail 'Arquivo de credencial não confirma contrato RT91.'}
  $userLine=@($cred|Where-Object{$_ -match '^Usuario ADM:\s*'})|Select-Object -First 1
  $passLine=@($cred|Where-Object{$_ -match '^Senha ADM:\s*'})|Select-Object -First 1
  if(-not $userLine -or -not $passLine){Fail 'Arquivo final não contém usuário/senha no formato esperado.'}
  $username=($userLine -replace '^Usuario ADM:\s*','').Trim()
  $password=($passLine -replace '^Senha ADM:\s*','').Trim()
  if($username -ne 'reinos_admin' -or [string]::IsNullOrWhiteSpace($password)){Fail 'Credencial final inválida.'}
  Pass 'credencial RT91 validada localmente sem imprimir senha'
  Pass 'ANTI_DOWNGRADE: nenhum source deploy executado'

  $Deno=Join-Path (Join-Path $env:LOCALAPPDATA 'ReinoTribalTools\deno-2.9.5') 'deno.exe'
  if(-not (Test-Path $Deno)){$dc=Get-Command deno.exe -ErrorAction SilentlyContinue;if($dc){$Deno=$dc.Source}else{Fail 'Deno 2.9.5 não encontrado após RT91.'}}
  Download "https://raw.githubusercontent.com/$Repo/main/tools/rt90_admin_public_proof.mjs" $BrowserTest
  Pass 'runner de navegador público baixado'

  $env:RT_FINAL_ADMIN_PASSWORD=$password
  $env:RT_FINAL_FRONTEND=$Frontend
  $env:RT_FINAL_API=$Api
  $env:RT_FINAL_PROOF_DIR=$ProofDir
  try{
    & $Deno run --allow-all $BrowserTest
    if($LASTEXITCODE -ne 0){Fail ('Prova pública do navegador falhou com exit code '+$LASTEXITCODE)}
  }finally{
    $env:RT_FINAL_ADMIN_PASSWORD=''
    $env:RT_FINAL_FRONTEND=''
    $env:RT_FINAL_API=''
    $env:RT_FINAL_PROOF_DIR=''
    $password=$null
  }

  $proofFile=Join-Path $ProofDir 'PROVA_RT90_ADMIN_PUBLICO.json'
  if(-not (Test-Path $proofFile)){Fail 'JSON da prova pública não foi criado.'}
  $proof=Get-Content $proofFile -Raw | ConvertFrom-Json
  if(-not $proof.pass){Fail ('Prova pública não marcou PASS: '+($proof|ConvertTo-Json -Depth 20))}
  foreach($required in @(
    'public final Turso bridge',
    'public login UI visible',
    'real admin session created by public UI',
    'real admin dashboard rendered',
    'dashboard identifies reinos_admin',
    'admin overview exists',
    'authenticated admin_status from public browser',
    'zero legacy Supabase network',
    'public admin screenshot captured'
  )){
    if(-not @($proof.checks|Where-Object{$_.name -eq $required -and $_.pass}).Count){Fail ('Checkpoint ausente: '+$required)}
  }
  Pass 'login reinos_admin no GitHub Pages'
  Pass 'dashboard ADM público real'
  Pass 'admin_status público autenticado'
  Pass 'zero tráfego Supabase legado'
  Pass ('screenshot: '+(Join-Path $ProofDir 'RT90_ADMIN_DASHBOARD_PUBLICO.png'))
  Write-Host ''
  Write-Host 'REINO_TRIBAL_ADMIN_PUBLICO_RT90_PASS' -ForegroundColor Green
  Write-Host 'ANTI_DOWNGRADE_NO_SOURCE_DEPLOY_PASS' -ForegroundColor Green
  Write-Host ('PROVA: '+$proofFile) -ForegroundColor Green
}finally{
  $env:RT_FINAL_ADMIN_PASSWORD=''
  Remove-Item $Tmp -Recurse -Force -ErrorAction SilentlyContinue
}
