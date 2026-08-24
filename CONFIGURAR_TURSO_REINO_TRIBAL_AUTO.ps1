$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Origem = 'https://raw.githubusercontent.com/kaalflash12/reinos-tribais-online/rt-turso-migration/RECUPERAR_REINO_TRIBAL_SEM_REINSTALAR.ps1'
$Destino = Join-Path $env:TEMP 'RECUPERAR_REINO_TRIBAL_SEM_REINSTALAR.ps1'

Write-Host '=== REINO TRIBAL - RECOVERY SEM REINSTALAR ===' -ForegroundColor Cyan
Remove-Item $Destino -Force -ErrorAction SilentlyContinue
Invoke-WebRequest -UseBasicParsing -Uri $Origem -OutFile $Destino -TimeoutSec 120
if (-not (Test-Path $Destino) -or (Get-Item $Destino).Length -le 0) {
  throw 'Falha baixando o recovery do Reino Tribal.'
}

$texto = [IO.File]::ReadAllText($Destino)
$utf8Bom = New-Object Text.UTF8Encoding($true)
[IO.File]::WriteAllText($Destino,$texto,$utf8Bom)

$tokens=$null
$errors=$null
[System.Management.Automation.Language.Parser]::ParseFile($Destino,[ref]$tokens,[ref]$errors) | Out-Null
if ($errors.Count -gt 0) {
  $msg = ($errors | ForEach-Object { $_.Message + ' @ ' + $_.Extent.StartLineNumber + ':' + $_.Extent.StartColumnNumber }) -join "`n"
  throw "Recovery não passou no parser; nada foi executado.`n$msg"
}

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Destino
if ($LASTEXITCODE -ne 0) {
  throw "Recovery parou no erro real. Código: $LASTEXITCODE"
}
