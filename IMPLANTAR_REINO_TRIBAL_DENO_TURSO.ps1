param([switch]$ValidateOnly)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$LauncherUrl = 'https://raw.githubusercontent.com/kaalflash12/reinos-tribais-online/ed588a887b5bf01b7b34a655f836b900624abdd4/RT_REINO_TRIBAL_TURSO_PESSOAL_20260824.ps1'
$LauncherPath = Join-Path $env:TEMP 'RT_REINO_TRIBAL_TURSO_PESSOAL_20260824.ps1'

Write-Host '=== REINO TRIBAL - BOOTSTRAP COMPATIVEL ===' -ForegroundColor Cyan
Write-Host 'Encaminhando para Turso gratuito + banco exclusivo + Deno automatico, sem indexacao vazia.' -ForegroundColor Green

Remove-Item $LauncherPath -Force -ErrorAction SilentlyContinue
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
