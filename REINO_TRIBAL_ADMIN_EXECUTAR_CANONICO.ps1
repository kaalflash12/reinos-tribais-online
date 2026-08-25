param(
  [switch]$ValidateOnly,
  [switch]$PreflightOnly,
  [string]$DenoExeOverride = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$ExecutorCommit = 'e86544bcf3902c1e2600f5efc76cee09fdddb02c'
$ExpectedSha256 = '8a9a93e0cee6f0f63e6df37ffeb60704d19cd7e287de0617d4fd924516bedfc2'
$Repo = 'kaalflash12/reinos-tribais-online'
$TargetName = 'RT_ADMIN_CANONICO_e86544bc.ps1'
$Target = Join-Path $env:TEMP $TargetName
$Curl = Get-Command curl.exe -ErrorAction SilentlyContinue
if (-not $Curl) { throw 'curl.exe nao encontrado no Windows.' }

foreach ($legacy in @(
  'RT_ADMIN_FIX15.ps1',
  'RT_ADMIN_FIX16.ps1',
  'RT_ADMIN_FIX16_be58d645.ps1',
  'RT_ADMIN_CANONICO_e86544bc.ps1',
  'REINO_TRIBAL_ADMIN_FIX15_FINAL.ps1',
  'REINO_TRIBAL_ADMIN_FIX16_FINAL.ps1'
)) {
  Remove-Item -LiteralPath (Join-Path $env:TEMP $legacy) -Force -ErrorAction SilentlyContinue
}

$url = "https://raw.githubusercontent.com/$Repo/$ExecutorCommit/REINO_TRIBAL_ADMIN_FINAL.ps1"
$downloaded = $false
for ($i=1; $i -le 5; $i++) {
  & $Curl.Source --fail --silent --show-error --location --http1.1 --tlsv1.2 --retry 3 --retry-all-errors --connect-timeout 20 --max-time 120 --output $Target $url
  if ($LASTEXITCODE -eq 0 -and (Test-Path $Target) -and (Get-Item $Target).Length -gt 1000) { $downloaded = $true; break }
  Remove-Item $Target -Force -ErrorAction SilentlyContinue
  if ($i -lt 5) { Start-Sleep -Seconds (2*$i) }
}
if (-not $downloaded) { throw 'Executor canonico nao foi baixado.' }

$actualSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $Target).Hash.ToLowerInvariant()
if ($actualSha -ne $ExpectedSha256) {
  Remove-Item $Target -Force -ErrorAction SilentlyContinue
  throw "SHA256 DO EXECUTOR NAO CONFERE. Esperado=$ExpectedSha256 Obtido=$actualSha. NADA FOI EXECUTADO."
}

$tokens=$null
$errors=$null
[System.Management.Automation.Language.Parser]::ParseFile($Target,[ref]$tokens,[ref]$errors)|Out-Null
if ($errors.Count) {
  Remove-Item $Target -Force -ErrorAction SilentlyContinue
  $errors | Format-List
  throw 'Executor canonico nao passou no parser PowerShell. NADA FOI EXECUTADO.'
}

$text=[IO.File]::ReadAllText($Target)
foreach($needle in @(
  "`$ExecutorBuild = 'REINO_TRIBAL_ADMIN_FIX17_FINAL'",
  'EXECUTOR SHA256:',
  '$preflightUrl = $preflightUri.AbsoluteUri',
  'REINO_TRIBAL_ADMIN_FIX17_VALIDADO'
)) {
  if(-not $text.Contains($needle)) {
    Remove-Item $Target -Force -ErrorAction SilentlyContinue
    throw "Executor canonico sem contrato FIX17: $needle"
  }
}

Write-Host "`n=== REINO TRIBAL ADMIN CANONICO ===" -ForegroundColor Cyan
Write-Host "Commit executor: $ExecutorCommit" -ForegroundColor DarkGray
Write-Host "SHA256 validado: $actualSha" -ForegroundColor Green
Write-Host "Arquivo executado: $Target" -ForegroundColor Yellow

$args = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$Target)
if ($ValidateOnly) { $args += '-ValidateOnly' }
if ($PreflightOnly) { $args += '-PreflightOnly' }
if ($DenoExeOverride) { $args += @('-DenoExeOverride',$DenoExeOverride) }

& powershell.exe @args
$code=$LASTEXITCODE
if ($code -ne 0) { throw "Executor canonico terminou com codigo $code" }
