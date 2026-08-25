param(
  [string]$OutFile = (Join-Path $env:TEMP 'REINO_TRIBAL_FINAL_UNICO_FIX9.ps1'),
  [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'
$sourceUrl = 'https://raw.githubusercontent.com/kaalflash12/reinos-tribais-online/81f7ff80dcd715ceebcdf64183bbddafad5b9ff4/REINO_TRIBAL_FINAL_UNICO.ps1'
$tmp = Join-Path $env:TEMP ('rt-fix9-' + [Guid]::NewGuid().ToString('N') + '.ps1')

function Replace-Required {
  param([string]$Text,[string]$Old,[string]$New,[string]$Label)
  if ($Text.IndexOf($Old,[StringComparison]::Ordinal) -lt 0) {
    throw "FIX9: trecho obrigatorio nao encontrado: $Label"
  }
  return $Text.Replace($Old,$New)
}

try {
  Invoke-WebRequest -UseBasicParsing -Uri $sourceUrl -OutFile $tmp -TimeoutSec 120
  $content = [IO.File]::ReadAllText($tmp)

  $oldTimeout = @'
      return [pscustomobject]@{ Code = 124; Text = "TIMEOUT após ${TimeoutSec}s: $label"; TimedOut = $true }
'@
  $newTimeout = @'
      return [pscustomobject]@{ Code = 124; Stdout = ''; Stderr = ''; Text = "TIMEOUT após ${TimeoutSec}s: $label"; TimedOut = $true }
'@
  $content = Replace-Required $content $oldTimeout $newTimeout 'timeout com stdout/stderr separados'

  $oldReturn = @'
  return [pscustomobject]@{
    Code = [int]$p.ExitCode
    Text = (($stdout + "`n" + $stderr).Trim())
    TimedOut = $false
  }
'@
  $newReturn = @'
  return [pscustomobject]@{
    Code = [int]$p.ExitCode
    Stdout = ([string]$stdout).Trim()
    Stderr = ([string]$stderr).Trim()
    Text = (($stdout + "`n" + $stderr).Trim())
    TimedOut = $false
  }
'@
  $content = Replace-Required $content $oldReturn $newReturn 'retorno Executar-Nativo'

  $pairs = @(
    @('$githubToken = $tokenResult.Text.Trim()','$githubToken = $tokenResult.Stdout.Trim()','token GitHub somente stdout'),
    @('if ($r.Code -eq 0 -and $r.Text) {`n      try { $checks = @($r.Text | ConvertFrom-Json) } catch { $checks = @() }','if ($r.Code -eq 0 -and $r.Stdout) {`n      try { $checks = @($r.Stdout | ConvertFrom-Json) } catch { $checks = @() }','checks GitHub JSON'),
    @('try { $denoOrgs = @($orgList.Text | ConvertFrom-Json) } catch { Falhar "Deno retornou JSON de organizacoes invalido.`n$($orgList.Text)" }','try { $denoOrgs = @($orgList.Stdout | ConvertFrom-Json) } catch { Falhar "Deno retornou JSON de organizacoes invalido.`nSTDOUT:`n$($orgList.Stdout)`nSTDERR:`n$($orgList.Stderr)" }','Deno orgs JSON'),
    @('if ($retryOrgs.Code -eq 0 -and $retryOrgs.Text) {`n        try { $denoOrgs = @($retryOrgs.Text | ConvertFrom-Json) } catch { $denoOrgs = @() }','if ($retryOrgs.Code -eq 0 -and $retryOrgs.Stdout) {`n        try { $denoOrgs = @($retryOrgs.Stdout | ConvertFrom-Json) } catch { $denoOrgs = @() }','retry orgs JSON'),
    @('try { $appMeta = $appInfo.Text | ConvertFrom-Json } catch { Falhar "apps get retornou JSON invalido.`n$($appInfo.Text)" }','try { $appMeta = $appInfo.Stdout | ConvertFrom-Json } catch { Falhar "apps get retornou JSON invalido.`nSTDOUT:`n$($appInfo.Stdout)`nSTDERR:`n$($appInfo.Stderr)" }','apps get JSON'),
    @('$pr = $prView.Text | ConvertFrom-Json','$pr = $prView.Stdout | ConvertFrom-Json','PR JSON'),
    @('if ($last.Code -eq 0 -and $last.Text) {`n      $runs = @($last.Text | ConvertFrom-Json)','if ($last.Code -eq 0 -and $last.Stdout) {`n      $runs = @($last.Stdout | ConvertFrom-Json)','run list JSON'),
    @('if ($view.Code -eq 0 -and $view.Text) {`n      $obj = $view.Text | ConvertFrom-Json','if ($view.Code -eq 0 -and $view.Stdout) {`n      $obj = $view.Stdout | ConvertFrom-Json','run view JSON')
  )

  foreach($pair in $pairs) {
    $content = Replace-Required $content $pair[0] $pair[1] $pair[2]
  }

  if ($content -notmatch 'Stdout\s*=\s*\(\[string\]\$stdout\)\.Trim\(\)') { throw 'FIX9: Stdout separado nao entrou.' }
  if ($content -notmatch 'Stderr\s*=\s*\(\[string\]\$stderr\)\.Trim\(\)') { throw 'FIX9: Stderr separado nao entrou.' }
  if ($content -match '\$orgList\.Text\s*\|\s*ConvertFrom-Json') { throw 'FIX9: orgList ainda usa Text para JSON.' }
  if ($content -match '\$appInfo\.Text\s*\|\s*ConvertFrom-Json') { throw 'FIX9: appInfo ainda usa Text para JSON.' }
  if ($content -notmatch 'package\.json') { throw 'FIX9: regressao; package.json desapareceu.' }
  if ($content -notmatch 'Get-TursoHostnameFromInstances') { throw 'FIX9: regressao; FIX8 Turso desapareceu.' }
  if ($content -notmatch 'auth/interactive') { throw 'FIX9: regressao; auth Deno desapareceu.' }

  $parent = Split-Path $OutFile -Parent
  if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  [IO.File]::WriteAllText($OutFile,$content,(New-Object Text.UTF8Encoding($true)))

  $tokens = $null
  $errors = $null
  [System.Management.Automation.Language.Parser]::ParseFile($OutFile,[ref]$tokens,[ref]$errors) | Out-Null
  if ($errors.Count -gt 0) {
    $errors | Format-List
    throw 'FIX9: executor final nao passou no parser PowerShell.'
  }

  Write-Host "FIX9_VALIDADO: $OutFile" -ForegroundColor Green
  if (-not $ValidateOnly) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $OutFile
    if ($LASTEXITCODE -ne 0) { throw "FIX9: executor final parou com codigo $LASTEXITCODE" }
  }
} finally {
  Remove-Item $tmp -Force -ErrorAction SilentlyContinue
}
