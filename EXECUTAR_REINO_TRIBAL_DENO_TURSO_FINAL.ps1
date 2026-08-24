param([switch]$ValidateOnly)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$LauncherUrl = 'https://raw.githubusercontent.com/kaalflash12/reinos-tribais-online/f213f0e8a3e517e01dc3276ae1cd3f3cdb11bc9e/RT_REINO_TRIBAL_TURSO_PESSOAL_20260824.ps1'
$LauncherPath = Join-Path $env:TEMP 'RT_REINO_TRIBAL_TURSO_PESSOAL_20260824.ps1'

Write-Host '=== REINO TRIBAL - ENTRADA FINAL ===' -ForegroundColor Cyan
Write-Host 'Turso pessoal gratuito + banco exclusivo + Deno automatico.' -ForegroundColor Green

@(
  (Join-Path $env:TEMP 'IMPLANTAR_REINO_TRIBAL_DENO_TURSO_FINAL.ps1'),
  (Join-Path $env:TEMP 'RT_BASE_LAUNCHER_VALIDADO.ps1'),
  (Join-Path $env:TEMP 'RT_REINO_TRIBAL_GHCLONE_TURSO_BROWSER_RUN.ps1'),
  $LauncherPath
) | ForEach-Object { Remove-Item $_ -Force -ErrorAction SilentlyContinue }

Invoke-WebRequest -UseBasicParsing -Uri $LauncherUrl -OutFile $LauncherPath -TimeoutSec 120
if (-not (Test-Path $LauncherPath) -or (Get-Item $LauncherPath).Length -le 0) { throw 'Falha baixando launcher final do Reino Tribal.' }

$txt=[IO.File]::ReadAllText($LauncherPath)
[IO.File]::WriteAllText($LauncherPath,$txt,(New-Object Text.UTF8Encoding($true)))
$tokens=$null;$errors=$null
[System.Management.Automation.Language.Parser]::ParseFile($LauncherPath,[ref]$tokens,[ref]$errors)|Out-Null
if($errors.Count){ throw ('Launcher final nao passou no parser: '+(($errors|ForEach-Object{$_.Message}) -join '; ')) }

if($ValidateOnly){
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $LauncherPath -ValidateOnly
}else{
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $LauncherPath
}
$code=$LASTEXITCODE
if($code -ne 0){ throw "Launcher final parou no erro real. Codigo: $code" }
