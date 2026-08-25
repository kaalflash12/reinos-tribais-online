param(
  [string]$OutFile = (Join-Path $env:TEMP 'REINO_TRIBAL_FINAL_UNICO_FIX10.ps1'),
  [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'
$sourceUrl = 'https://raw.githubusercontent.com/kaalflash12/reinos-tribais-online/14375557e741d6bd9144f53cfb488869bfac30a6/REINO_TRIBAL_FINAL_UNICO.ps1'
$tmp = Join-Path $env:TEMP ('rt-fix10-' + [Guid]::NewGuid().ToString('N') + '.ps1')

function Replace-Required {
  param([string]$Text,[string]$Old,[string]$New,[string]$Label)
  if ($Text.IndexOf($Old,[StringComparison]::Ordinal) -lt 0) {
    throw "FIX10: trecho obrigatorio nao encontrado: $Label"
  }
  return $Text.Replace($Old,$New)
}

try {
  Invoke-WebRequest -UseBasicParsing -Uri $sourceUrl -OutFile $tmp -TimeoutSec 120
  $content = [IO.File]::ReadAllText($tmp)

  $marker = "  `$workPath = `$repoDir`r`n"
  if ($content.IndexOf($marker,[StringComparison]::Ordinal) -lt 0) {
    $marker = "  `$workPath = `$repoDir`n"
  }
  if ($content.IndexOf($marker,[StringComparison]::Ordinal) -lt 0) {
    throw 'FIX10: marcador workPath nao encontrado.'
  }

  $guard = @'
  $workPath = $repoDir
  $denoConfigPath = Join-Path $workPath 'deno.json'
  try {
    $denoConfig = Get-Content -Raw -Path $denoConfigPath | ConvertFrom-Json
  } catch {
    Falhar "deno.json invalido antes do deploy: $($_.Exception.Message)"
  }
  if ($denoConfig.PSObject.Properties['deploy']) {
    $denoConfig.PSObject.Properties.Remove('deploy')
    $denoConfigText = $denoConfig | ConvertTo-Json -Depth 50
    [IO.File]::WriteAllText($denoConfigPath,$denoConfigText,(New-Object Text.UTF8Encoding($false)))
    Ok 'Bloco deploy removido do deno.json local; Deno Deploy sera configurado exclusivamente por flags --org/--app/runtime.'
  } else {
    Ok 'deno.json local sem bloco deploy conflitante; configuracao Deno Deploy sera feita exclusivamente por flags.'
  }
'@
  $guard = $guard -replace "`n",[Environment]::NewLine
  $content = $content.Replace($marker,$guard + [Environment]::NewLine)

  $content = Replace-Required $content `
    "      '--source','local'," `
    "      '--source','local',`r`n      '--do-not-use-detected-build-config'," `
    'create Deno sem auto-detect/source deploy config'

  foreach($required in @(
    "PSObject.Properties.Remove('deploy')",
    '--do-not-use-detected-build-config',
    '$orgList.Stdout | ConvertFrom-Json',
    'Get-TursoHostnameFromInstances',
    'package.json',
    'auth/interactive'
  )) {
    if ($content.IndexOf($required,[StringComparison]::Ordinal) -lt 0) {
      throw "FIX10: contrato obrigatorio ausente: $required"
    }
  }

  $parent = Split-Path $OutFile -Parent
  if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  [IO.File]::WriteAllText($OutFile,$content,(New-Object Text.UTF8Encoding($true)))

  $tokens = $null
  $errors = $null
  [System.Management.Automation.Language.Parser]::ParseFile($OutFile,[ref]$tokens,[ref]$errors) | Out-Null
  if ($errors.Count -gt 0) {
    $errors | Format-List
    throw 'FIX10: executor final nao passou no parser PowerShell.'
  }

  Write-Host "FIX10_VALIDADO: $OutFile" -ForegroundColor Green
  if (-not $ValidateOnly) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $OutFile
    if ($LASTEXITCODE -ne 0) { throw "FIX10: executor final parou com codigo $LASTEXITCODE" }
  }
} finally {
  Remove-Item $tmp -Force -ErrorAction SilentlyContinue
}
