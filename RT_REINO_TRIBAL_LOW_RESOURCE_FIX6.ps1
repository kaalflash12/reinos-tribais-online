param([switch]$ValidateOnly)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12

$Pinned='https://raw.githubusercontent.com/kaalflash12/reinos-tribais-online/450052dda662044700a0d7fdab1fc7625693ae31/RT_REINO_TRIBAL_TURSO_DB_SHAPE_FIX5B.ps1'
$Patched=Join-Path $env:TEMP 'RT_REINO_TRIBAL_LOW_RESOURCE_FIX6_INNER.ps1'
$Final=Join-Path $env:TEMP 'IMPLANTAR_REINO_TRIBAL_DENO_TURSO_FINAL.ps1'
$utf8Bom=New-Object Text.UTF8Encoding($true)

Remove-Item $Patched,$Final -Force -ErrorAction SilentlyContinue
Invoke-WebRequest -UseBasicParsing -Uri $Pinned -OutFile $Patched -TimeoutSec 120
if(-not(Test-Path $Patched)){throw 'FIX5B low-resource pinado nao foi baixado.'}

$s=[IO.File]::ReadAllText($Patched)
$old='$fileUri = "https://api.github.com/repos/$Repositorio/contents/$escapedPath?ref=$escapedBranch"'
$new='$fileUri = (''https://api.github.com/repos/{0}/contents/{1}?ref={2}'' -f $Repositorio,$escapedPath,$escapedBranch)'
if(-not $s.Contains($old)){throw 'FIX6 nao encontrou montagem antiga da URL Contents API.'}
$s=$s.Replace($old,$new)
if($s.Contains($old)){throw 'FIX6 ainda contem montagem ambigua da URL Contents API.'}
[IO.File]::WriteAllText($Patched,$s,$utf8Bom)

$tokens=$null;$errors=$null
[System.Management.Automation.Language.Parser]::ParseFile($Patched,[ref]$tokens,[ref]$errors)|Out-Null
if($errors.Count){throw ('FIX6 inner parser falhou: '+(($errors|ForEach-Object{$_.Message}) -join '; '))}

if($ValidateOnly){
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Patched -ValidateOnly
}else{
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Patched
}
$code=$LASTEXITCODE
if($code -ne 0){throw "FIX6 parou. Codigo: $code"}

if($ValidateOnly){
  if(-not(Test-Path $Final)){throw 'FIX6 nao gerou bootstrap final.'}
  $t=[IO.File]::ReadAllText($Final)
  foreach($needle in @(
    '$fileUri = (''https://api.github.com/repos/{0}/contents/{1}?ref={2}'' -f $Repositorio,$escapedPath,$escapedBranch)',
    'function Get-GitHubBranchFile',
    'Backend minimo obtido pela API GitHub autenticada: 5 arquivos, zero git.exe, zero clone, zero archive.',
    'Banco Turso reutilizado apos conflito 409',
    "Deno-PostJsonRaw -Url 'https://console.deno.com/auth/interactive'",
    '$env:DENO_DEPLOY_TOKEN = $denoToken'
  )){if(-not $t.Contains($needle)){throw "FIX6 contrato ausente: $needle"}}
  foreach($forbidden in @(
    '$fileUri = "https://api.github.com/repos/$Repositorio/contents/$escapedPath?ref=$escapedBranch"',
    'Get-Command git.exe',
    "'repo','clone'",
    '/zipball/'
  )){if($t.Contains($forbidden)){throw "FIX6 fluxo antigo reapareceu: $forbidden"}}
  Write-Host 'LOW_RESOURCE_FIX6_VALIDATE_PASS' -ForegroundColor Green
}
