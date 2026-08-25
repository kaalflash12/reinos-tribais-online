param(
  [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$FixId = 'REINO_TRIBAL_ADMIN_FIX17'
$PinnedCommit = '4ebd425d7fb54880b29fe463623c2834314c21f6'
$PinnedFile = 'REINO_TRIBAL_ADMIN_FIX17_FINAL.ps1'
$RawUrl = "https://raw.githubusercontent.com/kaalflash12/reinos-tribais-online/$PinnedCommit/$PinnedFile"
$Curl = Get-Command curl.exe -ErrorAction Stop

Write-Host "`n=== REINO TRIBAL ADMIN BOOTSTRAP CANONICO ===" -ForegroundColor Cyan
Write-Host "Executor: $FixId" -ForegroundColor Cyan
Write-Host "Commit pinado: $PinnedCommit" -ForegroundColor DarkGray

Get-ChildItem $env:TEMP -Filter 'RT_ADMIN_FIX*.ps1' -ErrorAction SilentlyContinue | ForEach-Object {
  Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
}
Get-ChildItem $env:TEMP -Filter 'REINO_TRIBAL_ADMIN_FIX*.ps1' -ErrorAction SilentlyContinue | ForEach-Object {
  Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
}

$dest = Join-Path $env:TEMP ("RT_ADMIN_FIX17_" + $PinnedCommit.Substring(0,12) + '_' + [Guid]::NewGuid().ToString('N') + '.ps1')

& $Curl.Source --fail --silent --show-error --location --http1.1 --tlsv1.2 --retry 5 --retry-all-errors --connect-timeout 20 --max-time 120 --output $dest $RawUrl
if ($LASTEXITCODE -ne 0) { throw "DOWNLOAD FIX17 FALHOU: curl exit $LASTEXITCODE" }
if (-not (Test-Path $dest) -or (Get-Item $dest).Length -lt 5000) { throw 'FIX17 baixado está ausente ou incompleto.' }

$text = [IO.File]::ReadAllText($dest)
foreach ($needle in @(
  "[string]`$BackendCommit = 'd5d1edadd9f33b612a233c4feed0e06ec97203bc'",
  '[switch]$PreflightOnly',
  '$preflightUrl = $preflightUri.AbsoluteUri',
  'CORS URL:',
  'CREDENCIAIS_ADMIN_REINO_TRIBAL_PENDENTE.txt',
  'Credencial PENDENTE preservada antes de alterar Deno',
  'REINO_TRIBAL_ADMIN_FIX17_VALIDADO'
)) {
  if (-not $text.Contains($needle)) { throw "ARQUIVO BAIXADO NÃO É O FIX17 VALIDADO. Marcador ausente: $needle" }
}

$tokens=$null; $errors=$null
[System.Management.Automation.Language.Parser]::ParseFile($dest,[ref]$tokens,[ref]$errors) | Out-Null
if ($errors.Count) { $errors | Format-List; throw 'FIX17 baixado não passou no parser PowerShell.' }

Write-Host 'PASS: arquivo FIX17 validado' -ForegroundColor Green
Write-Host "EXECUTANDO EXATAMENTE: $dest" -ForegroundColor Yellow

if ($ValidateOnly) {
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $dest -PreflightOnly
  if ($LASTEXITCODE -ne 0) { throw "PreflightOnly FIX17 falhou: $LASTEXITCODE" }

  $deno = Get-Command deno.exe -ErrorAction SilentlyContinue
  if ($deno) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $dest -ValidateOnly -DenoExeOverride $deno.Source
    if ($LASTEXITCODE -ne 0) { throw "ValidateOnly FIX17 falhou: $LASTEXITCODE" }
  } else {
    Write-Host 'AVISO: deno.exe não está no PATH; ValidateOnly do backend foi ignorado neste bootstrap.' -ForegroundColor Yellow
  }
  Write-Host 'REINO_TRIBAL_ADMIN_BOOTSTRAP_CANONICO_VALIDADO' -ForegroundColor Green
  exit 0
}

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $dest
if ($LASTEXITCODE -ne 0) { throw "FIX17 falhou com código $LASTEXITCODE" }
