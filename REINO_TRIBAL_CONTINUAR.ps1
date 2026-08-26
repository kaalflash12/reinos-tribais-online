param(
  [switch]$IdentityOnly,
  [switch]$PreflightOnly,
  [switch]$ValidateOnly,
  [string]$DenoExeOverride = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$CanonicalCommit = '133abc213cc3f269e1a5019a7c361847f8f72abe'
$CanonicalFile = 'REINO_TRIBAL_ADMIN_SAFE_RT91_CLI_AUTH.ps1'
$CanonicalVersion = 'RT91'
$CanonicalRevision = 'SAFE-CLI-AUTH-2'
$CanonicalContract = 'ADMIN_AUTHORITY_NO_SOURCE_DEPLOY_RT91'
$ExpectedBackend = 'https://reino-tribal-api.mestrederpg35.deno.net'
$Repo = 'kaalflash12/reinos-tribais-online'
$Curl = Get-Command curl.exe -ErrorAction SilentlyContinue
if (-not $Curl) { throw 'curl.exe nao encontrado no Windows.' }

$legacyPatterns = @(
  'RT_ADMIN_FIX15*.ps1',
  'RT_ADMIN_FIX16*.ps1',
  'REINO_TRIBAL_ADMIN_FIX15*.ps1',
  'REINO_TRIBAL_ADMIN_FIX16*.ps1',
  'REINO_TRIBAL_ADMIN_ATUAL_FIX17*.ps1',
  'REINO_TRIBAL_RESUMIR_POS_DEPLOY_FIX11*.ps1',
  'RT_FIX13*.ps1',
  'RT_FIX14*.ps1'
)
foreach ($pattern in $legacyPatterns) {
  Get-ChildItem -LiteralPath $env:TEMP -Filter $pattern -File -ErrorAction SilentlyContinue |
    Remove-Item -Force -ErrorAction SilentlyContinue
}

$target = Join-Path $env:TEMP ('REINO_TRIBAL_ADMIN_RT91_SAFE_' + $CanonicalCommit.Substring(0,8) + '.ps1')
Remove-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
$url = "https://raw.githubusercontent.com/$Repo/$CanonicalCommit/$CanonicalFile"

Write-Host ''
Write-Host '=== REINO TRIBAL LAUNCHER CANONICO RT91 ===' -ForegroundColor Cyan
Write-Host ('CANONICAL COMMIT: ' + $CanonicalCommit) -ForegroundColor DarkGray
Write-Host ('DESTINO: ' + $target) -ForegroundColor Yellow

& $Curl.Source --fail --silent --show-error --location --http1.1 --tlsv1.2 --retry 5 --retry-all-errors --connect-timeout 20 --max-time 120 --output $target $url
if ($LASTEXITCODE -ne 0) { throw "Download do executor canonico falhou: curl exit $LASTEXITCODE" }
if (-not (Test-Path $target) -or (Get-Item $target).Length -lt 1000) { throw 'Executor canonico ausente ou vazio apos download.' }

$text = [IO.File]::ReadAllText($target)
foreach ($needle in @(
  "`$ExecutorVersion = '$CanonicalVersion'",
  "`$ExecutorRevision = '$CanonicalRevision'",
  "`$ExecutorContract = '$CanonicalContract'",
  "`$ExpectedBackend = '$ExpectedBackend'",
  'REINO_TRIBAL_EXECUTOR_ATIVO.txt',
  'CREDENCIAIS_ADMIN_REINO_TRIBAL_PENDENTES.txt',
  'ANTI_DOWNGRADE: nenhum source deploy executado = PASS',
  'REINO_TRIBAL_ADMIN_RT91_VALIDADO',
  'Executar-Deno-Interativo',
  'Deno CLI + navegador'
)) {
  if (-not $text.Contains($needle)) { throw "Executor baixado nao cumpre contrato canonico RT91: $needle" }
}
if ($text.Contains("'deploy','--org'")) {
  throw 'ANTI-DOWNGRADE: executor contem source deploy. Nada sera executado.'
}
if (-not $text.Contains("'deploy','env','update-value'")) {
  throw 'Executor RT91 nao contem atualizacao segura de secrets.'
}
if ($text.Contains('console.deno.com/auth/interactive') -or $text.Contains('console.deno.com/auth/exchange')) {
  throw 'Executor RT91 voltou a usar auth HTTP manual proibido.'
}

$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile($target,[ref]$tokens,[ref]$errors) | Out-Null
if ($errors.Count -gt 0) {
  $errors | Format-List
  throw 'Executor canonico RT91 nao passou no parser PowerShell.'
}

Write-Host 'PASS: arquivo RT91 SAFE CLI-AUTH baixado e validado.' -ForegroundColor Green
Write-Host 'PASS: ANTI_DOWNGRADE_NO_SOURCE_DEPLOY_CONTRACT' -ForegroundColor Green
Write-Host 'PASS: DENO_AUTH_OFICIAL_CLI_CONTRACT' -ForegroundColor Green

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
  throw "Executor canonico RT91 terminou com codigo $code"
}

Write-Host 'PASS: REINO_TRIBAL_LAUNCHER_CANONICO_RT91_CONCLUIDO' -ForegroundColor Green
