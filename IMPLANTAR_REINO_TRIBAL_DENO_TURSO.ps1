param([switch]$ValidateOnly)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12

$LauncherUrl='https://raw.githubusercontent.com/kaalflash12/reinos-tribais-online/50810f90f5e0002a7e1fd2ea507cca2595c942a9/RT_REINO_TRIBAL_TURSO_DB_SHAPE_FIX5B.ps1'
$LauncherPath=Join-Path $env:TEMP 'RT_REINO_TRIBAL_TURSO_DB_SHAPE_FIX5B.ps1'

Write-Host '=== REINO TRIBAL - BOOTSTRAP FINAL FIX5B ===' -ForegroundColor Cyan
Write-Host 'Turso DB response normalizada + Deno device auth sem keychain, token manual ou TTY.' -ForegroundColor Green

Remove-Item $LauncherPath -Force -ErrorAction SilentlyContinue
Invoke-WebRequest -UseBasicParsing -Uri $LauncherUrl -OutFile $LauncherPath -TimeoutSec 120
if(-not(Test-Path $LauncherPath)-or(Get-Item $LauncherPath).Length -le 0){throw 'Falha baixando FIX5B validado.'}
$txt=[IO.File]::ReadAllText($LauncherPath)
[IO.File]::WriteAllText($LauncherPath,$txt,(New-Object Text.UTF8Encoding($true)))
$tokens=$null;$errors=$null
[System.Management.Automation.Language.Parser]::ParseFile($LauncherPath,[ref]$tokens,[ref]$errors)|Out-Null
if($errors.Count){throw ('FIX5B nao passou no parser: '+(($errors|ForEach-Object{$_.Message}) -join '; '))}

if($ValidateOnly){& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $LauncherPath -ValidateOnly}
else{& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $LauncherPath}
$code=$LASTEXITCODE
if($code -ne 0){throw "Bootstrap FIX5B parou no proximo erro real. Codigo: $code"}
