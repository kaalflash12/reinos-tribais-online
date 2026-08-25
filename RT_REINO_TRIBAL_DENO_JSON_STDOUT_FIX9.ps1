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

  $content = Replace-Required $content `
    '    Code = [int]$p.ExitCode' `
    "    Code = [int]`$p.ExitCode`r`n    Stdout = ([string]`$stdout).Trim()`r`n    Stderr = ([string]`$stderr).Trim()" `
    'retorno Executar-Nativo'

  $pairs = @(
    @('$tokenResult.Text.Trim()','$tokenResult.Stdout.Trim()','token GitHub somente stdout'),
    @('$r.Text | ConvertFrom-Json','$r.Stdout | ConvertFrom-Json','checks GitHub JSON'),
    @('$orgList.Text | ConvertFrom-Json','$orgList.Stdout | ConvertFrom-Json','Deno orgs JSON'),
    @('$retryOrgs.Text | ConvertFrom-Json','$retryOrgs.Stdout | ConvertFrom-Json','retry orgs JSON'),
    @('$appInfo.Text | ConvertFrom-Json','$appInfo.Stdout | ConvertFrom-Json','apps get JSON'),
    @('$prView.Text | ConvertFrom-Json','$prView.Stdout | ConvertFrom-Json','PR JSON'),
    @('$last.Text | ConvertFrom-Json','$last.Stdout | ConvertFrom-Json','run list JSON'),
    @('$view.Text | ConvertFrom-Json','$view.Stdout | ConvertFrom-Json','run view JSON'),
    @('$r.Code -eq 0 -and $r.Text','$r.Code -eq 0 -and $r.Stdout','checks condition'),
    @('$retryOrgs.Code -eq 0 -and $retryOrgs.Text','$retryOrgs.Code -eq 0 -and $retryOrgs.Stdout','retry orgs condition'),
    @('$last.Code -eq 0 -and $last.Text','$last.Code -eq 0 -and $last.Stdout','run list condition'),
    @('$view.Code -eq 0 -and $view.Text','$view.Code -eq 0 -and $view.Stdout','run view condition')
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
