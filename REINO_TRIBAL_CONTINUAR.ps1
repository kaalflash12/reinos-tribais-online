param(
  [switch]$IdentityOnly,
  [switch]$PreflightOnly,
  [switch]$ValidateOnly,
  [string]$DenoExeOverride = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$CanonicalCommit = 'e57caab5f36096575902438e9ec2145c1b90ef8f'
$CanonicalFile = 'REINO_TRIBAL_ADMIN_ATUAL.ps1'
$CanonicalVersion = 'FIX17'
$CanonicalRevision = 'CHECKPOINT-1'
$ExpectedBackend = 'https://reino-tribal-api.mestrederpg35.deno.net'
$Repo = 'kaalflash12/reinos-tribais-online'
$Curl = Get-Command curl.exe -ErrorAction SilentlyContinue
if (-not $Curl) { throw 'curl.exe nao encontrado no Windows.' }

$legacyPatterns = @(
  'RT_ADMIN_FIX15*.ps1',
  'RT_ADMIN_FIX16*.ps1',
  'REINO_TRIBAL_ADMIN_FIX15*.ps1',
  'REINO_TRIBAL_ADMIN_FIX16*.ps1',
  'REINO_TRIBAL_RESUMIR_POS_DEPLOY_FIX11*.ps1',
  'RT_FIX13*.ps1',
  'RT_FIX14*.ps1'
)
foreach ($pattern in $legacyPatterns) {
  Get-ChildItem -LiteralPath $env:TEMP -Filter $pattern -File -ErrorAction SilentlyContinue |
    Remove-Item -Force -ErrorAction SilentlyContinue
}

$target = Join-Path $env:TEMP ('REINO_TRIBAL_ADMIN_ATUAL_FIX17_CHECKPOINT1_' + $CanonicalCommit.Substring(0,8) + '.ps1')
Remove-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
$url = "https://raw.githubusercontent.com/$Repo/$CanonicalCommit/$CanonicalFile"

Write-Host ''
Write-Host '=== REINO TRIBAL LAUNCHER CANONICO ===' -ForegroundColor Cyan
Write-Host ('CANONICAL COMMIT: ' + $CanonicalCommit) -ForegroundColor DarkGray
Write-Host ('DESTINO: ' + $target) -ForegroundColor Yellow

& $Curl.Source --fail --silent --show-error --location --http1.1 --tlsv1.2 --retry 5 --retry-all-errors --connect-timeout 20 --max-time 120 --output $target $url
if ($LASTEXITCODE -ne 0) { throw "Download do executor canonico falhou: curl exit $LASTEXITCODE" }
if (-not (Test-Path $target) -or (Get-Item $target).Length -lt 1000) { throw 'Executor canonico ausente ou vazio apos download.' }

$text = [IO.File]::ReadAllText($target)
foreach ($needle in @(
  "`$ExecutorVersion = '$CanonicalVersion'",
  "`$ExecutorRevision = '$CanonicalRevision'",
  "`$ExpectedBackend = '$ExpectedBackend'",
  'REINO_TRIBAL_EXECUTOR_ATIVO.txt',
  'CREDENCIAIS_ADMIN_REINO_TRIBAL_PENDENTES.txt',
  '$preflightUrl = $preflightUri.AbsoluteUri',
  'CREDENCIAL PRESERVADA APOS A FALHA:',
  'REINO_TRIBAL_ADMIN_FIX17_VALIDADO'
)) {
  if (-not $text.Contains($needle)) { throw "Executor baixado nao cumpre contrato canonico: $needle" }
}
if ($text.Contains("`$ExecutorVersion = 'FIX15'") -or $text.Contains("`$ExecutorVersion = 'FIX16'")) {
  throw 'Executor legado detectado. Nada sera executado.'
}

$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile($target,[ref]$tokens,[ref]$errors) | Out-Null
if ($errors.Count -gt 0) {
  $errors | Format-List
  throw 'Executor canonico nao passou no parser PowerShell.'
}

Write-Host 'PASS: arquivo FIX17/CHECKPOINT-1 baixado e validado.' -ForegroundColor Green

$args = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$target)
if ($IdentityOnly) { $args += '-IdentityOnly' }
if ($PreflightOnly) { $args += '-PreflightOnly' }
if ($ValidateOnly) { $args += '-ValidateOnly' }
if ($DenoExeOverride) { $args += @('-DenoExeOverride',$DenoExeOverride) }

& powershell.exe @args
$code = $LASTEXITCODE
if ($code -ne 0) {
  $pending = Join-Path (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'ReinoTribal') 'CREDENCIAIS_ADMIN_REINO_TRIBAL_PENDENTES.txt'
  if (Test-Path $pending) {
    Write-Host ''
    Write-Host 'A CREDENCIAL GERADA FOI PRESERVADA EM:' -ForegroundColor Yellow
    Write-Host $pending -ForegroundColor Yellow
  }
  throw "Executor canonico FIX17 terminou com codigo $code"
}

Write-Host 'PASS: REINO_TRIBAL_LAUNCHER_CANONICO_CONCLUIDO' -ForegroundColor Green
