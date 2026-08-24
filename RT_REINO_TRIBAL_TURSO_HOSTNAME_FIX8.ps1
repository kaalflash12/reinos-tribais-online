param(
  [string]$OutFile = (Join-Path $env:TEMP 'REINO_TRIBAL_FINAL_UNICO_FIX8.ps1'),
  [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'
$sourceUrl = 'https://raw.githubusercontent.com/kaalflash12/reinos-tribais-online/f6a5ab1299e4b48df112ad2738f3c6baa68e0062/REINO_TRIBAL_FINAL_UNICO.ps1'
$tmp = Join-Path $env:TEMP ('rt-fix8-' + [Guid]::NewGuid().ToString('N') + '.ps1')

try {
  Invoke-WebRequest -UseBasicParsing -Uri $sourceUrl -OutFile $tmp -TimeoutSec 120
  $content = [IO.File]::ReadAllText($tmp)

  $startMarker = "  `$hostname = Get-TursoDatabaseField `$db 'Hostname'"
  $endMarker = "  `$dbUrl = 'libsql://' + (`$hostname -replace '^https?://','' -replace '^libsql://','')"

  $start = $content.IndexOf($startMarker,[StringComparison]::Ordinal)
  if ($start -lt 0) { throw 'FIX8: inicio do bloco hostname nao encontrado no executor pinado.' }
  $end = $content.IndexOf($endMarker,$start,[StringComparison]::Ordinal)
  if ($end -lt 0) { throw 'FIX8: fim do bloco hostname nao encontrado no executor pinado.' }
  $end += $endMarker.Length

  $replacement = @'
  function Get-TursoHostnameFromInstances {
    param($Raw)
    if ($null -eq $Raw) { return '' }

    $instances = @()
    if ($Raw -is [System.Array]) {
      $instances = @($Raw)
    } elseif ($Raw.PSObject.Properties['instances']) {
      $instances = @($Raw.instances)
    } elseif ($Raw.PSObject.Properties['data']) {
      $dataNode = $Raw.data
      if ($null -ne $dataNode) {
        if ($dataNode -is [System.Array]) {
          $instances = @($dataNode)
        } elseif ($dataNode.PSObject.Properties['instances']) {
          $instances = @($dataNode.instances)
        } elseif ($dataNode.PSObject.Properties['instance']) {
          $instances = @($dataNode.instance)
        }
      }
    } elseif ($Raw.PSObject.Properties['instance']) {
      $instances = @($Raw.instance)
    }

    $instances = @($instances | Where-Object { $null -ne $_ })
    if ($instances.Count -lt 1) { return '' }

    $candidate = $instances | Where-Object {
      $typeProp = $_.PSObject.Properties | Where-Object { $_.Name -ieq 'type' } | Select-Object -First 1
      $typeProp -and ([string]$typeProp.Value) -ieq 'primary'
    } | Select-Object -First 1
    if (-not $candidate) { $candidate = $instances | Select-Object -First 1 }
    if (-not $candidate) { return '' }

    $hostnameProp = $candidate.PSObject.Properties | Where-Object { $_.Name -ieq 'hostname' } | Select-Object -First 1
    if (-not $hostnameProp) { return '' }
    return ([string]$hostnameProp.Value).Trim()
  }

  $hostname = Get-TursoDatabaseField $db 'Hostname'
  if (-not $hostname) {
    $detailRaw = Turso-Request -Method GET -Path "/v1/organizations/$orgSlug/databases/$TursoDatabase" -Token $platformToken
    $detailDb = Convert-ToTursoDatabase $detailRaw
    $hostname = Get-TursoDatabaseField $detailDb 'Hostname'
  }

  if (-not $hostname) {
    $instancesRaw = Turso-Request -Method GET -Path "/v1/organizations/$orgSlug/databases/$TursoDatabase/instances" -Token $platformToken
    $hostname = Get-TursoHostnameFromInstances $instancesRaw
    if ($hostname) { Ok "Hostname Turso obtido pela instancia primaria: $hostname" }
  }

  if (-not $hostname) {
    Falhar 'Turso nao retornou hostname nem no detalhe do database nem na lista de instances.'
  }

  $dbUrl = 'libsql://' + ($hostname -replace '^https?://','' -replace '^libsql://','')
'@

  $patched = $content.Substring(0,$start) + $replacement + $content.Substring($end)

  if ($patched -notmatch '/instances') { throw 'FIX8: fallback /instances nao entrou no script.' }
  if ($patched -notmatch 'Get-TursoHostnameFromInstances') { throw 'FIX8: helper de hostname nao entrou no script.' }
  if ($patched -notmatch 'package\.json') { throw 'FIX8: regressao detectada; package.json desapareceu.' }
  if ($patched -notmatch 'auth/interactive') { throw 'FIX8: regressao detectada; auth Deno desapareceu.' }

  $parent = Split-Path $OutFile -Parent
  if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  [IO.File]::WriteAllText($OutFile,$patched,(New-Object Text.UTF8Encoding($true)))

  $tokens = $null
  $errors = $null
  [System.Management.Automation.Language.Parser]::ParseFile($OutFile,[ref]$tokens,[ref]$errors) | Out-Null
  if ($errors.Count -gt 0) {
    $errors | Format-List
    throw 'FIX8: executor final nao passou no parser PowerShell.'
  }

  Write-Host "FIX8_VALIDADO: $OutFile" -ForegroundColor Green
  if (-not $ValidateOnly) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $OutFile
    if ($LASTEXITCODE -ne 0) { throw "FIX8: executor final parou com codigo $LASTEXITCODE" }
  }
} finally {
  Remove-Item $tmp -Force -ErrorAction SilentlyContinue
}
