param([switch]$ValidateOnly)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12

$Pinned='https://raw.githubusercontent.com/kaalflash12/reinos-tribais-online/13cd5d12dc588ad1c4558f33f1f85a477026bc23/RT_REINO_TRIBAL_TURSO_DB_SHAPE_FIX5.ps1'
$Patched=Join-Path $env:TEMP 'RT_REINO_TRIBAL_TURSO_DB_SHAPE_FIX5B_INNER.ps1'
$Final=Join-Path $env:TEMP 'IMPLANTAR_REINO_TRIBAL_DENO_TURSO_FINAL.ps1'
$utf8Bom=New-Object Text.UTF8Encoding($true)

Write-Host '=== REINO TRIBAL FIX5B - TURSO DB SHAPE FINAL ===' -ForegroundColor Cyan
Remove-Item $Patched,$Final -Force -ErrorAction SilentlyContinue
Invoke-WebRequest -UseBasicParsing -Uri $Pinned -OutFile $Patched -TimeoutSec 120
if(-not(Test-Path $Patched)){throw 'FIX5 pinado nao foi baixado.'}

$s=[IO.File]::ReadAllText($Patched)
$replacements=@(
  @('param($Db,[Parameter(Mandatory=$true)][string]$Name)','param($DatabaseObject,[Parameter(Mandatory=$true)][string]$Name)'),
  @('if ($null -eq $Db) { return '''' }','if ($null -eq $DatabaseObject) { return '''' }'),
  @('$prop = $Db.PSObject.Properties | Where-Object { $_.Name -ieq $Name } | Select-Object -First 1','$prop = $DatabaseObject.PSObject.Properties | Where-Object { $_.Name -ieq $Name } | Select-Object -First 1')
)
foreach($pair in $replacements){
  if(-not $s.Contains($pair[0])){throw "FIX5B nao encontrou trecho para corrigir: $($pair[0])"}
  $s=$s.Replace($pair[0],$pair[1])
}
if($s.Contains('param($Db,[Parameter')){throw 'FIX5B ainda contem parametro Db conflitante.'}
[IO.File]::WriteAllText($Patched,$s,$utf8Bom)

$tokens=$null;$errors=$null
[System.Management.Automation.Language.Parser]::ParseFile($Patched,[ref]$tokens,[ref]$errors)|Out-Null
if($errors.Count){throw ('FIX5B inner parser falhou: '+(($errors|ForEach-Object{$_.Message}) -join '; '))}

if($ValidateOnly){
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Patched -ValidateOnly
}else{
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Patched
}
$code=$LASTEXITCODE
if($code -ne 0){throw "FIX5B parou no proximo erro real. Codigo: $code"}

if($ValidateOnly){
  if(-not(Test-Path $Final)){throw 'FIX5B nao gerou bootstrap final.'}
  $t=[IO.File]::ReadAllText($Final)
  foreach($needle in @(
    'param($DatabaseObject,[Parameter(Mandatory=$true)][string]$Name)',
    '$DatabaseObject.PSObject.Properties',
    'function Convert-ToTursoDatabaseList',
    '$Raw.PSObject.Properties[''databases'']',
    '$Raw.PSObject.Properties[''database'']',
    '$db = Convert-ToTursoDatabase $createdRaw',
    '$detailDb = Convert-ToTursoDatabase $detailRaw',
    "Deno-PostJsonRaw -Url 'https://console.deno.com/auth/interactive'",
    '$env:DENO_DEPLOY_TOKEN = $denoToken'
  )){if(-not $t.Contains($needle)){throw "FIX5B contrato ausente: $needle"}}
  foreach($forbidden in @('$dbList.databases','$created.database','$detail.database.Hostname','param($Db,[Parameter')){
    if($t.Contains($forbidden)){throw "FIX5B fluxo rigido/conflitante reapareceu: $forbidden"}
  }
  Write-Host 'TURSO_DB_SHAPE_FIX5B_VALIDATE_PASS' -ForegroundColor Green
}
