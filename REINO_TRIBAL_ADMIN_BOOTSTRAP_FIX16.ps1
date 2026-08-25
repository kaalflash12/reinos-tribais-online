param(
  [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$FixId = 'REINO_TRIBAL_ADMIN_FIX16'
$PinnedCommit = 'be58d6451fb556071e9cb0479a44b6fd51052fe4'
$PinnedFile = 'REINO_TRIBAL_ADMIN_FIX16_FINAL.ps1'
$RawUrl = "https://raw.githubusercontent.com/kaalflash12/reinos-tribais-online/$PinnedCommit/$PinnedFile"
$Curl = Get-Command curl.exe -ErrorAction Stop

Write-Host "`n=== $FixId BOOTSTRAP ===" -ForegroundColor Cyan
Write-Host "Commit pinado: $PinnedCommit" -ForegroundColor DarkGray

Get-ChildItem $env:TEMP -Filter 'RT_ADMIN_FIX*.ps1' -ErrorAction SilentlyContinue | ForEach-Object {
  Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
}
Get-ChildItem $env:TEMP -Filter 'REINO_TRIBAL_ADMIN_FIX*.ps1' -ErrorAction SilentlyContinue | ForEach-Object {
  Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
}

$dest = Join-Path $env:TEMP ("RT_ADMIN_FIX16_" + $PinnedCommit.Substring(0,12) + '_' + [Guid]::NewGuid().ToString('N') + '.ps1')

& $Curl.Source --fail --silent --show-error --location --http1.1 --tlsv1.2 --retry 5 --retry-all-errors --connect-timeout 20 --max-time 120 --output $dest $RawUrl
if ($LASTEXITCODE -ne 0) { throw "DOWNLOAD FIX16 FALHOU: curl exit $LASTEXITCODE" }
if (-not (Test-Path $dest) -or (Get-Item $dest).Length -lt 5000) { throw 'FIX16 baixado está ausente ou incompleto.' }

$text = [IO.File]::ReadAllText($dest)
foreach ($needle in @(
  "[string]`$BackendCommit = 'd5d1edadd9f33b612a233c4feed0e06ec97203bc'",
  '[switch]$PreflightOnly',
  '$preflightUrl = $preflightUri.AbsoluteUri',
  'CORS URL:',
  'REINO_TRIBAL_ADMIN_FIX16_VALIDADO'
)) {
  if (-not $text.Contains($needle)) { throw "ARQUIVO BAIXADO NÃO É O FIX16 VALIDADO. Marcador ausente: $needle" }
}

$tokens=$null; $errors=$null
[System.Management.Automation.Language.Parser]::ParseFile($dest,[ref]$tokens,[ref]$errors) | Out-Null
if ($errors.Count) { $errors | Format-List; throw 'FIX16 baixado não passou no parser PowerShell.' }

Write-Host "PASS: arquivo FIX16 validado" -ForegroundColor Green
Write-Host "EXECUTANDO EXATAMENTE: $dest" -ForegroundColor Yellow

if ($ValidateOnly) {
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $dest -PreflightOnly
  if ($LASTEXITCODE -ne 0) { throw "PreflightOnly FIX16 falhou: $LASTEXITCODE" }

  $deno = Get-Command deno.exe -ErrorAction SilentlyContinue
  if ($deno) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $dest -ValidateOnly -DenoExeOverride $deno.Source
    if ($LASTEXITCODE -ne 0) { throw "ValidateOnly FIX16 falhou: $LASTEXITCODE" }
  } else {
    Write-Host 'AVISO: deno.exe não está no PATH; ValidateOnly do backend foi ignorado neste bootstrap.' -ForegroundColor Yellow
  }
  Write-Host 'REINO_TRIBAL_ADMIN_BOOTSTRAP_FIX16_VALIDADO' -ForegroundColor Green
  exit 0
}

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $dest
if ($LASTEXITCODE -ne 0) { throw "FIX16 falhou com código $LASTEXITCODE" }
