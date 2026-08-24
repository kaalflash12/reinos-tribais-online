param([switch]$ValidateOnly)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12

$LauncherUrl='https://raw.githubusercontent.com/kaalflash12/reinos-tribais-online/41ec0982b2d37f163ea832a907c78130cb4fa118/RT_REINO_TRIBAL_DENO_DEVICE_AUTH_FIX4C.ps1'
$LauncherPath=Join-Path $env:TEMP 'RT_REINO_TRIBAL_DENO_DEVICE_AUTH_FIX4C.ps1'

Write-Host '=== REINO TRIBAL - ENTRADA FINAL FIX4C ===' -ForegroundColor Cyan
Write-Host 'Turso v2/v1 + Deno device auth oficial sem keychain/TTY.' -ForegroundColor Green

@(
  (Join-Path $env:TEMP 'IMPLANTAR_REINO_TRIBAL_DENO_TURSO_FINAL.ps1'),
  (Join-Path $env:TEMP 'RT_REINO_TRIBAL_DENO_DEVICE_AUTH_FIX4C_INNER.ps1'),
  $LauncherPath
)|ForEach-Object{Remove-Item $_ -Force -ErrorAction SilentlyContinue}

Invoke-WebRequest -UseBasicParsing -Uri $LauncherUrl -OutFile $LauncherPath -TimeoutSec 120
if(-not(Test-Path $LauncherPath)-or(Get-Item $LauncherPath).Length -le 0){throw 'Falha baixando FIX4C validado.'}
$txt=[IO.File]::ReadAllText($LauncherPath)
[IO.File]::WriteAllText($LauncherPath,$txt,(New-Object Text.UTF8Encoding($true)))
$tokens=$null;$errors=$null
[System.Management.Automation.Language.Parser]::ParseFile($LauncherPath,[ref]$tokens,[ref]$errors)|Out-Null
if($errors.Count){throw ('FIX4C nao passou no parser: '+(($errors|ForEach-Object{$_.Message}) -join '; '))}

if($ValidateOnly){& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $LauncherPath -ValidateOnly}
else{& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $LauncherPath}
$code=$LASTEXITCODE
if($code -ne 0){throw "Launcher FIX4C parou no proximo erro real. Codigo: $code"}
