param([switch]$ValidateOnly)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12

$PinnedFix4C='https://raw.githubusercontent.com/kaalflash12/reinos-tribais-online/41ec0982b2d37f163ea832a907c78130cb4fa118/RT_REINO_TRIBAL_DENO_DEVICE_AUTH_FIX4C.ps1'
$Fix4CPath=Join-Path $env:TEMP 'RT_REINO_TRIBAL_FIX4C_BASE_FIX5.ps1'
$BootstrapFinal=Join-Path $env:TEMP 'IMPLANTAR_REINO_TRIBAL_DENO_TURSO_FINAL.ps1'
$utf8Bom=New-Object Text.UTF8Encoding($true)

Write-Host '=== REINO TRIBAL FIX5 - TURSO DATABASE RESPONSE NORMALIZADA ===' -ForegroundColor Cyan
Write-Host 'Aceita array direto, databases, database, items e data sem quebrar StrictMode.' -ForegroundColor Green

@($Fix4CPath,$BootstrapFinal) | ForEach-Object { Remove-Item $_ -Force -ErrorAction SilentlyContinue }
Invoke-WebRequest -UseBasicParsing -Uri $PinnedFix4C -OutFile $Fix4CPath -TimeoutSec 120
if(-not(Test-Path $Fix4CPath)){throw 'FIX4C validado nao foi baixado.'}
$raw=[IO.File]::ReadAllText($Fix4CPath)
[IO.File]::WriteAllText($Fix4CPath,$raw,$utf8Bom)

$tokens=$null;$errors=$null
[System.Management.Automation.Language.Parser]::ParseFile($Fix4CPath,[ref]$tokens,[ref]$errors)|Out-Null
if($errors.Count){throw ('FIX4C base nao passou no parser: '+(($errors|ForEach-Object{$_.Message}) -join '; '))}

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Fix4CPath -ValidateOnly
if($LASTEXITCODE -ne 0){throw "FIX4C ValidateOnly falhou: $LASTEXITCODE"}
if(-not(Test-Path $BootstrapFinal)){throw 'FIX4C nao gerou bootstrap final.'}

$texto=[IO.File]::ReadAllText($BootstrapFinal).Replace("`r`n","`n")
$dbStartMarker='  $dbList = Turso-Request -Method GET -Path "/v1/organizations/$orgSlug/databases" -Token $platformToken'
$adminMarker="  `$adminPassword = 'RT!' + (Novo-Segredo 30)"
$dbStart=$texto.IndexOf($dbStartMarker,[StringComparison]::Ordinal)
$adminStart=$texto.IndexOf($adminMarker,$dbStart,[StringComparison]::Ordinal)
if($dbStart -lt 0 -or $adminStart -le $dbStart){throw 'Bloco antigo de banco Turso nao foi encontrado para FIX5.'}

$helpers=@'
  function Convert-ToTursoDatabaseList {
    param($Raw)
    if ($null -eq $Raw) { return @() }
    if ($Raw -is [System.Array]) { return @($Raw) }
    if ($Raw.PSObject.Properties['databases']) { return @($Raw.databases) }
    if ($Raw.PSObject.Properties['items']) { return @($Raw.items) }
    if ($Raw.PSObject.Properties['data']) {
      $dataNode = $Raw.data
      if ($null -eq $dataNode) { return @() }
      if ($dataNode -is [System.Array]) { return @($dataNode) }
      if ($dataNode.PSObject.Properties['databases']) { return @($dataNode.databases) }
      if ($dataNode.PSObject.Properties['items']) { return @($dataNode.items) }
      if ($dataNode.PSObject.Properties['database']) { return @($dataNode.database) }
      return @($dataNode)
    }
    if ($Raw.PSObject.Properties['database']) { return @($Raw.database) }
    return @($Raw)
  }

  function Convert-ToTursoDatabase {
    param($Raw)
    $items = @(Convert-ToTursoDatabaseList $Raw)
    return ($items | Select-Object -First 1)
  }

  function Get-TursoDatabaseField {
    param($DatabaseObject,[Parameter(Mandatory=$true)][string]$Name)
    if ($null -eq $DatabaseObject) { return '' }
    $prop = $DatabaseObject.PSObject.Properties | Where-Object { $_.Name -ieq $Name } | Select-Object -First 1
    if (-not $prop) { return '' }
    return [string]$prop.Value
  }

'@
$helpers=$helpers.Replace("`r`n","`n")

$dbNovo=@'
  $dbListRaw = Turso-Request -Method GET -Path "/v1/organizations/$orgSlug/databases" -Token $platformToken
  $dbItems = @(Convert-ToTursoDatabaseList $dbListRaw)
  $db = $dbItems | Where-Object { (Get-TursoDatabaseField $_ 'Name') -eq $TursoDatabase } | Select-Object -First 1

  if (-not $db) {
    $createdRaw = Turso-Request -Method POST -Path "/v1/organizations/$orgSlug/databases" -Token $platformToken -Body @{ name=$TursoDatabase; group=$groupName }
    $db = Convert-ToTursoDatabase $createdRaw
    if (-not $db) { Falhar 'Turso respondeu a criacao do banco sem objeto de database utilizavel.' }
    Ok "Banco Turso criado: $TursoDatabase"
  } else {
    Ok "Banco Turso reutilizado: $TursoDatabase"
  }

  $hostname = Get-TursoDatabaseField $db 'Hostname'
  if (-not $hostname) {
    $detailRaw = Turso-Request -Method GET -Path "/v1/organizations/$orgSlug/databases/$TursoDatabase" -Token $platformToken
    $detailDb = Convert-ToTursoDatabase $detailRaw
    $hostname = Get-TursoDatabaseField $detailDb 'Hostname'
  }
  if (-not $hostname) { Falhar 'Turso nao retornou hostname do banco apos normalizacao da resposta.' }

  $dbUrl = 'libsql://' + ($hostname -replace '^https?://','' -replace '^libsql://','')
  $dbTokenResp = Turso-Request -Method POST -Path "/v1/organizations/$orgSlug/databases/$TursoDatabase/auth/tokens?expiration=never&authorization=full-access" -Token $platformToken -Body @{}
  $dbToken = ''
  if ($dbTokenResp -is [string]) {
    $dbToken = [string]$dbTokenResp
  } elseif ($null -ne $dbTokenResp) {
    $jwtProp = $dbTokenResp.PSObject.Properties | Where-Object { $_.Name -ieq 'jwt' } | Select-Object -First 1
    $tokenProp = $dbTokenResp.PSObject.Properties | Where-Object { $_.Name -ieq 'token' } | Select-Object -First 1
    if ($jwtProp) { $dbToken = [string]$jwtProp.Value }
    elseif ($tokenProp) { $dbToken = [string]$tokenProp.Value }
  }
  if ($dbToken.Length -lt 20) { Falhar 'Turso nao retornou token de banco valido em formato reconhecido.' }
  Ok 'URL e token do banco Turso obtidos sem expor valores.'

'@
$dbNovo=$dbNovo.Replace("`r`n","`n")
$texto=$texto.Substring(0,$dbStart)+$helpers+$dbNovo+$texto.Substring($adminStart)

foreach($forbidden in @(
  '$dbList.databases',
  '$created.database',
  '$detail.database.Hostname'
)){
  if($texto.Contains($forbidden)){throw "FIX5 ainda contem acesso Turso rigido: $forbidden"}
}
foreach($needle in @(
  'function Convert-ToTursoDatabaseList',
  "`$Raw -is [System.Array]",
  "`$Raw.PSObject.Properties['databases']",
  "`$Raw.PSObject.Properties['database']",
  "`$Raw.PSObject.Properties['data']",
  'Get-TursoDatabaseField',
  '$dbListRaw = Turso-Request',
  '$db = Convert-ToTursoDatabase $createdRaw',
  '$detailDb = Convert-ToTursoDatabase $detailRaw',
  "Deno-PostJsonRaw -Url 'https://console.deno.com/auth/interactive'",
  '$env:DENO_DEPLOY_TOKEN = $denoToken'
)){
  if(-not $texto.Contains($needle)){throw "Contrato FIX5 ausente: $needle"}
}

[IO.File]::WriteAllText($BootstrapFinal,$texto,$utf8Bom)
$tokens=$null;$errors=$null
[System.Management.Automation.Language.Parser]::ParseFile($BootstrapFinal,[ref]$tokens,[ref]$errors)|Out-Null
if($errors.Count){throw ('Bootstrap FIX5 nao passou no parser: '+(($errors|ForEach-Object{$_.Message+' @ '+$_.Extent.StartLineNumber+':'+$_.Extent.StartColumnNumber}) -join "`n"))}

# Teste sintético da mesma normalizacao para as formas observadas/aceitas.
$testHelpers=$helpers -replace '^  ',' ' -replace "`n  ","`n"
Invoke-Expression $testHelpers
$sample=[pscustomobject]@{ Name='reino-tribal-prod'; Hostname='sample.turso.io' }
$cases=@(
  @($sample),
  [pscustomobject]@{ databases=@($sample) },
  [pscustomobject]@{ database=$sample },
  [pscustomobject]@{ items=@($sample) },
  [pscustomobject]@{ data=[pscustomobject]@{ databases=@($sample) } }
)
foreach($case in $cases){
  $items=@(Convert-ToTursoDatabaseList $case)
  if($items.Count -ne 1){throw 'FIX5 normalizador sintetico retornou contagem incorreta.'}
  if((Get-TursoDatabaseField $items[0] 'Name') -ne 'reino-tribal-prod'){throw 'FIX5 normalizador sintetico perdeu Name.'}
}

Write-Host 'PASS: TURSO DB = ARRAY DIRETO + DATABASES + DATABASE + ITEMS + DATA NORMALIZADOS.' -ForegroundColor Green
Write-Host 'PASS: TURSO DB = CRIACAO/DETALHE/HOSTNAME/TOKEN NORMALIZADOS.' -ForegroundColor Green
Write-Host 'PASS: DENO DEVICE AUTH FIX4C MANTIDO.' -ForegroundColor Green
Write-Host 'PASS: PARSER FINAL FIX5 VALIDADO.' -ForegroundColor Green

if($ValidateOnly){Write-Host 'TURSO_DB_SHAPE_FIX5_VALIDATE_PASS' -ForegroundColor Green;return}

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $BootstrapFinal
$code=$LASTEXITCODE
if($code -ne 0){throw "FIX5 parou no proximo erro real. Codigo: $code"}
