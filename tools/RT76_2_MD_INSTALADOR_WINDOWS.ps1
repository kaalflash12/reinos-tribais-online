param(
    [string]$RootOverride = '',
    [switch]$NoOpen,
    [switch]$NoShortcut,
    [switch]$NoPrompt
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Commit = '915cf53e00ebab3278abe49733500bb450be597d'
$ExpectedHtmlSha = 'e9c2f4de0753be66a84000def78f2516315e31dff808109ef2581dffceb45268'
$ArchiveUrl = "https://codeload.github.com/kaalflash12/reinos-tribais-online/zip/$Commit"

function Section([string]$s) {
    Write-Host ''
    Write-Host ('=' * 72) -ForegroundColor DarkYellow
    Write-Host (' ' + $s) -ForegroundColor Yellow
    Write-Host ('=' * 72) -ForegroundColor DarkYellow
}
function Info([string]$s) { Write-Host ('[INFO] ' + $s) -ForegroundColor Cyan }
function Ok([string]$s) { Write-Host ('[PASS] ' + $s) -ForegroundColor Green }
function Warn([string]$s) { Write-Host ('[WARN] ' + $s) -ForegroundColor Yellow }
function Sha256([string]$path) { return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Download([string]$url,[string]$path) {
    $dir = Split-Path -Parent $path
    if($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $wc = New-Object System.Net.WebClient
    try {
        $wc.Headers.Add('User-Agent','Reinos-Tribais-RT76-2-MD-Installer')
        $wc.DownloadFile($url,$path)
    } finally { $wc.Dispose() }
}
function GetPngSize([string]$path) {
    try {
        if(-not (Test-Path -LiteralPath $path)) { return $null }
        $b = [IO.File]::ReadAllBytes($path)
        if($b.Length -lt 24) { return $null }
        if($b[0] -ne 137 -or $b[1] -ne 80 -or $b[2] -ne 78 -or $b[3] -ne 71 -or $b[4] -ne 13 -or $b[5] -ne 10 -or $b[6] -ne 26 -or $b[7] -ne 10) { return $null }
        $w = [Net.IPAddress]::NetworkToHostOrder([BitConverter]::ToInt32($b,16))
        $h = [Net.IPAddress]::NetworkToHostOrder([BitConverter]::ToInt32($b,20))
        if($w -le 0 -or $h -le 0) { return $null }
        return @([int]$w,[int]$h)
    } catch { return $null }
}
function TestPng([string]$path,[int]$w=0,[int]$h=0) {
    $s = GetPngSize $path
    if(-not $s) { return $false }
    if($w -gt 0 -and $s[0] -ne $w) { return $false }
    if($h -gt 0 -and $s[1] -ne $h) { return $false }
    return $true
}
function AssertContains([string]$text,[string]$needle,[string]$label) {
    if(-not $text.Contains($needle)) { throw "Validation failed: $label" }
}
function ResolveRoot() {
    if($RootOverride) { return [IO.Path]::GetFullPath($RootOverride) }
    $candidates = New-Object System.Collections.Generic.List[string]
    $candidates.Add('A:\Downloads\RT63_CORRIGIDO\RT63')
    if($env:USERPROFILE) {
        $candidates.Add((Join-Path $env:USERPROFILE 'Downloads\RT63_CORRIGIDO\RT63'))
        $candidates.Add((Join-Path $env:USERPROFILE 'Downloads\RT76_CORRIGIDO\RT76'))
    }
    $scriptDir = Split-Path -Parent $MyInvocation.ScriptName
    if($scriptDir) { $candidates.Add($scriptDir) }
    foreach($c in $candidates) {
        if($c -and (Test-Path -LiteralPath (Join-Path $c 'JOGAR_REINOS_TRIBAIS.html'))) { return [IO.Path]::GetFullPath($c) }
    }
    if(Test-Path -LiteralPath 'A:\') { return 'A:\Downloads\RT76_CORRIGIDO\RT76' }
    if($env:USERPROFILE) { return (Join-Path $env:USERPROFILE 'Downloads\RT76_CORRIGIDO\RT76') }
    return (Join-Path (Get-Location).Path 'RT76')
}

$root = $null
$temp = $null
try {
    Section 'REINOS TRIBAIS RT76.2 - CONTRATO MD - INSTALADOR PINADO'
    Write-Host "Commit: $Commit"
    Write-Host 'Sem Git / sem Docker / sem Cloudflare.'
    Write-Host 'Instala a build RT76.2 que passou regressao e testes do contrato MD.'

    $root = ResolveRoot
    New-Item -ItemType Directory -Force -Path $root | Out-Null
    Info "Destino: $root"

    $auditRoot = Join-Path $root 'AUDITORIA_RT76_2_MD'
    New-Item -ItemType Directory -Force -Path $auditRoot | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backup = Join-Path $auditRoot ('backup-' + $stamp)
    New-Item -ItemType Directory -Force -Path $backup | Out-Null

    Section '1/8 Backup da instalacao atual'
    foreach($name in @('JOGAR_REINOS_TRIBAIS.html','index.html','rt76-runtime.js','rt76-map-ai.js','rt76-master-plan.js','PLANO_MESTRE_RT76_CONTRATO.json','AUDITORIA_RT76_PLANO_APLICADO.json','JOGAR_RT76.cmd')) {
        $p = Join-Path $root $name
        if(Test-Path -LiteralPath $p) { Copy-Item -LiteralPath $p -Destination (Join-Path $backup $name) -Force }
    }
    Ok "Backup: $backup"

    Section '2/8 Baixar o commit exato aprovado'
    $temp = Join-Path ([IO.Path]::GetTempPath()) ('rt76-2-md-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $temp | Out-Null
    $zip = Join-Path $temp 'rt76.zip'
    Download $ArchiveUrl $zip
    if((Get-Item -LiteralPath $zip).Length -lt 100000) { throw 'Archive download is unexpectedly small.' }
    Ok ('ZIP baixado: ' + (Get-Item -LiteralPath $zip).Length + ' bytes')

    Section '3/8 Extrair e validar HTML + contrato MD + runtimes'
    $extract = Join-Path $temp 'src'
    Expand-Archive -LiteralPath $zip -DestinationPath $extract -Force
    $repo = Get-ChildItem -LiteralPath $extract -Directory | Select-Object -First 1
    if(-not $repo) { throw 'Extracted repository folder not found.' }
    $src = $repo.FullName
    $srcHtml = Join-Path $src 'JOGAR_REINOS_TRIBAIS.html'
    $srcIndex = Join-Path $src 'index.html'
    if(-not (Test-Path -LiteralPath $srcHtml) -or -not (Test-Path -LiteralPath $srcIndex)) { throw 'Main HTML files are missing.' }
    $h1 = Sha256 $srcHtml
    $h2 = Sha256 $srcIndex
    if($h1 -ne $ExpectedHtmlSha -or $h2 -ne $ExpectedHtmlSha) { throw "HTML SHA mismatch. JOGAR=$h1 INDEX=$h2" }

    $html = [IO.File]::ReadAllText($srcHtml,[Text.Encoding]::UTF8)
    foreach($m in @(
        'const VERSION = 76;',
        'const RT_BUILD = "76.2";',
        'const RT76_PLAN = true;',
        'RT76_BRIDGE_START',
        'RT76_WAVE2_START',
        'rt76-runtime.js?v=76.2',
        'rt76-map-ai.js?v=76.2',
        'rt76-master-plan.js?v=76.2',
        'Central de Sistemas RT76'
    )) { AssertContains $html $m $m }
    foreach($bad in @('rt73-village-runtime.js?v=73','Central de Sistemas RT69','CENTRAL OPERACIONAL RT75','RT75 GUIADA')) {
        if($html.Contains($bad)) { throw "Legacy marker found: $bad" }
    }

    foreach($f in @('rt76-runtime.js','rt76-map-ai.js','rt76-master-plan.js','PLANO_MESTRE_RT76_CONTRATO.json','AUDITORIA_RT76_PLANO_APLICADO.json')) {
        if(-not (Test-Path -LiteralPath (Join-Path $src $f))) { throw "Missing required file: $f" }
    }
    $masterText = [IO.File]::ReadAllText((Join-Path $src 'rt76-master-plan.js'),[Text.Encoding]::UTF8)
    foreach($m in @('window.__RT76_MASTER_PLAN__=true','RT76_MASTER_BASE_INIT','RT76_MASTER_STATE_WATCH','window.RT=A.engine')) { AssertContains $masterText $m $m }

    $contract = Get-Content -LiteralPath (Join-Path $src 'PLANO_MESTRE_RT76_CONTRATO.json') -Raw | ConvertFrom-Json
    if([int]$contract.source_lines -ne 1349) { throw "MD contract line count invalid: $($contract.source_lines)" }
    if([bool]$contract.global_complete -ne $false) { throw 'MD contract must remain honest: global_complete must be false.' }
    if($contract.acceptance_matrix.Count -ne 7) { throw "Acceptance matrix count invalid: $($contract.acceptance_matrix.Count)" }

    $audit = Get-Content -LiteralPath (Join-Path $src 'AUDITORIA_RT76_PLANO_APLICADO.json') -Raw | ConvertFrom-Json
    if([string]$audit.build -ne 'RT76.2') { throw "Audit build invalid: $($audit.build)" }
    if([string]$audit.patched_html_sha256 -ne $ExpectedHtmlSha) { throw 'Audit HTML SHA does not match pinned build.' }
    if([int]$audit.md_contract.lines -ne 1349) { throw 'Audit MD contract metadata invalid.' }
    Ok "Build + contrato MD validados: SHA-256 $ExpectedHtmlSha"

    Section '4/8 Validar 95 artes e 5 mapas/overlay'
    $buildings = @('church','academy','timber','stable','rally','farm','main','barracks','first_church','market','clay','iron','warehouse','smith','garage','hide','wall','statue','watchtower')
    $assetCount = 0
    foreach($b in $buildings) {
        foreach($lvl in 0..4) {
            $p = Join-Path $src ("assets\v54\buildings\{0}_l{1}.png" -f $b,$lvl)
            if(-not (TestPng $p 480 400)) { throw "Invalid building PNG: $b L$lvl" }
            $assetCount++
        }
    }
    if($assetCount -ne 95) { throw "Building asset count $assetCount/95" }
    foreach($rel in @('assets\v54\map\village_stage1.png','assets\v54\map\village_stage2.png','assets\v54\map\village_stage3.png','assets\v54\map\village_stage4.png','assets\v54\map\interaction_overlay.png')) {
        if(-not (TestPng (Join-Path $src $rel))) { throw "Invalid map PNG: $rel" }
    }
    Ok '95/95 predios e 5/5 mapas/overlay PNG validos.'

    Section '5/8 Instalar copia limpa da RT76.2'
    $dstAssets = Join-Path $root 'assets'
    if(Test-Path -LiteralPath $dstAssets) { Remove-Item -LiteralPath $dstAssets -Recurse -Force }
    Copy-Item -LiteralPath (Join-Path $src 'assets') -Destination $root -Recurse -Force
    foreach($name in @('JOGAR_REINOS_TRIBAIS.html','index.html','rt76-runtime.js','rt76-map-ai.js','rt76-master-plan.js','PLANO_MESTRE_RT76_CONTRATO.json','AUDITORIA_RT76_PLANO_APLICADO.json')) {
        Copy-Item -LiteralPath (Join-Path $src $name) -Destination (Join-Path $root $name) -Force
    }
    Get-ChildItem -LiteralPath $root -Filter 'rt*-runtime.js' -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'rt76-runtime.js' } | Remove-Item -Force -ErrorAction SilentlyContinue
    foreach($legacy in @('rt73-village-runtime.js','rt72-village-runtime.js','rt72a-village-runtime.js')) {
        $lp = Join-Path $root $legacy
        if(Test-Path -LiteralPath $lp) { Remove-Item -LiteralPath $lp -Force }
    }
    $installedSha = Sha256 (Join-Path $root 'JOGAR_REINOS_TRIBAIS.html')
    if($installedSha -ne $ExpectedHtmlSha) { throw "Installed HTML SHA mismatch: $installedSha" }
    if((Sha256 (Join-Path $root 'index.html')) -ne $ExpectedHtmlSha) { throw 'Installed index SHA mismatch.' }
    foreach($f in @('rt76-runtime.js','rt76-map-ai.js','rt76-master-plan.js','PLANO_MESTRE_RT76_CONTRATO.json')) { if(-not (Test-Path -LiteralPath (Join-Path $root $f))) { throw "Installed file missing: $f" } }
    Ok 'Arquivos RT76.2 + runtime mestre instalados.'

    Section '6/8 Revalidar instalacao'
    $installedCount = 0
    foreach($b in $buildings) {
        foreach($lvl in 0..4) {
            $p = Join-Path $root ("assets\v54\buildings\{0}_l{1}.png" -f $b,$lvl)
            if(-not (TestPng $p 480 400)) { throw "Installed building PNG invalid: $b L$lvl" }
            $installedCount++
        }
    }
    if($installedCount -ne 95) { throw "Installed building count $installedCount/95" }
    foreach($rel in @('assets\v54\map\village_stage1.png','assets\v54\map\village_stage2.png','assets\v54\map\village_stage3.png','assets\v54\map\village_stage4.png','assets\v54\map\interaction_overlay.png')) {
        if(-not (TestPng (Join-Path $root $rel))) { throw "Installed map PNG invalid: $rel" }
    }
    $installedContract = Get-Content -LiteralPath (Join-Path $root 'PLANO_MESTRE_RT76_CONTRATO.json') -Raw | ConvertFrom-Json
    if([int]$installedContract.source_lines -ne 1349) { throw 'Installed MD contract invalid.' }
    Ok 'Instalacao e contrato MD revalidados.'

    Section '7/8 Criar launcher e atalho'
    $cmdPath = Join-Path $root 'JOGAR_RT76.cmd'
    $cmd = @'
@echo off
setlocal
set "GAME=%~dp0JOGAR_REINOS_TRIBAIS.html"
set "CHROME=%ProgramFiles%\Google\Chrome\Application\chrome.exe"
set "CHROME86=%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe"
set "EDGE=%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe"
set "EDGE64=%ProgramFiles%\Microsoft\Edge\Application\msedge.exe"
if exist "%CHROME%" (start "" "%CHROME%" --new-window "%GAME%" & exit /b)
if exist "%CHROME86%" (start "" "%CHROME86%" --new-window "%GAME%" & exit /b)
if exist "%EDGE%" (start "" "%EDGE%" --new-window "%GAME%" & exit /b)
if exist "%EDGE64%" (start "" "%EDGE64%" --new-window "%GAME%" & exit /b)
start "" "%GAME%"
'@
    [IO.File]::WriteAllText($cmdPath,$cmd,(New-Object Text.UTF8Encoding($false)))
    if(-not $NoShortcut) {
        try {
            $desktop = [Environment]::GetFolderPath('Desktop')
            if($desktop) {
                $ws = New-Object -ComObject WScript.Shell
                $lnk = $ws.CreateShortcut((Join-Path $desktop 'Reinos Tribais RT76.2.lnk'))
                $lnk.TargetPath = $cmdPath
                $lnk.WorkingDirectory = $root
                $lnk.Description = 'Reinos Tribais RT76.2 - Contrato MD'
                $lnk.Save()
                Ok 'Atalho criado na area de trabalho.'
            }
        } catch { Warn ('Atalho nao criado: ' + $_.Exception.Message) }
    } else { Info 'Atalho ignorado por parametro de teste.' }

    Section '8/8 Gravar prova local e abrir'
    $proof = [ordered]@{
        build = 'RT76.2'
        md_contract_lines = 1349
        md_global_complete = $false
        commit = $Commit
        html_sha256 = $installedSha
        root = $root
        installed_at = (Get-Date).ToString('o')
        building_png = '95/95'
        village_map_png = '5/5'
        runtime = @('rt76-runtime.js','rt76-map-ai.js','rt76-master-plan.js')
        contract = 'PLANO_MESTRE_RT76_CONTRATO.json'
        cloudflare = 'NOT_USED'
        docker = 'NOT_REQUIRED'
        git = 'NOT_REQUIRED'
    }
    $proofPath = Join-Path $auditRoot 'INSTALACAO_RT76_2_MD.json'
    [IO.File]::WriteAllText($proofPath,($proof | ConvertTo-Json -Depth 6),(New-Object Text.UTF8Encoding($true)))
    Ok "Relatorio: $proofPath"
    if(-not $NoOpen) { Start-Process -FilePath $cmdPath; Ok 'Jogo aberto.' } else { Info 'Abertura ignorada por parametro de teste.' }

    Section 'RT76.2 INSTALADA E VALIDADA LOCALMENTE'
    Write-Host "Raiz: $root"
    Write-Host "HTML SHA-256: $installedSha"
    Write-Host 'Contrato MD: 1349 linhas rastreadas'
    Write-Host 'Predios: 95/95 PNG validos'
    Write-Host 'Mapas/overlay: 5/5 PNG validos'
    exit 0
} catch {
    Section 'RT76.2 PAROU COM ERRO'
    Write-Host $_.Exception.Message -ForegroundColor Red
    if($root) { Write-Host "Raiz: $root" }
    Write-Host 'Cloudflare nao foi acessado.'
    if(-not $NoPrompt) { try { [void](Read-Host 'Pressione ENTER para fechar') } catch {} }
    exit 1
} finally {
    if($temp -and (Test-Path -LiteralPath $temp)) { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue }
}
