param([switch]$ValidateOnly)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Compatibilidade apenas. Toda a lógica final vive no launcher único pinado abaixo.
# Revalidação Windows solicitada após runner anterior ficar preso no checkout.
$LauncherUrl = 'https://raw.githubusercontent.com/kaalflash12/reinos-tribais-online/dfca9197c7feae252eef4bbcb1035ac4237f1938/RT_REINO_TRIBAL_GHCLONE_TURSO_BROWSER_20260824.ps1'
$LauncherPath = Join-Path $env:TEMP 'RT_REINO_TRIBAL_GHCLONE_TURSO_BROWSER_20260824.ps1'

Write-Host '=== REINO TRIBAL - ENTRADA COMPATIVEL ===' -ForegroundColor Cyan
Write-Host 'Executor antigo aposentado. Encaminhando para GHCLONE + TURSO BROWSER + DENO AUTO.' -ForegroundColor Green

@(
  (Join-Path $env:TEMP 'IMPLANTAR_REINO_TRIBAL_DENO_TURSO_FINAL.ps1'),
  (Join-Path $env:TEMP 'RT_BASE_LAUNCHER_VALIDADO.ps1'),
  (Join-Path $env:TEMP 'RT_REINO_TRIBAL_GHCLONE_TURSO_BROWSER_RUN.ps1'),
  $LauncherPath
) | ForEach-Object { Remove-Item $_ -Force -ErrorAction SilentlyContinue }

Invoke-WebRequest -UseBasicParsing -Uri $LauncherUrl -OutFile $LauncherPath -TimeoutSec 120
if (-not (Test-Path $LauncherPath) -or (Get-Item $LauncherPath).Length -le 0) {
  throw 'Falha baixando o launcher único validado do Reino Tribal.'
}

$txt = [IO.File]::ReadAllText($LauncherPath)
[IO.File]::WriteAllText($LauncherPath,$txt,(New-Object Text.UTF8Encoding($true)))

$tokens=$null
$errors=$null
[System.Management.Automation.Language.Parser]::ParseFile($LauncherPath,[ref]$tokens,[ref]$errors) | Out-Null
if ($errors.Count -gt 0) {
  $msg = ($errors | ForEach-Object { $_.Message + ' @ ' + $_.Extent.StartLineNumber + ':' + $_.Extent.StartColumnNumber }) -join "`n"
  throw "Launcher único não passou no parser.`n$msg"
}

if ($ValidateOnly) {
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $LauncherPath -ValidateOnly
} else {
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $LauncherPath
}
$code=$LASTEXITCODE
if ($code -ne 0) { throw "Launcher único parou no erro real. Código: $code" }