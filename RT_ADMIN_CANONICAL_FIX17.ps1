$ErrorActionPreference = 'Stop'
$src = Join-Path $PSScriptRoot 'REINO_TRIBAL_ADMIN_FIX16_FINAL.ps1'
$dst = Join-Path $PSScriptRoot 'REINO_TRIBAL_ADMIN_ATUAL.ps1'
if (-not (Test-Path $src)) { throw 'FIX16 final nao encontrado.' }
$text = [IO.File]::ReadAllText($src).Replace("`r`n","`n")

function Insert-AfterLineContaining([string]$InputText,[string]$Needle,[string]$InsertText) {
  $idx = $InputText.IndexOf($Needle,[StringComparison]::Ordinal)
  if ($idx -lt 0) { throw "Linha ancora nao encontrada: $Needle" }
  $eol = $InputText.IndexOf("`n",$idx)
  if ($eol -lt 0) { $eol = $InputText.Length - 1 }
  return $InputText.Substring(0,$eol + 1) + $InsertText.TrimEnd("`r","`n") + "`n" + $InputText.Substring($eol + 1)
}

$paramOld = "  [switch]`$PreflightOnly`n)"
$paramNew = "  [switch]`$PreflightOnly,`n  [switch]`$IdentityOnly`n)"
if (-not $text.Contains($paramOld)) { throw 'Bloco de parametros FIX16 nao encontrado.' }
$text = $text.Replace($paramOld,$paramNew)

$identityVars = @'
$ExecutorVersion = 'FIX17'
$ExecutorContract = 'ADMIN_AUTHORITY_CORS_CANONICAL'
$ExpectedBackend = 'https://reino-tribal-api.mestrederpg35.deno.net'
$SelfPath = [string]$MyInvocation.MyCommand.Path
$SelfLeaf = if ($SelfPath) { Split-Path $SelfPath -Leaf } else { '<interactive>' }
$ExecutionMarker = Join-Path $env:TEMP 'REINO_TRIBAL_EXECUTOR_ATIVO.txt'
'@
$text = Insert-AfterLineContaining $text "`$CredFile = Join-Path `$CredDir 'CREDENCIAIS_ADMIN_REINO_TRIBAL.txt'" $identityVars

$identityBlock = @'
function Mostrar-Identidade {
  Write-Host ''
  Write-Host '=== REINO TRIBAL EXECUTOR CANONICO ===' -ForegroundColor Cyan
  Write-Host ('VERSAO: ' + $ExecutorVersion) -ForegroundColor Green
  Write-Host ('CONTRATO: ' + $ExecutorContract) -ForegroundColor DarkGray
  Write-Host ('ARQUIVO: ' + $SelfPath) -ForegroundColor Yellow
  Write-Host ('PID: ' + $PID) -ForegroundColor DarkGray
  Write-Host ('BACKEND: ' + $Backend) -ForegroundColor DarkGray
  Write-Host ('BACKEND COMMIT: ' + $BackendCommit) -ForegroundColor DarkGray
}

function Limpar-CopiasLegadas {
  $patterns = @(
    'RT_ADMIN_FIX15*.ps1',
    'RT_ADMIN_FIX16*.ps1',
    'REINO_TRIBAL_ADMIN_FIX15*.ps1',
    'REINO_TRIBAL_ADMIN_FIX16*.ps1',
    'REINO_TRIBAL_RESUMIR_POS_DEPLOY_FIX11*.ps1',
    'RT_FIX13*.ps1',
    'RT_FIX14*.ps1'
  )
  foreach ($pattern in $patterns) {
    Get-ChildItem -LiteralPath $env:TEMP -Filter $pattern -File -ErrorAction SilentlyContinue | ForEach-Object {
      if (-not $SelfPath -or $_.FullName -ne $SelfPath) {
        Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
      }
    }
  }
}

Mostrar-Identidade
if ($SelfLeaf -match '(?i)FIX1[56]') {
  Falhar ('FIX17 recusou nome de arquivo legado: ' + $SelfLeaf + '. Baixe o executor canonico novamente.')
}
if ($Backend -ne $ExpectedBackend) {
  Falhar ('Backend inesperado no FIX17: ' + $Backend)
}
Limpar-CopiasLegadas
$markerText = @(
  ('version=' + $ExecutorVersion),
  ('contract=' + $ExecutorContract),
  ('path=' + $SelfPath),
  ('pid=' + $PID),
  ('backend=' + $Backend),
  ('backend_commit=' + $BackendCommit),
  ('started_utc=' + [DateTime]::UtcNow.ToString('o'))
) -join [Environment]::NewLine
[IO.File]::WriteAllText($ExecutionMarker,$markerText,(New-Object Text.UTF8Encoding($false)))
if ($IdentityOnly) {
  Ok 'REINO_TRIBAL_FIX17_IDENTITY_PASS'
  return
}
'@
$text = Insert-AfterLineContaining $text 'function Falhar([string]$Texto) { throw $Texto }' $identityBlock

$text = $text.Replace("('reino-tribal-admin-fix15-'","('reino-tribal-admin-fix17-'")
$text = $text.Replace('FIX16 - teste publico isolado de CORS','FIX17 - teste publico isolado de CORS')
$text = $text.Replace('FIX16 - sincronizacao definitiva do administrador','FIX17 - sincronizacao definitiva do administrador')
$text = $text.Replace('FIX16_PREFLIGHT_PUBLICO_PASS','FIX17_PREFLIGHT_PUBLICO_PASS')
$text = $text.Replace('REINO_TRIBAL_ADMIN_FIX16_VALIDADO','REINO_TRIBAL_ADMIN_FIX17_VALIDADO')
$text = $text.Replace('rt-fix16-cors-','rt-fix17-cors-')
$text = $text.Replace('rt-fix16-','rt-fix17-')
$text = $text.Replace("Ok 'FIX15 ValidateOnly concluido; nenhum secret e nenhum deploy foram alterados.'","Ok 'FIX17 ValidateOnly concluido; nenhum secret e nenhum deploy foram alterados.'")

foreach ($needle in @(
  "`$ExecutorVersion = 'FIX17'",
  "`$ExecutorContract = 'ADMIN_AUTHORITY_CORS_CANONICAL'",
  '[switch]$IdentityOnly',
  'REINO_TRIBAL_FIX17_IDENTITY_PASS',
  'REINO_TRIBAL_EXECUTOR_ATIVO.txt',
  "if (`$SelfLeaf -match '(?i)FIX1[56]')",
  '$preflightUrl = $preflightUri.AbsoluteUri',
  'FIX17_PREFLIGHT_PUBLICO_PASS',
  'REINO_TRIBAL_ADMIN_FIX17_VALIDADO'
)) {
  if (-not $text.Contains($needle)) { throw "Contrato FIX17 ausente: $needle" }
}

[IO.File]::WriteAllText($dst,$text,(New-Object Text.UTF8Encoding($false)))
Write-Host 'FIX17_CANONICAL_TRANSFORM_PASS'
