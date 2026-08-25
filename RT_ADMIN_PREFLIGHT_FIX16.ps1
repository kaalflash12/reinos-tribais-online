$ErrorActionPreference = 'Stop'
$src = Join-Path $PSScriptRoot 'REINO_TRIBAL_ADMIN_FIX15_FINAL.ps1'
$dst = Join-Path $PSScriptRoot 'REINO_TRIBAL_ADMIN_FIX16_FINAL.ps1'
if (-not (Test-Path $src)) { throw 'FIX15 final nao encontrado.' }
$text = [IO.File]::ReadAllText($src)

# Adiciona modo de teste publico do preflight sem Deno/Turso/deploy.
$paramOld = "  [string]`$DenoExeOverride = '',`n  [switch]`$ValidateOnly`n)"
$paramNew = "  [string]`$DenoExeOverride = '',`n  [switch]`$ValidateOnly,`n  [switch]`$PreflightOnly`n)"
if (-not $text.Contains($paramOld)) { throw 'Bloco de parametros FIX15 nao encontrado.' }
$text = $text.Replace($paramOld,$paramNew)

# Corrige especificamente a montagem da URL usada pelo curl OPTIONS.
$fnOld = "function Testar-Preflight {`n  `$headers = Join-Path `$env:TEMP ('rt-fix15-cors-' + [Guid]::NewGuid().ToString('N') + '.txt')"
$fnNew = @'
function Testar-Preflight {
  $preflightUri = [Uri]($Backend.TrimEnd('/') + '/api/reino')
  if (-not $preflightUri.IsAbsoluteUri -or [string]::IsNullOrWhiteSpace($preflightUri.Host)) {
    Falhar ("URL CORS invalida antes do curl: " + [string]$preflightUri)
  }
  $preflightUrl = $preflightUri.AbsoluteUri
  Write-Host ("CORS URL: " + $preflightUrl) -ForegroundColor DarkGray
  $headers = Join-Path $env:TEMP ('rt-fix16-cors-' + [Guid]::NewGuid().ToString('N') + '.txt')
'@
$fnNew = $fnNew.TrimEnd("`r","`n")
if (-not $text.Contains($fnOld)) { throw 'Inicio de Testar-Preflight FIX15 nao encontrado.' }
$text = $text.Replace($fnOld,$fnNew)

$callOld = "      `$Backend + '/api/reino'`n    ) -TimeoutSec 45 -Rotulo 'CORS preflight publico'"
$callNew = "      `$preflightUrl`n    ) -TimeoutSec 45 -Rotulo 'CORS preflight publico'"
if (-not $text.Contains($callOld)) { throw 'Argumento URL antigo do preflight nao encontrado.' }
$text = $text.Replace($callOld,$callNew)

$tryOld = "try {`n  Etapa 'FIX15 - sincronizacao definitiva do administrador'"
$tryNew = @'
if ($PreflightOnly) {
  Etapa 'FIX16 - teste publico isolado de CORS'
  if (-not $CurlCmd) { Falhar 'curl.exe nao encontrado no Windows.' }
  Testar-Preflight
  Ok 'FIX16_PREFLIGHT_PUBLICO_PASS'
  return
}

try {
  Etapa 'FIX16 - sincronizacao definitiva do administrador'
'@
$tryNew = $tryNew.TrimEnd("`r","`n")
if (-not $text.Contains($tryOld)) { throw 'Inicio do fluxo principal FIX15 nao encontrado.' }
$text = $text.Replace($tryOld,$tryNew)

$text = $text.Replace('REINO_TRIBAL_ADMIN_FIX15_VALIDADO','REINO_TRIBAL_ADMIN_FIX16_VALIDADO')
$text = $text.Replace('rt-fix15-','rt-fix16-')

foreach ($needle in @(
  '[switch]$PreflightOnly',
  '$preflightUri = [Uri]($Backend.TrimEnd(''/'') + ''/api/reino'')',
  '$preflightUrl = $preflightUri.AbsoluteUri',
  'CORS URL:',
  'FIX16_PREFLIGHT_PUBLICO_PASS',
  'REINO_TRIBAL_ADMIN_FIX16_VALIDADO'
)) {
  if (-not $text.Contains($needle)) { throw "Contrato FIX16 ausente: $needle" }
}

[IO.File]::WriteAllText($dst,$text,(New-Object Text.UTF8Encoding($false)))
Write-Host 'FIX16_TRANSFORM_PASS'
