param([switch]$ValidateOnly)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12

$Pinned='https://raw.githubusercontent.com/kaalflash12/reinos-tribais-online/9b1dd809cc0d5c3f4f4b336de37b2a4d9bba9d49/RT_REINO_TRIBAL_DENO_DEVICE_AUTH_FIX4B.ps1'
$Patched=Join-Path $env:TEMP 'RT_REINO_TRIBAL_DENO_DEVICE_AUTH_FIX4C_INNER.ps1'
$Final=Join-Path $env:TEMP 'IMPLANTAR_REINO_TRIBAL_DENO_TURSO_FINAL.ps1'

Write-Host '=== REINO TRIBAL FIX4C - DENO DEVICE AUTH FINAL ===' -ForegroundColor Cyan
Remove-Item $Patched,$Final -Force -ErrorAction SilentlyContinue
Invoke-WebRequest -UseBasicParsing -Uri $Pinned -OutFile $Patched -TimeoutSec 120
if(-not(Test-Path $Patched)){throw 'FIX4B pinado nao foi baixado.'}

$s=[IO.File]::ReadAllText($Patched)
$old='  "$denoOrg = $slugs | Sort-Object | Select-Object -First 1"'
$new="  '`$denoOrg = `$slugs | Sort-Object | Select-Object -First 1'"
if(-not $s.Contains($old)){throw 'Gate StrictMode antigo nao encontrado para patch.'}
$s=$s.Replace($old,$new)
[IO.File]::WriteAllText($Patched,$s,(New-Object Text.UTF8Encoding($true)))

$tokens=$null;$errors=$null
[System.Management.Automation.Language.Parser]::ParseFile($Patched,[ref]$tokens,[ref]$errors)|Out-Null
if($errors.Count){throw ('FIX4C inner parser falhou: '+(($errors|ForEach-Object{$_.Message}) -join '; '))}

if($ValidateOnly){
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Patched -ValidateOnly
}else{
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Patched
}
$code=$LASTEXITCODE
if($code -ne 0){throw "FIX4C parou no proximo erro real. Codigo: $code"}

if($ValidateOnly){
  if(-not(Test-Path $Final)){throw 'FIX4C nao gerou bootstrap final.'}
  $t=[IO.File]::ReadAllText($Final)
  foreach($needle in @(
    "Deno-PostJsonRaw -Url 'https://console.deno.com/auth/interactive'",
    "Deno-PostJsonRaw -Url 'https://console.deno.com/auth/exchange'",
    '$env:DENO_DEPLOY_TOKEN = $denoToken',
    "'deploy','whoami','--json','--non-interactive'",
    "'deploy','orgs','list','--json','--non-interactive'",
    '$denoOrg = $slugs | Sort-Object | Select-Object -First 1',
    "Turso-Request -Method GET -Path '/v2/organizations'"
  )){if(-not $t.Contains($needle)){throw "FIX4C contrato ausente: $needle"}}
  if($t.Contains('@($slugs | Sort-Object | Select-Object -First 1)[0]')){throw 'FIX4C ainda contem indexacao Deno [0].'}
  Write-Host 'DENO_DEVICE_AUTH_FIX4C_VALIDATE_PASS' -ForegroundColor Green
}
