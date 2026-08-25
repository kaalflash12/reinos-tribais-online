param(
  [string]$OutFile = (Join-Path $env:TEMP 'REINO_TRIBAL_FINAL_UNICO_FIX11.ps1'),
  [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'
$sourceUrl = 'https://raw.githubusercontent.com/kaalflash12/reinos-tribais-online/02a43e23f0962c80defae762c20d83b02e4f306b/REINO_TRIBAL_FINAL_UNICO.ps1'
$tmp = Join-Path $env:TEMP ('rt-fix11-' + [Guid]::NewGuid().ToString('N') + '.ps1')

function Replace-Required {
  param([string]$Text,[string]$Old,[string]$New,[string]$Label)
  if ($Text.IndexOf($Old,[StringComparison]::Ordinal) -lt 0) {
    throw "FIX11: trecho obrigatorio nao encontrado: $Label"
  }
  return $Text.Replace($Old,$New)
}

try {
  Invoke-WebRequest -UseBasicParsing -Uri $sourceUrl -OutFile $tmp -TimeoutSec 120
  $content = [IO.File]::ReadAllText($tmp)

  $content = Replace-Required $content `
    "  [string]`$Branch = 'rt-turso-migration'," `
    "  [string]`$Branch = 'main'," `
    'fonte pos-merge deve ser main'

  $oldAdminLine = "  `$adm = Post-Json `"`$backend/api/reino`" @{ action='login'; identifier='reinos_admin'; password=`$adminPassword }"
  $newAdmin = @'
  # Idempotencia: cada execucao pode gerar uma nova credencial ADM. A recovery key
  # publicada no mesmo deploy sincroniza o hash persistido antes de testar o login.
  $admSync = Post-Json "$backend/api/reino" @{ action='admin_recover'; recovery_key=$recoveryKey; password=$adminPassword }
  if (-not $admSync.ok) { Falhar 'Sincronizacao da credencial ADM via recovery key falhou.' }
  Ok 'Credencial ADM sincronizada com o Turso para esta execucao.'
  $adm = Post-Json "$backend/api/reino" @{ action='login'; identifier='reinos_admin'; password=$adminPassword }
'@
  $newAdmin = $newAdmin -replace "`n",[Environment]::NewLine

  $content = Replace-Required $content $oldAdminLine $newAdmin 'sincronizacao ADM antes do login'
  $content = $content.Replace("if (-not `$adm.access_token -or `$adm.user.role -ne 'admin') { Falhar 'Login ADM real falhou.' }","if (-not `$adm.access_token -or `$adm.user.role -ne 'admin') { Falhar 'Login ADM real falhou apos sincronizacao.' }")

  foreach($required in @(
    "[string]`$Branch = 'main'",
    "action='admin_recover'",
    'recovery_key=$recoveryKey',
    'Credencial ADM sincronizada com o Turso para esta execucao.',
    "action='login'; identifier='reinos_admin'; password=`$adminPassword",
    '$pr.mergedAt',
    'Get-TursoHostnameFromInstances',
    '--do-not-use-detected-build-config',
    'package.json',
    'auth/interactive'
  )) {
    if ($content.IndexOf($required,[StringComparison]::Ordinal) -lt 0) {
      throw "FIX11: contrato obrigatorio ausente: $required"
    }
  }

  $recoverPos = $content.IndexOf("action='admin_recover'",[StringComparison]::Ordinal)
  $loginPos = $content.IndexOf("action='login'; identifier='reinos_admin'",[StringComparison]::Ordinal)
  if ($recoverPos -lt 0 -or $loginPos -lt 0 -or $recoverPos -ge $loginPos) {
    throw 'FIX11: admin_recover precisa ocorrer antes do login ADM.'
  }

  $parent = Split-Path $OutFile -Parent
  if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  [IO.File]::WriteAllText($OutFile,$content,(New-Object Text.UTF8Encoding($true)))

  $tokens = $null
  $errors = $null
  [System.Management.Automation.Language.Parser]::ParseFile($OutFile,[ref]$tokens,[ref]$errors) | Out-Null
  if ($errors.Count -gt 0) {
    $errors | Format-List
    throw 'FIX11: executor final nao passou no parser PowerShell.'
  }

  Write-Host "FIX11_VALIDADO: $OutFile" -ForegroundColor Green
  if (-not $ValidateOnly) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $OutFile
    if ($LASTEXITCODE -ne 0) { throw "FIX11: executor final parou com codigo $LASTEXITCODE" }
  }
} finally {
  Remove-Item $tmp -Force -ErrorAction SilentlyContinue
}
