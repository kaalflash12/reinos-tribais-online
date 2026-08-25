$ErrorActionPreference = 'Stop'
$src = Join-Path $PSScriptRoot 'REINO_TRIBAL_ADMIN_FIX16_FINAL.ps1'
$dst = Join-Path $PSScriptRoot 'REINO_TRIBAL_ADMIN_FIX17_FINAL.ps1'
if (-not (Test-Path $src)) { throw 'FIX16 final nao encontrado.' }
$text = [IO.File]::ReadAllText($src).Replace("`r`n","`n")

# Acrescenta modo isolado para testar o estado transacional sem tocar em Deno/Turso.
$paramOld = "  [switch]`$ValidateOnly,`n  [switch]`$PreflightOnly`n)"
$paramNew = "  [switch]`$ValidateOnly,`n  [switch]`$PreflightOnly,`n  [switch]`$StateOnly`n)"
if (-not $text.Contains($paramOld)) { throw 'Parametros FIX16 nao encontrados.' }
$text = $text.Replace($paramOld,$paramNew)

$anchor = "`$CredFile = Join-Path `$CredDir 'CREDENCIAIS_ADMIN_REINO_TRIBAL.txt'`n"
$insert = @'
$ExecutorId = 'RT-ADMIN-FIX17'
$StateDir = Join-Path $env:LOCALAPPDATA 'ReinoTribal'
$StateFile = Join-Path $StateDir 'ADMIN_FIX17_STATE.json'
$CurrentScriptPath = [IO.Path]::GetFullPath($MyInvocation.MyCommand.Path)
foreach ($legacy in @(
  (Join-Path $env:TEMP 'RT_ADMIN_FIX15.ps1'),
  (Join-Path $env:TEMP 'RT_ADMIN_FIX16.ps1'),
  (Join-Path $env:TEMP 'RT_ADMIN_FIX15_FINAL.ps1'),
  (Join-Path $env:TEMP 'RT_FIX14.ps1')
)) {
  try {
    if (Test-Path $legacy) {
      $legacyFull = [IO.Path]::GetFullPath($legacy)
      if ($legacyFull -ne $CurrentScriptPath) { Remove-Item $legacyFull -Force -ErrorAction SilentlyContinue }
    }
  } catch {}
}
Write-Host ("EXECUTOR: " + $ExecutorId) -ForegroundColor Cyan
Write-Host ("EXECUTOR PATH: " + $CurrentScriptPath) -ForegroundColor DarkGray
Write-Host ("BACKEND PIN: " + $BackendCommit) -ForegroundColor DarkGray
'@
$insert = $insert.TrimEnd("`r","`n") + "`n"
if (-not $text.Contains($anchor)) { throw 'Ancora CredFile nao encontrada.' }
$text = $text.Replace($anchor,$anchor + $insert)

# Estado transacional protegido diretamente pela DPAPI do Windows (CurrentUser).
$fnAnchor = "function Parse-JsonResult(`$Result,[string]`$Label) {`n"
$stateFns = @'
function Protect-LocalText([string]$Plain) {
  $bytes = [Text.Encoding]::UTF8.GetBytes($Plain)
  $protected = [Security.Cryptography.ProtectedData]::Protect(
    $bytes,
    $null,
    [Security.Cryptography.DataProtectionScope]::CurrentUser
  )
  return [Convert]::ToBase64String($protected)
}

function Unprotect-LocalText([string]$Cipher) {
  $protected = [Convert]::FromBase64String($Cipher)
  $bytes = [Security.Cryptography.ProtectedData]::Unprotect(
    $protected,
    $null,
    [Security.Cryptography.DataProtectionScope]::CurrentUser
  )
  return [Text.Encoding]::UTF8.GetString($bytes)
}

function Get-OrCreateAdminState {
  New-Item -ItemType Directory -Force -Path $StateDir | Out-Null
  if (Test-Path $StateFile) {
    try {
      $saved = [IO.File]::ReadAllText($StateFile) | ConvertFrom-Json
      if ([string]$saved.backendCommit -eq $BackendCommit) {
        $p = Unprotect-LocalText ([string]$saved.passwordProtected)
        $r = Unprotect-LocalText ([string]$saved.recoveryProtected)
        if ($p.Length -ge 12 -and $r.Length -ge 24) {
          Ok 'Estado ADM transacional existente reutilizado; nenhuma senha nova foi criada.'
          return [pscustomobject]@{ Password=$p; RecoveryKey=$r; Reused=$true }
        }
      }
    } catch {
      Write-Host ("Estado ADM existente invalido: " + $_.Exception.Message) -ForegroundColor DarkYellow
    }
    Remove-Item $StateFile -Force -ErrorAction SilentlyContinue
  }

  $p = 'RT!' + (Novo-Segredo 30)
  $r = Novo-Segredo 48
  $state = [ordered]@{
    executor = $ExecutorId
    backendCommit = $BackendCommit
    createdAt = (Get-Date).ToString('o')
    passwordProtected = Protect-LocalText $p
    recoveryProtected = Protect-LocalText $r
  } | ConvertTo-Json -Depth 10
  [IO.File]::WriteAllText($StateFile,$state,(New-Object Text.UTF8Encoding($false)))
  try { (Get-Item $StateFile).Attributes = (Get-Item $StateFile).Attributes -bor [IO.FileAttributes]::Hidden } catch {}
  Ok 'Estado ADM transacional criado e protegido pela DPAPI antes de qualquer alteracao remota.'
  return [pscustomobject]@{ Password=$p; RecoveryKey=$r; Reused=$false }
}

function Clear-AdminState {
  Remove-Item $StateFile -Force -ErrorAction SilentlyContinue
}

'@
$stateFns = $stateFns.Replace("`r`n","`n")
if (-not $text.Contains($fnAnchor)) { throw 'Ancora Parse-JsonResult nao encontrada.' }
$text = $text.Replace($fnAnchor,$stateFns + $fnAnchor)

# Testa o estado transacional de forma isolada.
$preflightAnchor = "if (`$PreflightOnly) {`n"
$stateMode = @'
if ($StateOnly) {
  Etapa 'FIX17 - teste isolado do estado ADM transacional'
  $s1 = Get-OrCreateAdminState
  $s2 = Get-OrCreateAdminState
  if ($s1.Password -ne $s2.Password -or $s1.RecoveryKey -ne $s2.RecoveryKey) { Falhar 'Estado transacional nao foi reutilizado de forma deterministica.' }
  if (-not $s2.Reused) { Falhar 'Segunda leitura do estado nao foi marcada como reutilizada.' }
  Clear-AdminState
  Ok 'FIX17_STATE_TRANSACTION_PASS'
  return
}

'@
$stateMode = $stateMode.Replace("`r`n","`n")
if (-not $text.Contains($preflightAnchor)) { throw 'Bloco PreflightOnly nao encontrado.' }
$text = $text.Replace($preflightAnchor,$stateMode + $preflightAnchor)

# O preflight publico ocorre antes de autenticar no Deno ou alterar secrets.
$beforeAuth = "  Garantir-DenoAuth`n"
$preBeforeAuth = @'
  Etapa 'Preflight publico antes de alterar credenciais'
  Testar-Preflight
  Ok 'Preflight publico passou antes de qualquer alteracao de secret.'

  Garantir-DenoAuth
'@
$preBeforeAuth = $preBeforeAuth.Replace("`r`n","`n")
if (-not $text.Contains($beforeAuth)) { throw 'Chamada Garantir-DenoAuth nao encontrada.' }
$text = $text.Replace($beforeAuth,$preBeforeAuth)

# Senha/recovery passam a vir do estado transacional protegido e reutilizavel.
$secretOld = "  `$adminPassword = 'RT!' + (Novo-Segredo 30)`n  `$recoveryKey = Novo-Segredo 48`n"
$secretNew = @'
  $adminState = Get-OrCreateAdminState
  $adminPassword = [string]$adminState.Password
  $recoveryKey = [string]$adminState.RecoveryKey
  Ok 'Credencial ADM transacional carregada; reruns reutilizarao a mesma senha ate validacao final.'
'@
$secretNew = $secretNew.Replace("`r`n","`n").TrimEnd("`n") + "`n"
if (-not $text.Contains($secretOld)) { throw 'Geracao de senha FIX16 nao encontrada.' }
$text = $text.Replace($secretOld,$secretNew)

# Limpa o estado somente depois que login + admin_status + dashboard passaram e a credencial final foi gravada.
$afterCred = "  [IO.File]::WriteAllText(`$CredFile,`$cred,(New-Object Text.UTF8Encoding(`$true)))`n"
$afterCredNew = $afterCred + "  Clear-AdminState`n"
if (-not $text.Contains($afterCred)) { throw 'Gravacao CredFile nao encontrada.' }
$text = $text.Replace($afterCred,$afterCredNew)

$text = $text.Replace("Join-Path `$env:TEMP ('reino-tribal-admin-fix15-'","Join-Path `$env:TEMP ('reino-tribal-admin-fix17-'")
$text = $text.Replace('FIX16 - teste publico isolado de CORS','FIX17 - teste publico isolado de CORS')
$text = $text.Replace('FIX16_PREFLIGHT_PUBLICO_PASS','FIX17_PREFLIGHT_PUBLICO_PASS')
$text = $text.Replace('FIX16 - sincronizacao definitiva do administrador','FIX17 - sincronizacao definitiva do administrador')
$text = $text.Replace('REINO_TRIBAL_ADMIN_FIX16_VALIDADO','REINO_TRIBAL_ADMIN_FIX17_VALIDADO')
$text = $text.Replace('FIX15 ValidateOnly concluido','FIX17 ValidateOnly concluido')

foreach ($needle in @(
  "`$ExecutorId = 'RT-ADMIN-FIX17'",
  '[switch]$StateOnly',
  'ADMIN_FIX17_STATE.json',
  '[Security.Cryptography.ProtectedData]::Protect',
  'FIX17_STATE_TRANSACTION_PASS',
  'Preflight publico antes de alterar credenciais',
  '$adminState = Get-OrCreateAdminState',
  'Clear-AdminState',
  'REINO_TRIBAL_ADMIN_FIX17_VALIDADO'
)) {
  if (-not $text.Contains($needle)) { throw "Contrato FIX17 ausente: $needle" }
}

[IO.File]::WriteAllText($dst,$text,(New-Object Text.UTF8Encoding($false)))
Write-Host 'FIX17_TRANSFORM_PASS'
