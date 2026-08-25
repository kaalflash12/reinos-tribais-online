$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

$root=$PSScriptRoot
$source=Join-Path $root 'REINO_TRIBAL_FINAL_UNICO.ps1'
if(-not (Test-Path $source)){throw 'Executor canonico fonte nao encontrado.'}
$text=[IO.File]::ReadAllText($source).Replace("`r`n","`n")

# Deno auth: remove HttpWebRequest/GetResponse e usa curl.exe com retry.
$startMarker='  function Deno-PostJsonRaw {'
$endMarker='  $denoToken = [string]$env:DENO_DEPLOY_TOKEN'
$start=$text.IndexOf($startMarker,[StringComparison]::Ordinal)
$end=$text.IndexOf($endMarker,[StringComparison]::Ordinal)
if($start -lt 0 -or $end -le $start){throw 'Bloco Deno-PostJsonRaw canonico nao localizado.'}
$newDeno=@'
  function Deno-PostJsonRaw {
    param([Parameter(Mandatory=$true)][string]$Url,[Parameter(Mandatory=$true)][hashtable]$Body)
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if (-not $curl) { Falhar 'curl.exe nao encontrado no Windows para autenticar no Deno.' }
    $id = [Guid]::NewGuid().ToString('N')
    $reqFile = Join-Path $env:TEMP ("rt-deno-auth-$id-request.json")
    $respFile = Join-Path $env:TEMP ("rt-deno-auth-$id-response.json")
    $json = $Body | ConvertTo-Json -Depth 20 -Compress
    [IO.File]::WriteAllText($reqFile,$json,(New-Object Text.UTF8Encoding($false)))
    try {
      $last = ''
      for ($attempt=1; $attempt -le 5; $attempt++) {
        Remove-Item $respFile -Force -ErrorAction SilentlyContinue
        $r = Executar-Nativo -Exe $curl.Source -Args @(
          '--silent','--show-error','--location','--http1.1','--tlsv1.2',
          '--connect-timeout','20','--max-time','60',
          '--retry','2','--retry-all-errors',
          '-H','Content-Type: application/json','-H','Accept: application/json',
          '--data-binary',('@' + $reqFile),'--output',$respFile,'--write-out','%{http_code}',$Url
        ) -TimeoutSec 75 -Rotulo "Deno HTTPS tentativa $attempt/5"
        $bodyText = if (Test-Path $respFile) { [IO.File]::ReadAllText($respFile) } else { '' }
        $status = 0
        if ($r.Stdout -match '^[0-9]{3}$') { $status = [int]$r.Stdout }
        if ($r.Code -eq 0 -and $status -gt 0) {
          return [pscustomobject]@{ Ok=($status -ge 200 -and $status -lt 300); Status=$status; Text=[string]$bodyText }
        }
        $last = "curl exit=$($r.Code); http=$status; stderr=$($r.Stderr); body=$bodyText"
        if ($attempt -lt 5) { Start-Sleep -Seconds ([Math]::Min(8,$attempt*2)) }
      }
      return [pscustomobject]@{ Ok=$false; Status=0; Text=('Falha HTTPS Deno apos 5 tentativas. ' + $last) }
    } finally {
      Remove-Item $reqFile,$respFile -Force -ErrorAction SilentlyContinue
    }
  }

'@
$text=$text.Substring(0,$start)+$newDeno+$text.Substring($end)

# CORS publico: substitui por indices ASCII, sem depender de encoding/acento.
$healthStartMarker='  $health = Post-Json "$backend/api/reino"'
$nextAccountMarker='  $stamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()'
$healthStart=$text.IndexOf($healthStartMarker,[StringComparison]::Ordinal)
$nextAccount=$text.IndexOf($nextAccountMarker,[StringComparison]::Ordinal)
if($healthStart -lt 0 -or $nextAccount -le $healthStart){throw 'Faixa health -> conta de teste nao localizada.'}
$corsBlock=@'
  $health = Post-Json "$backend/api/reino" @{ action='health' }
  if (-not $health.ok -or $health.database -ne 'turso') { Falhar 'Health da API/Turso nao passou.' }

  $corsUri = [Uri]($backend.TrimEnd('/') + '/api/reino')
  if (-not $corsUri.IsAbsoluteUri -or [string]::IsNullOrWhiteSpace($corsUri.Host)) { Falhar "URL CORS invalida: $corsUri" }
  $corsUrl = $corsUri.AbsoluteUri
  Write-Host ("CORS URL: " + $corsUrl) -ForegroundColor DarkGray
  $corsHeaders = Join-Path $env:TEMP ('rt-canonical-cors-' + [Guid]::NewGuid().ToString('N') + '.txt')
  try {
    $curlCors = Get-Command curl.exe -ErrorAction SilentlyContinue
    if (-not $curlCors) { Falhar 'curl.exe nao encontrado para teste CORS.' }
    $cors = Executar-Nativo -Exe $curlCors.Source -Args @(
      '--silent','--show-error','--http1.1','--tlsv1.2','--connect-timeout','20','--max-time','30',
      '--output','NUL','--dump-header',$corsHeaders,'--request','OPTIONS',
      '-H','Origin: https://kaalflash12.github.io',
      '-H','Access-Control-Request-Method: POST',
      '-H','Access-Control-Request-Headers: content-type,authorization',
      $corsUrl
    ) -TimeoutSec 45 -Rotulo 'CORS preflight publico'
    Exigir-Sucesso $cors 'CORS preflight publico nao respondeu.'
    $corsText = if (Test-Path $corsHeaders) { [IO.File]::ReadAllText($corsHeaders) } else { '' }
    if ($corsText -notmatch '(?im)^HTTP/\S+\s+204\b') { Falhar "CORS preflight nao retornou 204.`n$corsText" }
    if ($corsText -notmatch '(?im)^access-control-allow-origin:\s*https://kaalflash12\.github\.io\s*$') { Falhar "CORS allow-origin invalido.`n$corsText" }
    Ok 'CORS publico 204 passou.'
  } finally {
    Remove-Item $corsHeaders -Force -ErrorAction SilentlyContinue
  }

'@
$text=$text.Substring(0,$healthStart)+$corsBlock+$text.Substring($nextAccount)

# Contratos ja corrigidos que nao podem regredir.
foreach($needle in @(
  "[string]`$Branch = 'main'",
  "'package.json'",
  '--do-not-use-detected-build-config',
  "action='admin_recover'",
  'recovery_key=$recoveryKey',
  'Deno HTTPS tentativa',
  '$corsUrl = $corsUri.AbsoluteUri',
  "Ok 'CORS publico 204 passou.'"
)){
  if(-not $text.Contains($needle)){throw "Contrato FIX17 ausente: $needle"}
}
foreach($forbidden in @('HttpWebRequest','GetResponse()')){
  if($text.Contains($forbidden)){throw "FIX17 ainda contem transporte Deno legado: $forbidden"}
}

$targets=@(
  'REINO_TRIBAL_FINAL_UNICO.ps1',
  'EXECUTAR_REINO_TRIBAL_DENO_TURSO_FINAL.ps1',
  'IMPLANTAR_REINO_TRIBAL_DENO_TURSO.ps1'
)
$utf8=New-Object Text.UTF8Encoding($false)
foreach($name in $targets){
  [IO.File]::WriteAllText((Join-Path $root $name),$text,$utf8)
}
Write-Host 'FIX17_CANONICAL_TRANSFORM_PASS'
