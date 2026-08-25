$ErrorActionPreference = 'Stop'
$src = Join-Path $PSScriptRoot 'REINO_TRIBAL_ADMIN_FIX16_FINAL.ps1'
$dst = Join-Path $PSScriptRoot 'REINO_TRIBAL_ADMIN_FIX17_FINAL.ps1'
if (-not (Test-Path $src)) { throw 'FIX16 final nao encontrado.' }
$text = [IO.File]::ReadAllText($src).Replace("`r`n","`n")

$oldCred = "$CredFile = Join-Path `$CredDir 'CREDENCIAIS_ADMIN_REINO_TRIBAL.txt'"
$newCred = "$CredFile = Join-Path `$CredDir 'CREDENCIAIS_ADMIN_REINO_TRIBAL.txt'`n`$PendingCredFile = Join-Path `$CredDir 'CREDENCIAIS_ADMIN_REINO_TRIBAL_PENDENTE.txt'"
if (-not $text.Contains($oldCred)) { throw 'Linha CredFile nao encontrada.' }
$text = $text.Replace($oldCred,$newCred)

$oldGen = @'
  $adminPassword = 'RT!' + (Novo-Segredo 30)
  $recoveryKey = Novo-Segredo 48

  Etapa 'Atualizando autoridade ADM no Deno'
'@
$oldGen = $oldGen.TrimEnd("`r","`n")
$newGen = @'
  $adminPassword = 'RT!' + (Novo-Segredo 30)
  $recoveryKey = Novo-Segredo 48

  New-Item -ItemType Directory -Force -Path $CredDir | Out-Null
  $pendingCred = @(
    'REINO TRIBAL - CREDENCIAIS ADMINISTRATIVAS PENDENTES',
    ('Gerado em: ' + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')),
    ('Backend FIX15: ' + $BackendCommit),
    ('Backend: ' + $Backend),
    'Usuario ADM: reinos_admin',
    ('Senha ADM: ' + $adminPassword),
    ('Recovery Key: ' + $recoveryKey),
    'ESTADO: PENDENTE - pode tornar-se ativa assim que os secrets forem atualizados no Deno.'
  ) -join [Environment]::NewLine
  [IO.File]::WriteAllText($PendingCredFile,$pendingCred,(New-Object Text.UTF8Encoding($true)))
  Ok "Credencial PENDENTE preservada antes de alterar Deno: $PendingCredFile"

  Etapa 'Atualizando autoridade ADM no Deno'
'@
$newGen = $newGen.TrimEnd("`r","`n")
if (-not $text.Contains($oldGen)) { throw 'Bloco de geracao de senha FIX16 nao encontrado.' }
$text = $text.Replace($oldGen,$newGen)

$oldWrite = '[IO.File]::WriteAllText($CredFile,$cred,(New-Object Text.UTF8Encoding($true)))'
$newWrite = $oldWrite + "`n  Remove-Item `$PendingCredFile -Force -ErrorAction SilentlyContinue"
if (-not $text.Contains($oldWrite)) { throw 'Gravacao final de credencial nao encontrada.' }
$text = $text.Replace($oldWrite,$newWrite)

$text = $text.Replace('FIX16 - teste publico isolado de CORS','FIX17 - teste publico isolado de CORS')
$text = $text.Replace('FIX16_PREFLIGHT_PUBLICO_PASS','FIX17_PREFLIGHT_PUBLICO_PASS')
$text = $text.Replace('FIX16 - sincronizacao definitiva do administrador','FIX17 - sincronizacao definitiva do administrador')
$text = $text.Replace('REINO_TRIBAL_ADMIN_FIX16_VALIDADO','REINO_TRIBAL_ADMIN_FIX17_VALIDADO')
$text = $text.Replace('rt-fix16-','rt-fix17-')

foreach ($needle in @(
  'CREDENCIAIS_ADMIN_REINO_TRIBAL_PENDENTE.txt',
  'Credencial PENDENTE preservada antes de alterar Deno',
  'ESTADO: PENDENTE',
  'Remove-Item $PendingCredFile -Force -ErrorAction SilentlyContinue',
  'REINO_TRIBAL_ADMIN_FIX17_VALIDADO'
)) {
  if (-not $text.Contains($needle)) { throw "Contrato FIX17 ausente: $needle" }
}

$iPending = $text.IndexOf('[IO.File]::WriteAllText($PendingCredFile')
$iUpdate = $text.IndexOf("'deploy','env','update-value','RT_ADMIN_PASSWORD'")
$iFinal = $text.IndexOf('[IO.File]::WriteAllText($CredFile,$cred')
$iRemove = $text.IndexOf('Remove-Item $PendingCredFile -Force')
if ($iPending -lt 0 -or $iUpdate -lt 0 -or $iFinal -lt 0 -or $iRemove -lt 0 -or -not ($iPending -lt $iUpdate -and $iUpdate -lt $iFinal -and $iFinal -lt $iRemove)) {
  throw 'Ordem FIX17 invalida: pending -> update Deno -> credencial valida -> remover pending.'
}

[IO.File]::WriteAllText($dst,$text,(New-Object Text.UTF8Encoding($false)))
Write-Host 'FIX17_PENDING_CREDENTIAL_TRANSFORM_PASS'
