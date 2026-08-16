param(
  [string]$RootOverride = '',
  [switch]$NoOpen,
  [switch]$NoShortcut,
  [switch]$NoPrompt
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Set-StrictMode -Version 2

$Commit = '2b475eddc068f8c418f338428546239089d5648c'
$ExpectedHtmlSha = '3a1942edee3ddde4d22d1d4b4c187fb18a0c393020c263cc55e7690018a9a6da'
$Raw = "https://raw.githubusercontent.com/kaalflash12/reinos-tribais-online/$Commit"
if($RootOverride){ $Root = $RootOverride } else { $Root = 'A:\Downloads\RT63_CORRIGIDO\RT63' }

$Buildings = @(
  'main','timber','clay','iron','farm','warehouse','market','hide','barracks',
  'stable','garage','smith','academy','statue','rally','wall','watchtower',
  'first_church','church'
)

function Info([string]$s){ Write-Host "[INFO] $s" -ForegroundColor Cyan }
function Pass([string]$s){ Write-Host "[PASS] $s" -ForegroundColor Green }
function Warn([string]$s){ Write-Host "[AVISO] $s" -ForegroundColor Yellow }
function EnsureDir([string]$p){ if(-not (Test-Path -LiteralPath $p)){ New-Item -ItemType Directory -Path $p -Force | Out-Null } }
function Download([string]$url,[string]$out){
  EnsureDir (Split-Path -Parent $out)
  Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing -TimeoutSec 120 `
    -Headers @{'User-Agent'='Reinos-Tribais-RT75-V3';'Cache-Control'='no-cache'}
}
function GetPngSize([string]$path){
  try{
    $b=[IO.File]::ReadAllBytes($path)
    if($b.Length -lt 24){ return $null }
    $sig=@(137,80,78,71,13,10,26,10)
    for($i=0;$i -lt 8;$i++){ if($b[$i] -ne $sig[$i]){ return $null } }
    [Array]::Reverse($b,16,4); [Array]::Reverse($b,20,4)
    $w=[BitConverter]::ToUInt32($b,16); $h=[BitConverter]::ToUInt32($b,20)
    return @([int]$w,[int]$h)
  } catch { return $null }
}
function TestPng([string]$path,[int]$w=0,[int]$h=0){
  if(-not (Test-Path -LiteralPath $path)){ return $false }
  $s=GetPngSize $path
  if(-not $s){ return $false }
  if($w -gt 0 -and $s[0] -ne $w){ return $false }
  if($h -gt 0 -and $s[1] -ne $h){ return $false }
  return $true
}
function AssertContains([string]$text,[string]$needle){ if(-not $text.Contains($needle)){ throw "Marcador ausente: $needle" } }

try{
  [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
  Write-Host ''
  Write-Host '============================================================' -ForegroundColor DarkYellow
  Write-Host ' REINOS TRIBAIS RT75 - INSTALADOR V3 WINDOWS' -ForegroundColor Yellow
  Write-Host '============================================================' -ForegroundColor DarkYellow

  EnsureDir $Root
  $Audit=Join-Path $Root 'AUDITORIA_RT75'
  EnsureDir $Audit
  $Game=Join-Path $Root 'JOGAR_REINOS_TRIBAIS.html'
  $Index=Join-Path $Root 'index.html'

  Info "1/7 Pasta alvo: $Root"
  $stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
  if(Test-Path -LiteralPath $Game){ Copy-Item $Game (Join-Path $Audit "JOGAR.pre-v3-$stamp.html") -Force }
  if(Test-Path -LiteralPath $Index){ Copy-Item $Index (Join-Path $Audit "index.pre-v3-$stamp.html") -Force }

  Info '2/7 Baixando e validando os HTMLs exatos...'
  $Tmp=Join-Path $env:TEMP ('rt75v3-'+[Guid]::NewGuid().ToString('N'))
  EnsureDir $Tmp
  $TG=Join-Path $Tmp 'JOGAR_REINOS_TRIBAIS.html'
  $TI=Join-Path $Tmp 'index.html'
  Download "$Raw/JOGAR_REINOS_TRIBAIS.html" $TG
  Download "$Raw/index.html" $TI
  $SG=(Get-FileHash $TG -Algorithm SHA256).Hash.ToLowerInvariant()
  $SI=(Get-FileHash $TI -Algorithm SHA256).Hash.ToLowerInvariant()
  if($SG -ne $ExpectedHtmlSha -or $SI -ne $ExpectedHtmlSha){ throw "SHA HTML incorreto: jogo=$SG index=$SI" }
  $H=[IO.File]::ReadAllText($TG)
  @(
    '<title>Reinos Tribais',
    'const VERSION = 75;',
    'const RT_BUILD = "75.0";',
    'const RT75_STABLE = true;',
    'RT75_VILLAGE_RENDERER',
    'rt75-building-art',
    'RT74_LOCAL_AUTOSAVE',
    'rt74RankedPrizePanel',
    'rt74EventsExecutionPanel',
    'Monstros e drops exclusivos'
  ) | ForEach-Object { AssertContains $H $_ }
  Pass 'HTML e marcadores confirmados.'

  Info '3/7 Instalando os HTMLs...'
  Copy-Item $TG $Game -Force
  Copy-Item $TI $Index -Force
  if((Get-FileHash $Game -Algorithm SHA256).Hash.ToLowerInvariant() -ne $ExpectedHtmlSha){ throw 'JOGAR local divergiu.' }
  if((Get-FileHash $Index -Algorithm SHA256).Hash.ToLowerInvariant() -ne $ExpectedHtmlSha){ throw 'index local divergiu.' }
  Pass 'HTMLs instalados byte-a-byte.'

  Info '4/7 Validando/reparando 95 PNGs dos predios...'
  $n=0
  foreach($b in $Buildings){
    foreach($lvl in 0..4){
      $rel="assets/v54/buildings/${b}_l${lvl}.png"
      $local=Join-Path $Root ($rel -replace '/','\')
      if(-not (TestPng $local 480 400)){ Download "$Raw/$rel" $local }
      if(-not (TestPng $local 480 400)){ throw "PNG invalido: $rel" }
      $n++
    }
  }
  if($n -ne 95){ throw "Contagem PNG: $n/95" }
  Pass '95/95 PNGs validos em 480x400; L0 de 824 bytes e aceito.'

  Info '5/7 Validando/reparando mapas...'
  foreach($rel in @(
    'assets/v54/map/village_stage1.png','assets/v54/map/village_stage2.png',
    'assets/v54/map/village_stage3.png','assets/v54/map/village_stage4.png',
    'assets/v54/map/interaction_overlay.png'
  )){
    $local=Join-Path $Root ($rel -replace '/','\')
    if(-not (TestPng $local)){ Download "$Raw/$rel" $local }
    if(-not (TestPng $local)){ throw "Mapa PNG invalido: $rel" }
  }
  Pass '4 mapas + overlay validos.'

  Info '6/7 Gravando relatorio local...'
  $report=[ordered]@{
    build='RT75'; installer='V3_WINDOWS'; commit=$Commit; html_sha256=$ExpectedHtmlSha
    html_ok=$true; building_png='95/95'; maps='4/4 + overlay'
    local_save_marker=$true; ranked_marker=$true; events_marker=$true; monster_marker=$true
    installed_at=(Get-Date).ToString('s'); root=$Root
  }
  $report | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $Audit 'EXECUCAO_RT75_V3.json') -Encoding UTF8
  Pass 'Relatorio gravado.'

  Info '7/7 Finalizacao...'
  if(-not $NoShortcut){
    try{
      $desktop=[Environment]::GetFolderPath('Desktop')
      if($desktop){
        $ws=New-Object -ComObject WScript.Shell
        $lnk=$ws.CreateShortcut((Join-Path $desktop 'Reinos Tribais RT75.lnk'))
        $lnk.TargetPath=$Game; $lnk.WorkingDirectory=$Root; $lnk.Description='Reinos Tribais RT75'
        $lnk.Save()
      }
    } catch { Warn "Atalho nao criado: $($_.Exception.Message)" }
  }

  Remove-Item $Tmp -Recurse -Force -ErrorAction SilentlyContinue

  if(-not $NoOpen){
    try{
      $chrome='C:\Program Files\Google\Chrome\Application\chrome.exe'
      if(-not (Test-Path $chrome)){ $chrome='C:\Program Files (x86)\Google\Chrome\Application\chrome.exe' }
      if(Test-Path $chrome){
        $uri=(New-Object System.Uri($Game)).AbsoluteUri+'?rt75v3='+[DateTime]::UtcNow.Ticks
        Start-Process $chrome -ArgumentList @('--new-window','--disable-application-cache',$uri)
      } else { Start-Process $Game }
    } catch { Warn "Jogo instalado, mas nao consegui abrir automaticamente: $($_.Exception.Message)" }
  }

  Write-Host ''
  Write-Host 'RT75 V3 INSTALADA COM SUCESSO.' -ForegroundColor Green
  exit 0
}
catch{
  Write-Host ''
  Write-Host "[ERRO] $($_.Exception.Message)" -ForegroundColor Red
  Write-Host 'A instalacao nao foi marcada como concluida.' -ForegroundColor Yellow
  if(-not $NoPrompt){ Read-Host 'Pressione ENTER para fechar' | Out-Null }
  exit 1
}
