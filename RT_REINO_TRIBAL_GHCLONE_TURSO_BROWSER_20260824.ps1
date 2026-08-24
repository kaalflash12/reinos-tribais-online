param([switch]$ValidateOnly)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$PinnedLauncher = 'https://raw.githubusercontent.com/kaalflash12/reinos-tribais-online/4240490a8e2e7d57d9da749ab6bc09a92755fdd8/EXECUTAR_REINO_TRIBAL_DENO_TURSO_FINAL.ps1'
$RunPath = Join-Path $env:TEMP 'RT_REINO_TRIBAL_GHCLONE_TURSO_BROWSER_RUN.ps1'

Write-Host '=== RT FINAL 20260824 - GHCLONE + TURSO BROWSER ===' -ForegroundColor Cyan
Write-Host 'Este launcher usa nome novo para impedir execucao acidental de TEMP antigo.' -ForegroundColor Green

foreach ($old in @(
  (Join-Path $env:TEMP 'EXECUTAR_REINO_TRIBAL_DENO_TURSO_FINAL.ps1'),
  (Join-Path $env:TEMP 'IMPLANTAR_REINO_TRIBAL_DENO_TURSO_FINAL.ps1'),
  (Join-Path $env:TEMP 'RT_BASE_LAUNCHER_VALIDADO.ps1'),
  $RunPath
)) {
  Remove-Item $old -Force -ErrorAction SilentlyContinue
}

Invoke-WebRequest -UseBasicParsing -Uri $PinnedLauncher -OutFile $RunPath -TimeoutSec 120
if (-not (Test-Path $RunPath) -or (Get-Item $RunPath).Length -le 0) {
  throw 'Falha baixando o launcher GHCLONE/Turso Browser validado.'
}

$txt = [IO.File]::ReadAllText($RunPath)
$utf8Bom = New-Object Text.UTF8Encoding($true)
[IO.File]::WriteAllText($RunPath,$txt,$utf8Bom)

$tokens=$null
$errors=$null
[System.Management.Automation.Language.Parser]::ParseFile($RunPath,[ref]$tokens,[ref]$errors) | Out-Null
if ($errors.Count -gt 0) {
  $msg = ($errors | ForEach-Object { $_.Message + ' @ ' + $_.Extent.StartLineNumber + ':' + $_.Extent.StartColumnNumber }) -join "`n"
  throw "Launcher GHCLONE nao passou no parser.`n$msg"
}

$source = [IO.File]::ReadAllText($RunPath)
foreach ($needle in @(
  'Fonte da branch: GitHub CLI autenticado, sem codeload anonimo.',
  '''repo'',''clone'',$Repositorio,$repoDir',
  '''--branch'',$Branch,''--depth'',''1'',''--single-branch''',
  'Obter-TursoPlatformTokenBrowser'
)) {
  if (-not $source.Contains($needle)) { throw "Launcher pinado perdeu contrato obrigatorio: $needle" }
}

Write-Host 'PASS: launcher unico carregado.' -ForegroundColor Green
Write-Host 'PASS: fonte = GitHub CLI autenticado.' -ForegroundColor Green
Write-Host 'PASS: Turso = login no navegador/callback.' -ForegroundColor Green

if ($ValidateOnly) {
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $RunPath -ValidateOnly
} else {
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $RunPath
}
$code=$LASTEXITCODE
if ($code -ne 0) { throw "Launcher GHCLONE parou no erro real. Codigo: $code" }
