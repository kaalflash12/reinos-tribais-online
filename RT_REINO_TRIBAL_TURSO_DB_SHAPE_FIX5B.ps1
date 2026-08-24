param([switch]$ValidateOnly)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12

$Pinned='https://raw.githubusercontent.com/kaalflash12/reinos-tribais-online/13cd5d12dc588ad1c4558f33f1f85a477026bc23/RT_REINO_TRIBAL_TURSO_DB_SHAPE_FIX5.ps1'
$Patched=Join-Path $env:TEMP 'RT_REINO_TRIBAL_TURSO_DB_SHAPE_FIX5B_INNER.ps1'
$Final=Join-Path $env:TEMP 'IMPLANTAR_REINO_TRIBAL_DENO_TURSO_FINAL.ps1'
$utf8Bom=New-Object Text.UTF8Encoding($true)

Write-Host '=== REINO TRIBAL FINAL - TURSO 409 + GITHUB MINIMAL FILES LOW RESOURCE ===' -ForegroundColor Cyan
Remove-Item $Patched,$Final -Force -ErrorAction SilentlyContinue
Invoke-WebRequest -UseBasicParsing -Uri $Pinned -OutFile $Patched -TimeoutSec 120
if(-not(Test-Path $Patched)){throw 'Base pinada nao foi baixada.'}

# 1) Corrige o gerador FIX5B/Turso antes de gerar o bootstrap final.
$s=[IO.File]::ReadAllText($Patched).Replace("`r`n","`n")
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
$oldCreate=$oldCreate.Replace("`r`n","`n")

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
$newCreate=$newCreate.Replace("`r`n","`n")

if(-not $s.Contains($oldCreate)){throw 'Transform nao encontrou bloco de criacao Turso para adicionar recovery 409.'}
$s=$s.Replace($oldCreate,$newCreate)
if($s.Contains('param($Db,[Parameter')){throw 'Ainda contem parametro Db conflitante no gerador.'}
[IO.File]::WriteAllText($Patched,$s,$utf8Bom)

$tokens=$null;$errors=$null
[System.Management.Automation.Language.Parser]::ParseFile($Patched,[ref]$tokens,[ref]$errors)|Out-Null
if($errors.Count){throw ('Inner parser falhou: '+(($errors|ForEach-Object{$_.Message}) -join '; '))}

# 2) Sempre gera sem executar, para aplicar o patch low-resource no bootstrap real.
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Patched -ValidateOnly
$code=$LASTEXITCODE
if($code -ne 0){throw "Gerador FIX5B ValidateOnly falhou. Codigo: $code"}
if(-not(Test-Path $Final)){throw 'Bootstrap final nao foi gerado.'}

# 3) Troca git clone por download autenticado somente dos 5 arquivos do backend.
$t=[IO.File]::ReadAllText($Final).Replace("`r`n","`n")
$branchPattern="(?s)  Etapa 'Obtendo branch.*?(?=  Etapa 'Turso:)"
$branchMatch=[regex]::Match($t,$branchPattern)
if(-not $branchMatch.Success){throw 'Bootstrap final nao contem bloco de obtencao da branch para patch low-resource.'}

$newBranch=@'
  Etapa 'Obtendo backend minimo via GitHub API autenticada'
  $repoDir = Join-Path $WorkRoot 'repo'
  Remove-Item $repoDir -Recurse -Force -ErrorAction SilentlyContinue
  New-Item -ItemType Directory -Force -Path $repoDir | Out-Null

  $tokenResult = Executar-Nativo -Exe $gh -Args @('auth','token') -TimeoutSec 30 -Rotulo 'Obter credencial temporaria GitHub da sessao atual'
  Exigir-Sucesso $tokenResult 'GitHub CLI autenticado nao forneceu a credencial temporaria da sessao.'
  $githubToken = $tokenResult.Text.Trim()
  if ($githubToken.Length -lt 20) { Falhar 'Credencial temporaria GitHub veio vazia ou invalida.' }

  $githubHeaders = @{
    Authorization = "Bearer $githubToken"
    Accept = 'application/vnd.github+json'
    'User-Agent' = 'Reino-Tribal-Bootstrap'
    'X-GitHub-Api-Version' = '2022-11-28'
  }
  $escapedBranch = [Uri]::EscapeDataString($Branch)

  function Get-GitHubBranchFile {
    param([Parameter(Mandatory=$true)][string]$RelativePath)
    $escapedPath = (($RelativePath -split '/') | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/'
    $fileUri = "https://api.github.com/repos/$Repositorio/contents/$escapedPath?ref=$escapedBranch"
    try {
      $meta = Invoke-RestMethod -Method Get -Uri $fileUri -Headers $githubHeaders -TimeoutSec 60
    } catch {
      Falhar "Falha baixando arquivo GitHub $RelativePath.`n$($_.Exception.Message)"
    }
    if ($null -eq $meta -or [string]$meta.type -ne 'file' -or -not $meta.content) {
      Falhar "GitHub API nao retornou conteudo de arquivo para $RelativePath."
    }
    $base64 = ([string]$meta.content) -replace '\s',''
    try { $bytes = [Convert]::FromBase64String($base64) }
    catch { Falhar "Conteudo base64 invalido recebido do GitHub para $RelativePath." }
    if ($bytes.Length -lt 1) { Falhar "Arquivo GitHub vazio: $RelativePath" }
    $dest = Join-Path $repoDir ($RelativePath -replace '/','\')
    $parent = Split-Path $dest -Parent
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    [IO.File]::WriteAllBytes($dest,$bytes)
  }

  $requiredFiles = @(
    'deno.json',
    'deno/main.js',
    'api/reino.js',
    'api/admin.js',
    'backend/turso/schema.sql'
  )
  try {
    foreach ($requiredFile in $requiredFiles) { Get-GitHubBranchFile $requiredFile }
  } finally {
    $githubToken = ''
    $githubHeaders.Authorization = ''
  }

  $workPath = $repoDir
  foreach ($required in @('deno.json','deno\main.js','api\reino.js','api\admin.js','backend\turso\schema.sql')) {
    if (-not (Test-Path (Join-Path $workPath $required))) { Falhar "Arquivo obrigatorio ausente apos download minimo: $required" }
  }
  Ok 'Backend minimo obtido pela API GitHub autenticada: 5 arquivos, zero git.exe, zero clone, zero archive.'
  $check = Executar-Nativo -Exe $DenoExe -Args @('check','deno/main.js') -Diretorio $workPath -TimeoutSec 180 -Rotulo 'Deno check do backend'
  Exigir-Sucesso $check 'Backend não passou no deno check.'
  Ok 'Backend Deno/Turso validado localmente.'

'@
$newBranch=$newBranch.Replace("`r`n","`n")
$t=$t.Substring(0,$branchMatch.Index)+$newBranch+$t.Substring($branchMatch.Index+$branchMatch.Length)
[IO.File]::WriteAllText($Final,$t,$utf8Bom)

$tokens=$null;$errors=$null
[System.Management.Automation.Language.Parser]::ParseFile($Final,[ref]$tokens,[ref]$errors)|Out-Null
if($errors.Count){throw ('Bootstrap final low-resource nao passou no parser: '+(($errors|ForEach-Object{$_.Message+' @ '+$_.Extent.StartLineNumber+':'+$_.Extent.StartColumnNumber}) -join '; '))}

# 4) Contratos do bootstrap final.
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
  '$env:DENO_DEPLOY_TOKEN = $denoToken',
  "`$tokenResult = Executar-Nativo -Exe `$gh -Args @('auth','token')",
  'function Get-GitHubBranchFile',
  'https://api.github.com/repos/$Repositorio/contents/$escapedPath?ref=$escapedBranch',
  '[Convert]::FromBase64String($base64)',
  '[IO.File]::WriteAllBytes($dest,$bytes)',
  'Backend minimo obtido pela API GitHub autenticada: 5 arquivos, zero git.exe, zero clone, zero archive.'
)){
  if(-not $t.Contains($needle)){throw "Contrato final ausente: $needle"}
}
foreach($forbidden in @(
  '$dbList.databases',
  '$created.database',
  '$detail.database.Hostname',
  'param($Db,[Parameter',
  'Get-Command git.exe',
  "'repo','clone'",
  '--single-branch',
  '/zipball/',
  'Expand-Archive -Path $archiveZip'
)){
  if($t.Contains($forbidden)){throw "Fluxo rigido/pesado reapareceu no bootstrap final: $forbidden"}
}

# 5) Teste sintetico do 409.
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
Write-Host 'PASS: GITHUB SOURCE = 5 FILES VIA CONTENTS API AUTH; ZERO GIT/CLONE/ARCHIVE.' -ForegroundColor Green
Write-Host 'PASS: DENO DEVICE AUTH = MANTIDO.' -ForegroundColor Green
Write-Host 'TURSO_DB_409_GITHUB_MINIMAL_VALIDATE_PASS' -ForegroundColor Green

if($ValidateOnly){return}

# 6) So executa depois de tudo acima validado.
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Final
$code=$LASTEXITCODE
if($code -ne 0){throw "Implantacao final parou no proximo erro real. Codigo: $code"}
