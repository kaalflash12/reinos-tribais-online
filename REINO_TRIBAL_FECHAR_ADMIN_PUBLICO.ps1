param([switch]$PackageValidateOnly)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12

$PinnedCommit='555c839859c628a34843635601c595a54158022d'
$Repo='kaalflash12/reinos-tribais-online'
$PinnedFile='REINO_TRIBAL_FECHAR_ADMIN_PUBLICO_AUTH10.ps1'
$Url="https://raw.githubusercontent.com/$Repo/$PinnedCommit/$PinnedFile"
$Tmp=Join-Path $env:TEMP ('reino-tribal-auth10-canonical-'+[Guid]::NewGuid().ToString('N')+'.ps1')

try {
  Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $Tmp
  if(-not (Test-Path $Tmp) -or (Get-Item $Tmp).Length -eq 0){throw 'Fechamento AUTH10 pinado nao foi baixado.'}

  $tokens=$null;$errors=$null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Tmp,[ref]$tokens,[ref]$errors)
  if($errors.Count){throw ('Fechamento AUTH10 pinado falhou no parser: '+(($errors|ForEach-Object{$_.Message}) -join ' | '))}

  $text=[IO.File]::ReadAllText($Tmp)
  foreach($needle in @(
    'BUNDLE WINDOWS+CDP GREEN PINADO',
    'PackageValidateOnly',
    'REINO_TRIBAL_ADMIN_PUBLICO_RT90_PASS',
    'REINO_TRIBAL_MOBILE_PLAYER_TURSO_E2E_PASS',
    'ANTI_DOWNGRADE_NO_SOURCE_DEPLOY_PASS'
  )){
    if(-not $text.Contains($needle)){throw ('AUTH10 pinado sem marcador esperado: '+$needle)}
  }

  Write-Host 'PASS: fechamento canonico AUTH10 pinado e parseado.' -ForegroundColor Green
  if($PackageValidateOnly){
    & $Tmp -PackageValidateOnly
  }else{
    & $Tmp
  }
  if(-not $?){throw 'Fechamento AUTH10 retornou falha.'}
} finally {
  Remove-Item $Tmp -Force -ErrorAction SilentlyContinue
}
