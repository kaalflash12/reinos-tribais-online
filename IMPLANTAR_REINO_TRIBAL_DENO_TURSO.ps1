param([switch]$ValidateOnly)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Compatibilidade: este nome antigo não contém mais lógica de provisionamento.
# Toda execução é encaminhada para o launcher único já validado no Windows CI.
$LauncherUrl = 'https://raw.githubusercontent.com/kaalflash12/reinos-tribais-online/c16d93137fc827d352271656878d6b7eafe8176d/RT_REINO_TRIBAL_GHCLONE_TURSO_BROWSER_20260824.ps1'
$LauncherPath = Join-Path $env:TEMP 'RT_REINO_TRIBAL_GHCLONE_TURSO_BROWSER_20260824.ps1'

Write-Host '=== REINO TRIBAL - BOOTSTRAP COMPATIVEL APOSENTADO ===' -ForegroundColor Cyan
Write-Host 'Encaminhando para GHCLONE + TURSO BROWSER.' -ForegroundColor Green

Remove-Item $LauncherPath -Force -ErrorAction SilentlyContinue
Invoke-WebRequest -UseBasicParsing -Uri $LauncherUrl -OutFile $LauncherPath -TimeoutSec 120
if (-not (Test-Path $LauncherPath) -or (Get-Item $LauncherPath).Length -le 0) {
  throw 'Falha baixando o launcher único validado do Reino Tribal.'
}

$txt=[IO.File]::ReadAllText($LauncherPath)
[IO.File]::WriteAllText($LauncherPath,$txt,(New-Object Text.UTF8Encoding($true)))

$tokens=$null
$errors=$null
[System.Management.Automation.Language.Parser]::ParseFile($LauncherPath,[ref]$tokens,[ref]$errors) | Out-Null
if ($errors.Count -gt 0) {
  $msg=($errors | ForEach-Object { $_.Message + ' @ ' + $_.Extent.StartLineNumber + ':' + $_.Extent.StartColumnNumber }) -join "`n"
  throw "Launcher único não passou no parser.`n$msg"
}

if ($ValidateOnly) {
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $LauncherPath -ValidateOnly
} else {
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $LauncherPath
}
$code=$LASTEXITCODE
if ($code -ne 0) { throw "Launcher único parou no erro real. Código: $code" }
