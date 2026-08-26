param(
  [string]$Repositorio = 'kaalflash12/reinos-tribais-online',
  [string]$DenoOrg = 'mestrederpg35',
  [string]$DenoApp = 'reino-tribal-api',
  [string]$DenoVersion = '2.9.5',
  [string]$DenoExeOverride = '',
  [switch]$ValidateOnly,
  [switch]$PreflightOnly,
  [switch]$IdentityOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$ExecutorVersion = 'RT91'
$ExecutorRevision = 'SAFE-CLI-AUTH-3'
$ExecutorContract = 'ADMIN_AUTHORITY_NO_SOURCE_DEPLOY_RT91'
$ExpectedBackend = 'https://reino-tribal-api.mestrederpg35.deno.net'
$BaseCommit = '133abc213cc3f269e1a5019a7c361847f8f72abe'
$BaseFile = 'REINO_TRIBAL_ADMIN_SAFE_RT91_CLI_AUTH.ps1'
$Repo = 'kaalflash12/reinos-tribais-online'
$Curl = (Get-Command curl.exe -ErrorAction Stop).Source
$Tmp = Join-Path $env:TEMP ('rt91-cli-auth3-' + [Guid]::NewGuid().ToString('N'))
$BasePath = Join-Path $Tmp 'RT91_BASE.ps1'
$PatchedPath = Join-Path $Tmp 'RT91_CLI_AUTH3_PATCHED.ps1'

# Contratos que este wrapper exige no executor-base pinado.
$RequiredBaseMarkers = @(
  "`$ExecutorVersion = 'RT91'",
  "`$ExecutorRevision = 'SAFE-CLI-AUTH-2'",
  "`$ExecutorContract = 'ADMIN_AUTHORITY_NO_SOURCE_DEPLOY_RT91'",
  "`$ExpectedBackend = 'https://reino-tribal-api.mestrederpg35.deno.net'",
  'Executar-Deno-Interativo',
  'Deno CLI + navegador',
  "'deploy','env','update-value'",
  'ANTI_DOWNGRADE: nenhum source deploy executado = PASS',
  'REINO_TRIBAL_ADMIN_RT91_VALIDADO'
)

try {
  New-Item -ItemType Directory -Force -Path $Tmp | Out-Null
  Write-Host ''
  Write-Host '=== REINO TRIBAL RT91 CLI-AUTH-3 ===' -ForegroundColor Cyan
  Write-Host ('BASE PINADA: ' + $BaseCommit) -ForegroundColor DarkGray

  $url = "https://raw.githubusercontent.com/$Repo/$BaseCommit/$BaseFile"
  & $Curl --fail --silent --show-error --location --http1.1 --tlsv1.2 --retry 5 --retry-all-errors --connect-timeout 20 --max-time 120 --output $BasePath $url
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path $BasePath) -or (Get-Item $BasePath).Length -lt 5000) {
    throw 'Falha baixando executor-base RT91 CLI-AUTH-2 pinado.'
  }

  $text = [IO.File]::ReadAllText($BasePath)
  foreach ($needle in $RequiredBaseMarkers) {
    if (-not $text.Contains($needle)) { throw "Executor-base nao cumpre contrato: $needle" }
  }
  if ($text.Contains("'deploy','--org'")) { throw 'ANTI-DOWNGRADE: source deploy detectado no executor-base.' }
  if ($text.Contains('console.deno.com/auth/interactive') -or $text.Contains('console.deno.com/auth/exchange')) {
    throw 'Auth HTTP manual proibido detectado no executor-base.'
  }

  $oldCors = "if(`$h -notmatch '(?im)^access-control-allow-origin:\s*\*'){Falhar 'CORS sem Access-Control-Allow-Origin esperado.'}"
  $newCors = "if(`$h -notmatch '(?im)^access-control-allow-origin:\s*https://kaalflash12\.github\.io\s*`$'){Falhar ('CORS allow-origin nao autoriza GitHub Pages.' + [Environment]::NewLine + `$h)}"
  if (-not $text.Contains($oldCors)) { throw 'Trecho CORS legado esperado nao foi encontrado; patch recusado.' }

  $text = $text.Replace("`$ExecutorRevision = 'SAFE-CLI-AUTH-2'","`$ExecutorRevision = 'SAFE-CLI-AUTH-3'")
  $text = $text.Replace($oldCors,$newCors)
  [IO.File]::WriteAllText($PatchedPath,$text,(New-Object Text.UTF8Encoding($false)))

  $tokens=$null;$errors=$null
  [Management.Automation.Language.Parser]::ParseFile($PatchedPath,[ref]$tokens,[ref]$errors)|Out-Null
  if ($errors.Count) { $errors|Format-List|Out-String|Write-Host; throw 'RT91 CLI-AUTH-3 nao passou no parser PowerShell.' }

  $patched = [IO.File]::ReadAllText($PatchedPath)
  foreach ($needle in @(
    "`$ExecutorRevision = 'SAFE-CLI-AUTH-3'",
    "access-control-allow-origin:\s*https://kaalflash12\.github\.io",
    'Executar-Deno-Interativo',
    "'deploy','env','update-value'",
    'ANTI_DOWNGRADE: nenhum source deploy executado = PASS',
    'REINO_TRIBAL_ADMIN_RT91_VALIDADO'
  )) { if (-not $patched.Contains($needle)) { throw "Patch RT91 CLI-AUTH-3 incompleto: $needle" } }
  if ($patched.Contains("'deploy','--org'")) { throw 'ANTI-DOWNGRADE: source deploy apareceu apos patch.' }

  Write-Host 'PASS: RT91 CLI-AUTH-3 parseado.' -ForegroundColor Green
  Write-Host 'PASS: CORS_GITHUB_PAGES_EXACT_ORIGIN_CONTRACT' -ForegroundColor Green
  Write-Host 'PASS: DENO_AUTH_OFICIAL_CLI_CONTRACT' -ForegroundColor Green
  Write-Host 'PASS: ANTI_DOWNGRADE_NO_SOURCE_DEPLOY_CONTRACT' -ForegroundColor Green

  $args = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$PatchedPath)
  if ($IdentityOnly) { $args += '-IdentityOnly' }
  if ($PreflightOnly) { $args += '-PreflightOnly' }
  if ($ValidateOnly) { $args += '-ValidateOnly' }
  if ($DenoExeOverride) { $args += @('-DenoExeOverride',$DenoExeOverride) }
  & powershell.exe @args
  $code=$LASTEXITCODE
  if($code -ne 0){throw "RT91 CLI-AUTH-3 terminou com codigo $code"}
} finally {
  Remove-Item $Tmp -Recurse -Force -ErrorAction SilentlyContinue
}
