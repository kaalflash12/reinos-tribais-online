param([switch]$ValidateOnly)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12

$Pinned='https://raw.githubusercontent.com/kaalflash12/reinos-tribais-online/197aee308093c0d4aef84d0b85e63091ee7e1f08/RT_REINO_TRIBAL_LOW_RESOURCE_FIX6.ps1'
$Base=Join-Path $env:TEMP 'RT_REINO_TRIBAL_DENO_DEP_FIX7_BASE.ps1'
$Final=Join-Path $env:TEMP 'IMPLANTAR_REINO_TRIBAL_DENO_TURSO_FINAL.ps1'
$utf8Bom=New-Object Text.UTF8Encoding($true)

Write-Host '=== REINO TRIBAL FIX7 - DENO DEPENDENCIA PACKAGE.JSON ===' -ForegroundColor Cyan
Remove-Item $Base,$Final -Force -ErrorAction SilentlyContinue
Invoke-WebRequest -UseBasicParsing -Uri $Pinned -OutFile $Base -TimeoutSec 120
if(-not(Test-Path $Base)){throw 'FIX6 pinado nao foi baixado.'}

# Gera o bootstrap low-resource sem executar deploy.
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Base -ValidateOnly
$code=$LASTEXITCODE
if($code -ne 0){throw "FIX6 ValidateOnly falhou. Codigo: $code"}
if(-not(Test-Path $Final)){throw 'FIX6 nao gerou bootstrap final.'}

$t=[IO.File]::ReadAllText($Final).Replace("`r`n","`n")

$oldRequired=@'
  $requiredFiles = @(
    'deno.json',
    'deno/main.js',
    'api/reino.js',
    'api/admin.js',
    'backend/turso/schema.sql'
  )
'@
$oldRequired=$oldRequired.Replace("`r`n","`n")
$newRequired=@'
  $requiredFiles = @(
    'deno.json',
    'package.json',
    'deno/main.js',
    'api/reino.js',
    'api/admin.js',
    'backend/turso/schema.sql'
  )
'@
$newRequired=$newRequired.Replace("`r`n","`n")
if(-not $t.Contains($oldRequired)){throw 'FIX7 nao encontrou lista de 5 arquivos para adicionar package.json.'}
$t=$t.Replace($oldRequired,$newRequired)

# PowerShell nao usa barra invertida como escape; o texto gerado contem UMA barra por caminho.
$oldVerify="foreach (`$required in @('deno.json','deno\main.js','api\reino.js','api\admin.js','backend\turso\schema.sql'))"
$newVerify="foreach (`$required in @('deno.json','package.json','deno\main.js','api\reino.js','api\admin.js','backend\turso\schema.sql'))"
if(-not $t.Contains($oldVerify)){throw 'FIX7 nao encontrou gate de arquivos obrigatorios.'}
$t=$t.Replace($oldVerify,$newVerify)

$t=$t.Replace('Backend minimo obtido pela API GitHub autenticada: 5 arquivos, zero git.exe, zero clone, zero archive.','Backend minimo obtido pela API GitHub autenticada: 6 arquivos, incluindo package.json; zero git.exe, zero clone, zero archive.')

[IO.File]::WriteAllText($Final,$t,$utf8Bom)

$tokens=$null;$errors=$null
[System.Management.Automation.Language.Parser]::ParseFile($Final,[ref]$tokens,[ref]$errors)|Out-Null
if($errors.Count){throw ('FIX7 bootstrap final nao passou no parser: '+(($errors|ForEach-Object{$_.Message+' @ '+$_.Extent.StartLineNumber+':'+$_.Extent.StartColumnNumber}) -join '; '))}

$t=[IO.File]::ReadAllText($Final)
foreach($needle in @(
  "'package.json'",
  'Backend minimo obtido pela API GitHub autenticada: 6 arquivos, incluindo package.json; zero git.exe, zero clone, zero archive.',
  '$fileUri = (''https://api.github.com/repos/{0}/contents/{1}?ref={2}'' -f $Repositorio,$escapedPath,$escapedBranch)',
  'Banco Turso reutilizado apos conflito 409',
  "Deno-PostJsonRaw -Url 'https://console.deno.com/auth/interactive'",
  '$env:DENO_DEPLOY_TOKEN = $denoToken'
)){
  if(-not $t.Contains($needle)){
    throw "FIX7 contrato ausente: $needle"
  }
}
foreach($forbidden in @(
  'Backend minimo obtido pela API GitHub autenticada: 5 arquivos',
  'Get-Command git.exe',
  "'repo','clone'",
  '/zipball/'
)){
  if($t.Contains($forbidden)){throw "FIX7 fluxo antigo reapareceu: $forbidden"}
}

Write-Host 'PASS: BACKEND MINIMO = 6 ARQUIVOS COM PACKAGE.JSON.' -ForegroundColor Green
Write-Host 'PASS: PACKAGE.JSON DA BRANCH SERA BAIXADO ANTES DO DENO CHECK.' -ForegroundColor Green
Write-Host 'FIX7_VALIDATE_PASS' -ForegroundColor Green

if($ValidateOnly){return}

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Final
$code=$LASTEXITCODE
if($code -ne 0){throw "Implantacao final parou no proximo erro real. Codigo: $code"}
