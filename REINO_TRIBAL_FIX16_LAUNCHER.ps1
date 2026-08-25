param(
  [switch]$PreflightOnly,
  [switch]$ValidateOnly,
  [string]$DenoExeOverride = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$ExpectedCommit = 'be58d6451fb556071e9cb0479a44b6fd51052fe4'
$ExpectedFile = 'REINO_TRIBAL_ADMIN_FIX16_FINAL.ps1'
$ExpectedBlobMarker = 'REINO_TRIBAL_ADMIN_FIX16_VALIDADO'
$ExpectedPreflightMarker = '$preflightUrl = $preflightUri.AbsoluteUri'
$ExpectedBackendCommit = "[string]`$BackendCommit = 'd5d1edadd9f33b612a233c4feed0e06ec97203bc'"
$Target = Join-Path $env:TEMP ('RT_ADMIN_FIX16_' + $ExpectedCommit.Substring(0,12) + '.ps1')
$Url = "https://raw.githubusercontent.com/kaalflash12/reinos-tribais-online/$ExpectedCommit/$ExpectedFile"

function Fail([string]$Message) { throw $Message }

Write-Host "`n=== REINO TRIBAL FIX16 LAUNCHER ===" -ForegroundColor Cyan
Write-Host "Executor commit: $ExpectedCommit" -ForegroundColor DarkGray
Write-Host "Destino unico: $Target" -ForegroundColor DarkGray

# Elimina nomes antigos que causaram reexecucao acidental no Windows.
foreach($old in @(
  (Join-Path $env:TEMP 'RT_ADMIN_FIX15.ps1'),
  (Join-Path $env:TEMP 'RT_ADMIN_FIX16.ps1'),
  (Join-Path $env:TEMP 'REINO_TRIBAL_ADMIN_FIX15_FINAL.ps1'),
  (Join-Path $env:TEMP 'REINO_TRIBAL_ADMIN_FIX16_FINAL.ps1')
)) {
  Remove-Item $old -Force -ErrorAction SilentlyContinue
}
Remove-Item $Target -Force -ErrorAction SilentlyContinue

$curl = Get-Command curl.exe -ErrorAction SilentlyContinue
if(-not $curl){ Fail 'curl.exe nao encontrado no Windows.' }

& $curl.Source --fail --silent --show-error --location --http1.1 --tlsv1.2 --retry 5 --retry-all-errors --connect-timeout 20 --max-time 120 --output $Target $Url
if($LASTEXITCODE -ne 0){ Fail "Download do FIX16 falhou com codigo $LASTEXITCODE." }
if(-not (Test-Path $Target) -or (Get-Item $Target).Length -lt 5000){ Fail 'FIX16 baixado esta ausente ou incompleto.' }

$text = [IO.File]::ReadAllText($Target)
foreach($marker in @(
  '[switch]$PreflightOnly',
  $ExpectedBlobMarker,
  $ExpectedPreflightMarker,
  $ExpectedBackendCommit,
  'CORS URL:'
)) {
  if(-not $text.Contains($marker)){ Fail "Arquivo baixado nao e o FIX16 esperado. Marcador ausente: $marker" }
}
if($text.Contains('RT_ADMIN_FIX15.ps1')){ Fail 'Executor baixado referencia launcher FIX15 legado.' }

$tokens=$null;$errors=$null
[System.Management.Automation.Language.Parser]::ParseFile($Target,[ref]$tokens,[ref]$errors)|Out-Null
if($errors.Count){ $errors | Format-List; Fail 'FIX16 baixado nao passou no parser PowerShell.' }

Write-Host 'PASS: FIX16 correto baixado, identificado e parseado.' -ForegroundColor Green
Write-Host "EXECUTANDO EXATAMENTE: $Target" -ForegroundColor Yellow

$args = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$Target)
if($PreflightOnly){ $args += '-PreflightOnly' }
if($ValidateOnly){
  $args += '-ValidateOnly'
  if($DenoExeOverride){ $args += @('-DenoExeOverride',$DenoExeOverride) }
}

$p = Start-Process -FilePath powershell.exe -ArgumentList $args -Wait -PassThru -NoNewWindow
if($p.ExitCode -ne 0){ Fail "FIX16 terminou com codigo $($p.ExitCode). Arquivo executado: $Target" }

Write-Host 'PASS: launcher executou somente o FIX16 pinado.' -ForegroundColor Green
