$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Origem = 'https://raw.githubusercontent.com/kaalflash12/reinos-tribais-online/rt-turso-migration/RECUPERAR_REINO_TRIBAL_SEM_TRAVAR.ps1'
$Destino = Join-Path $env:TEMP 'RECUPERAR_REINO_TRIBAL_SEM_TRAVAR.ps1'

Write-Host '=== REINO TRIBAL - RECOVERY ANTI-TRAVAMENTO ===' -ForegroundColor Cyan
Remove-Item $Destino -Force -ErrorAction SilentlyContinue
Invoke-WebRequest -UseBasicParsing -Uri $Origem -OutFile $Destino -TimeoutSec 120
if (-not (Test-Path $Destino) -or (Get-Item $Destino).Length -le 0) { throw 'Falha baixando o recovery anti-travamento.' }
$texto = [IO.File]::ReadAllText($Destino)
$utf8Bom = New-Object Text.UTF8Encoding($true)
[IO.File]::WriteAllText($Destino,$texto,$utf8Bom)
$tokens=$null; $errors=$null
[System.Management.Automation.Language.Parser]::ParseFile($Destino,[ref]$tokens,[ref]$errors) | Out-Null
if ($errors.Count -gt 0) { throw ('Recovery anti-travamento não passou no parser: ' + (($errors | ForEach-Object {$_.Message}) -join '; ')) }
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Destino
if ($LASTEXITCODE -ne 0) { throw "Recovery parou no erro real. Código: $LASTEXITCODE" }
