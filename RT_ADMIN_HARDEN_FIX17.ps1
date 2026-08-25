$ErrorActionPreference = 'Stop'
$src = Join-Path $PSScriptRoot 'REINO_TRIBAL_ADMIN_FIX16_FINAL.ps1'
$dst = Join-Path $PSScriptRoot 'REINO_TRIBAL_ADMIN_FIX17_FINAL.ps1'
if (-not (Test-Path $src)) { throw 'FIX16 final nao encontrado.' }
$text = [IO.File]::ReadAllText($src).Replace("`r`n","`n")

$anchor = "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12`n"
$insert = @'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$ExecutorBuild = 'REINO_TRIBAL_ADMIN_FIX17_FINAL'
$ExecutorBackendCommit = 'd5d1edadd9f33b612a233c4feed0e06ec97203bc'
$SelfPath = [string]$MyInvocation.MyCommand.Path
$SelfSha256 = if ($SelfPath -and (Test-Path $SelfPath)) { (Get-FileHash -Algorithm SHA256 -LiteralPath $SelfPath).Hash.ToLowerInvariant() } else { '' }
$legacyNames = @(
  'RT_ADMIN_FIX15.ps1',
  'RT_ADMIN_FIX16.ps1',
  'RT_ADMIN_FIX16_be58d645.ps1',
  'REINO_TRIBAL_ADMIN_FIX15_FINAL.ps1',
  'REINO_TRIBAL_ADMIN_FIX16_FINAL.ps1'
)
foreach ($legacyName in $legacyNames) {
  $legacyPath = Join-Path $env:TEMP $legacyName
  try {
    if (Test-Path $legacyPath) {
      $sameAsSelf = $false
      if ($SelfPath) {
        try { $sameAsSelf = ([IO.Path]::GetFullPath($legacyPath) -eq [IO.Path]::GetFullPath($SelfPath)) } catch {}
      }
      if (-not $sameAsSelf) { Remove-Item -LiteralPath $legacyPath -Force -ErrorAction Stop }
    }
  } catch { throw "Nao foi possivel remover executor legado do TEMP: $legacyPath. $($_.Exception.Message)" }
}
Write-Host ("EXECUTOR: " + $ExecutorBuild) -ForegroundColor Cyan
Write-Host ("EXECUTOR SHA256: " + $SelfSha256) -ForegroundColor DarkGray
Write-Host ("BACKEND PINADO: " + $ExecutorBackendCommit) -ForegroundColor DarkGray
Write-Host 'PASS: executores FIX15/FIX16 legados removidos do TEMP.' -ForegroundColor Green
'@
$insert = $insert.TrimEnd("`r","`n") + "`n"
if (-not $text.Contains($anchor)) { throw 'Ancora TLS do FIX16 nao encontrada.' }
$text = $text.Replace($anchor,$insert)

$text = $text.Replace("reino-tribal-admin-fix15-","reino-tribal-admin-fix17-")
$text = $text.Replace("rt-fix16-","rt-fix17-")
$text = $text.Replace("REINO_TRIBAL_ADMIN_FIX16_VALIDADO","REINO_TRIBAL_ADMIN_FIX17_VALIDADO")
$text = $text.Replace("Etapa 'FIX16 - sincronizacao definitiva do administrador'","Etapa 'FIX17 - sincronizacao definitiva do administrador'")
$text = $text.Replace("FIX16_PREFLIGHT_PUBLICO_PASS","FIX17_PREFLIGHT_PUBLICO_PASS")
$text = $text.Replace("Etapa 'FIX16 - teste publico isolado de CORS'","Etapa 'FIX17 - teste publico isolado de CORS'")

foreach ($needle in @(
  "`$ExecutorBuild = 'REINO_TRIBAL_ADMIN_FIX17_FINAL'",
  'EXECUTOR SHA256:',
  'PASS: executores FIX15/FIX16 legados removidos do TEMP.',
  'RT_ADMIN_FIX15.ps1',
  'RT_ADMIN_FIX16.ps1',
  '$preflightUrl = $preflightUri.AbsoluteUri',
  'FIX17_PREFLIGHT_PUBLICO_PASS',
  'REINO_TRIBAL_ADMIN_FIX17_VALIDADO',
  "[string]`$BackendCommit = 'd5d1edadd9f33b612a233c4feed0e06ec97203bc'"
)) {
  if (-not $text.Contains($needle)) { throw "Contrato FIX17 ausente: $needle" }
}

[IO.File]::WriteAllText($dst,$text,(New-Object Text.UTF8Encoding($false)))
Write-Host 'FIX17_TRANSFORM_PASS'
