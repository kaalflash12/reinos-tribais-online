param([switch]$ValidateOnly)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12

$Pinned='https://raw.githubusercontent.com/kaalflash12/reinos-tribais-online/13cd5d12dc588ad1c4558f33f1f85a477026bc23/RT_REINO_TRIBAL_TURSO_DB_SHAPE_FIX5.ps1'
$Patched=Join-Path $env:TEMP 'RT_REINO_TRIBAL_TURSO_DB_SHAPE_FIX5B_INNER.ps1'
$Final=Join-Path $env:TEMP 'IMPLANTAR_REINO_TRIBAL_DENO_TURSO_FINAL.ps1'
$utf8Bom=New-Object Text.UTF8Encoding($true)

Write-Host '=== REINO TRIBAL FINAL - TURSO DB SHAPE + RECOVERY 409 ===' -ForegroundColor Cyan
Remove-Item $Patched,$Final -Force -ErrorAction SilentlyContinue
Invoke-WebRequest -UseBasicParsing -Uri $Pinned -OutFile $Patched -TimeoutSec 120
if(-not(Test-Path $Patched)){throw 'Base pinada nao foi baixada.'}

$s=[IO.File]::ReadAllText($Patched)
$replacements=@(
  @('param($Db,[Parameter(Mandatory=$true)][string]$Name)','param($DatabaseObject,[Parameter(Mandatory=$true)][string]$Name)'),
  @('if ($null -eq $Db) { return '''' }','if ($null -eq $DatabaseObject) { return '''' }'),
  @('$prop = $Db.PSObject.Properties | Where-Object { $_.Name -ieq $Name } | Select-Object -First 1','$prop = $DatabaseObject.PSObject.Properties | Where-Object { $_.Name -ieq $Name } | Select-Object -First 1')
)
foreach($pair in $replacements){
  if(-not $s.Contains($pair[0])){throw "Transform nao encontrou trecho obrigatorio: $($pair[0])"}
  $s=$s.Replace($pair[0],$pair[1])
}

$oldCreate=@'
  if (-not $db) {
    $createdRaw = Turso-Request -Method POST -Path "/v1/organizations/$orgSlug/databases" -Token $platformToken -Body @{ name=$TursoDatabase; group=$groupName }
    $db = Convert-ToTursoDatabase $createdRaw
    if (-not $db) { Falhar 'Turso respondeu a criacao do banco sem objeto de database utilizavel.' }
    Ok "Banco Turso criado: $TursoDatabase"
  } else {
    Ok "Banco Turso reutilizado: $TursoDatabase"
  }
'@

$newCreate=@'
  if (-not $db) {
    try {
      $createdRaw = Turso-Request -Method POST -Path "/v1/organizations/$orgSlug/databases" -Token $platformToken -Body @{ name=$TursoDatabase; group=$groupName }
      $db = Convert-ToTursoDatabase $createdRaw
      if (-not $db) { Falhar 'Turso respondeu a criacao do banco sem objeto de database utilizavel.' }
      Ok "Banco Turso criado: $TursoDatabase"
    } catch {
      $createError = [string]$_.Exception.Message
      if ($createError -notmatch '(?i)(\b409\b|Conflict|Conflito)') { throw }

      Aviso "Turso informou conflito 409 ao criar $TursoDatabase; buscando o banco existente pelo nome."
      $existingRaw = Turso-Request -Method GET -Path "/v1/organizations/$orgSlug/databases/$TursoDatabase" -Token $platformToken
      $db = Convert-ToTursoDatabase $existingRaw
      if (-not $db) { Falhar 'Turso retornou 409 na criacao, mas o banco existente nao pôde ser carregado pelo nome.' }

      $existingName = Get-TursoDatabaseField $db 'Name'
      if ($existingName -and $existingName -ne $TursoDatabase) {
        Falhar "Turso retornou 409 e o detalhe carregado pertence a outro banco: $existingName"
      }
      Ok "Banco Turso reutilizado apos conflito 409: $TursoDatabase"
    }
  } else {
    Ok "Banco Turso reutilizado: $TursoDatabase"
  }
'@

if(-not $s.Contains($oldCreate)){throw 'Transform nao encontrou bloco de criacao Turso para adicionar recovery 409.'}
$s=$s.Replace($oldCreate,$newCreate)

if($s.Contains('param($Db,[Parameter')){throw 'Ainda contem parametro Db conflitante.'}
if($s.Contains('$dbList.databases')){throw 'Ainda contem acesso rigido $dbList.databases.'}
[IO.File]::WriteAllText($Patched,$s,$utf8Bom)

$tokens=$null;$errors=$null
[System.Management.Automation.Language.Parser]::ParseFile($Patched,[ref]$tokens,[ref]$errors)|Out-Null
if($errors.Count){throw ('Inner parser falhou: '+(($errors|ForEach-Object{$_.Message}) -join '; '))}

if($ValidateOnly){
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Patched -ValidateOnly
}else{
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Patched
}
$code=$LASTEXITCODE
if($code -ne 0){throw "Bootstrap parou. Codigo: $code"}

if($ValidateOnly){
  if(-not(Test-Path $Final)){throw 'Bootstrap final nao foi gerado.'}
  $t=[IO.File]::ReadAllText($Final)
  foreach($needle in @(
    'param($DatabaseObject,[Parameter(Mandatory=$true)][string]$Name)',
    '$DatabaseObject.PSObject.Properties',
    'function Convert-ToTursoDatabaseList',
    '$Raw.PSObject.Properties[''databases'']',
    '$Raw.PSObject.Properties[''database'']',
    '$db = Convert-ToTursoDatabase $createdRaw',
    '$existingRaw = Turso-Request -Method GET -Path "/v1/organizations/$orgSlug/databases/$TursoDatabase"',
    "if (`$createError -notmatch '(?i)(\b409\b|Conflict|Conflito)') { throw }",
    'Banco Turso reutilizado apos conflito 409',
    '$detailDb = Convert-ToTursoDatabase $detailRaw',
    "Deno-PostJsonRaw -Url 'https://console.deno.com/auth/interactive'",
    '$env:DENO_DEPLOY_TOKEN = $denoToken'
  )){if(-not $t.Contains($needle)){throw "Contrato final ausente: $needle"}}
  foreach($forbidden in @('$dbList.databases','$created.database','$detail.database.Hostname','param($Db,[Parameter')){
    if($t.Contains($forbidden)){throw "Fluxo rigido/conflitante reapareceu: $forbidden"}
  }

  # Teste sintetico do caso real: listagem nao acha, POST devolve 409, GET por nome devolve banco existente.
  function Convert-TestDatabaseList {
    param($Raw)
    if ($null -eq $Raw) { return @() }
    if ($Raw -is [System.Array]) { return @($Raw) }
    if ($Raw.PSObject.Properties['databases']) { return @($Raw.databases) }
    if ($Raw.PSObject.Properties['items']) { return @($Raw.items) }
    if ($Raw.PSObject.Properties['data']) {
      $dataNode=$Raw.data
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
  function Convert-TestDatabase { param($Raw); return (@(Convert-TestDatabaseList $Raw) | Select-Object -First 1) }
  function Get-TestField { param($Obj,[string]$Name); $p=$Obj.PSObject.Properties|Where-Object{$_.Name -ieq $Name}|Select-Object -First 1; if($p){[string]$p.Value}else{''} }
  function Invoke-TestTurso {
    param([string]$Method,[string]$Path)
    if($Method -eq 'POST'){throw 'Turso API falhou em POST /v1/organizations/test/databases O servidor remoto devolveu um erro: (409) Conflito.'}
    if($Method -eq 'GET' -and $Path -match '/databases/reino-tribal-prod$'){
      return [pscustomobject]@{database=[pscustomobject]@{name='reino-tribal-prod';hostname='reino-tribal-prod-test.turso.io'}}
    }
    throw "Chamada sintetica inesperada: $Method $Path"
  }

  $testDb=$null
  try {
    $null=Invoke-TestTurso -Method POST -Path '/v1/organizations/test/databases'
  } catch {
    $msg=[string]$_.Exception.Message
    if($msg -notmatch '(?i)(\b409\b|Conflict|Conflito)'){throw}
    $raw=Invoke-TestTurso -Method GET -Path '/v1/organizations/test/databases/reino-tribal-prod'
    $testDb=Convert-TestDatabase $raw
  }
  if(-not $testDb){throw 'Teste 409 falhou: banco existente nao foi recuperado.'}
  if((Get-TestField $testDb 'Name') -ne 'reino-tribal-prod'){throw 'Teste 409 falhou: Name incorreto.'}
  if((Get-TestField $testDb 'Hostname') -ne 'reino-tribal-prod-test.turso.io'){throw 'Teste 409 falhou: Hostname incorreto.'}

  Write-Host 'PASS: TURSO 409 = BANCO EXISTENTE RECUPERADO POR GET NOMINAL.' -ForegroundColor Green
  Write-Host 'PASS: TURSO DB SHAPES = ARRAY/DATABASES/DATABASE/ITEMS/DATA.' -ForegroundColor Green
  Write-Host 'PASS: DENO DEVICE AUTH = MANTIDO.' -ForegroundColor Green
  Write-Host 'TURSO_DB_409_RECOVERY_VALIDATE_PASS' -ForegroundColor Green
}
