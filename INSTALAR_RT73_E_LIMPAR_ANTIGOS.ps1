$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Set-StrictMode -Version 2

$Commit = 'f29f33d24b1e38779b38f7a6772cad9768cf63e5'
$ExpectedHtmlSha = '584ff58350df3be7dca42d6cb809dffbf500e5e0e4dce4d85083027f72395c11'
$ExpectedRuntimeSha = '799a7a516c7a4078c47833025479984a4011a36384dffd068e7c12dab509bd04'
$Downloads = 'A:\Downloads'
$ParentRoot = 'A:\Downloads\RT63_CORRIGIDO'
$InstallRoot = 'A:\Downloads\RT63_CORRIGIDO\RT63'
$RepoZip = "https://codeload.github.com/kaalflash12/reinos-tribais-online/zip/$Commit"
$PagesUrl = 'https://kaalflash12.github.io/reinos-tribais-online/'
$SelfPath = $MyInvocation.MyCommand.Path

$Buildings = @(
    'main','timber','clay','iron','farm','warehouse','market','hide',
    'barracks','stable','garage','smith','academy','statue','rally','wall',
    'watchtower','first_church','church'
)

function Banner([string]$Text) {
    Write-Host ''
    Write-Host ('=' * 74) -ForegroundColor DarkYellow
    Write-Host (' ' + $Text) -ForegroundColor Yellow
    Write-Host ('=' * 74) -ForegroundColor DarkYellow
}
function Ok([string]$Text) { Write-Host "[OK] $Text" -ForegroundColor Green }
function Info([string]$Text) { Write-Host "[..] $Text" -ForegroundColor Cyan }
function Warn([string]$Text) { Write-Host "[AVISO] $Text" -ForegroundColor Yellow }
function Ensure-Dir([string]$Path) { if (-not (Test-Path -LiteralPath $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null } }
function Normalize([string]$Path) { return [IO.Path]::GetFullPath($Path).TrimEnd('\') }
function Sha256([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }

function Remove-PathSafe([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $full = Normalize $Path
    $install = Normalize $InstallRoot
    $parent = Normalize $ParentRoot
    $self = if ($SelfPath) { Normalize $SelfPath } else { '' }

    if ($full -eq $install -or $full -eq $parent -or ($self -and $full -eq $self)) { return }
    if ($full.StartsWith($install + '\', [StringComparison]::OrdinalIgnoreCase)) { return }

    $item = Get-Item -LiteralPath $Path -Force
    if ($item.PSIsContainer) { Remove-Item -LiteralPath $Path -Recurse -Force }
    else { Remove-Item -LiteralPath $Path -Force }
    Write-Host "      apagado: $Path" -ForegroundColor DarkGray
}

function Validate-FreshRepo([string]$Root) {
    $index = Join-Path $Root 'index.html'
    $game = Join-Path $Root 'JOGAR_REINOS_TRIBAIS.html'
    $runtime = Join-Path $Root 'rt73-village-runtime.js'
    $audit = Join-Path $Root 'AUDITORIA_RT73_FINAL.json'

    foreach ($p in @($index,$game,$runtime,$audit)) {
        if (-not (Test-Path -LiteralPath $p)) { throw "Arquivo RT73 ausente: $p" }
    }

    $indexSha = Sha256 $index
    $gameSha = Sha256 $game
    $runtimeSha = Sha256 $runtime
    if ($indexSha -ne $ExpectedHtmlSha -or $gameSha -ne $ExpectedHtmlSha) {
        throw "HTML RT73 diferente do publicado. Esperado $ExpectedHtmlSha; index=$indexSha; jogo=$gameSha"
    }
    if ($runtimeSha -ne $ExpectedRuntimeSha) {
        throw "Runtime da aldeia diferente do publicado. Esperado $ExpectedRuntimeSha; recebido=$runtimeSha"
    }

    $html = [IO.File]::ReadAllText($game)
    foreach ($marker in @(
        '<title>Reinos Tribais — RT73 Final</title>',
        'const VERSION = 73;',
        'const RT_BUILD = "73.0";',
        'const RT73_FINAL = true;',
        '<script src="rt73-village-runtime.js?v=73"></script>'
    )) {
        if (-not $html.Contains($marker)) { throw "Marcador RT73 ausente: $marker" }
    }

    $runtimeText = [IO.File]::ReadAllText($runtime)
    foreach ($marker in @('__RT73_VILLAGE_RUNTIME__','rt73-village-overlay','assets/v54/buildings/${key}_l${tier}.png')) {
        if (-not $runtimeText.Contains($marker)) { throw "Marcador do runtime ausente: $marker" }
    }

    $assetCount = 0
    foreach ($b in $Buildings) {
        foreach ($lvl in 0..4) {
            $p = Join-Path $Root "assets\v54\buildings\${b}_l${lvl}.png"
            if (-not (Test-Path -LiteralPath $p)) { throw "Asset ausente: $p" }
            if ((Get-Item -LiteralPath $p).Length -lt 1024) { throw "Asset inválido/pequeno: $p" }
            $assetCount++
        }
    }
    if ($assetCount -ne 95) { throw "Contagem de assets inválida: $assetCount/95" }

    foreach ($stage in 1..4) {
        $p = Join-Path $Root "assets\v54\map\village_stage${stage}.png"
        if (-not (Test-Path -LiteralPath $p)) { throw "Mapa evolutivo ausente: $p" }
    }

    return [ordered]@{
        html_sha256 = $indexSha
        runtime_sha256 = $runtimeSha
        building_assets = $assetCount
        village_maps = 4
    }
}

function Prune-DevFiles([string]$Root) {
    $devDir = Join-Path $Root '.github'
    if (Test-Path -LiteralPath $devDir) { Remove-Item -LiteralPath $devDir -Recurse -Force }

    Get-ChildItem -LiteralPath $Root -File -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -match '^rt(58|59|6[0-9]|7[0-2]).*trigger\.txt$' -or
        $_.Name -match '^AUDITORIA_(HOTFIX_)?RT(58|59|6[0-9]|7[0-2]).*\.(json|txt)$' -or
        $_.Name -match '^LEIA_PRIMEIRO_RT(58|59|6[0-9]|7[0-2]).*\.txt$' -or
        $_.Name -match '^rt(69|70|71|72)-.*\.(patch|b64|txt)$'
    } | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force }
}

function Clean-OldDownloads {
    Info 'Apagando versões antigas do Reinos Tribais em A:\Downloads...'
    if (-not (Test-Path -LiteralPath $Downloads)) { return }

    Get-ChildItem -LiteralPath $Downloads -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
        if ((Normalize $_.FullName) -eq (Normalize $ParentRoot)) { return }
        $n = $_.Name
        if ($n -match '^RT(58|59|6[0-9]|7[0-2])(?:\D|$)' -or
            $n -match '^Reinos.?Tribais.*RT(58|59|6[0-9]|7[0-2])' -or
            $n -match '^REINOS_TRIBAIS.*RT(58|59|6[0-9]|7[0-2])') {
            Remove-PathSafe $_.FullName
        }
    }

    Get-ChildItem -LiteralPath $Downloads -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
        $n = $_.Name
        if ($n -match 'RT(58|59|6[0-9]|7[0-2]|72A|72B)' -and
            $n -match '\.(zip|7z|rar|ps1|json|txt|md|png|jpg|html)$') {
            Remove-PathSafe $_.FullName
        }
    }

    if (Test-Path -LiteralPath $ParentRoot) {
        Get-ChildItem -LiteralPath $ParentRoot -Force -ErrorAction SilentlyContinue | ForEach-Object {
            if ((Normalize $_.FullName) -ne (Normalize $InstallRoot)) { Remove-PathSafe $_.FullName }
        }
    }
}

function Create-Shortcut([string]$GamePath) {
    try {
        $desktop = [Environment]::GetFolderPath('Desktop')
        if (-not $desktop) { return }
        Get-ChildItem -LiteralPath $desktop -Filter '*Reinos*Tribais*.lnk' -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        $lnk = Join-Path $desktop 'Reinos Tribais RT73.lnk'
        $shell = New-Object -ComObject WScript.Shell
        $s = $shell.CreateShortcut($lnk)
        $s.TargetPath = $GamePath
        $s.WorkingDirectory = Split-Path -Parent $GamePath
        $s.Description = 'Reinos Tribais RT73 Final'
        $s.Save()
        Ok 'Atalho único RT73 criado na Área de Trabalho.'
    } catch { Warn "Não consegui criar o atalho: $($_.Exception.Message)" }
}

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    Banner 'REINOS TRIBAIS RT73 - INSTALAR NOVA + LIMPAR ANTIGAS'
    Write-Host ' GitHub: usa a build RT73 já publicada e validada.' -ForegroundColor Cyan
    Write-Host ' GitLab: NÃO.' -ForegroundColor Cyan
    Write-Host ' Cloudflare: NÃO.' -ForegroundColor Cyan
    Write-Host ' Git/gh/Docker/Node: NÃO instala.' -ForegroundColor Cyan
    Write-Host ''

    Ensure-Dir $Downloads
    Ensure-Dir $ParentRoot

    $temp = Join-Path $env:TEMP ('reinos-rt73-' + [Guid]::NewGuid().ToString('N'))
    Ensure-Dir $temp
    $zip = Join-Path $temp 'rt73.zip'
    $extract = Join-Path $temp 'extract'
    Ensure-Dir $extract

    Info '[1/8] Baixando a RT73 exata do GitHub...'
    Invoke-WebRequest -Uri $RepoZip -OutFile $zip -UseBasicParsing -Headers @{'User-Agent'='Reinos-Tribais-RT73';'Cache-Control'='no-cache'} -TimeoutSec 180
    if ((Get-Item -LiteralPath $zip).Length -lt 1000000) { throw 'ZIP do GitHub ficou pequeno demais; download incompleto.' }
    Ok ("Download concluído: {0:N1} MB" -f ((Get-Item $zip).Length / 1MB))

    Info '[2/8] Extraindo...'
    Expand-Archive -LiteralPath $zip -DestinationPath $extract -Force
    $source = Get-ChildItem -LiteralPath $extract -Directory | Select-Object -First 1
    if (-not $source) { throw 'Pasta do repositório não apareceu após extrair.' }
    Ok "Extraído: $($source.FullName)"

    Info '[3/8] Validando a build ANTES de tocar na instalação atual...'
    $remoteCheck = Validate-FreshRepo $source.FullName
    Ok "RT73 confirmada: HTML $($remoteCheck.html_sha256)"
    Ok "Runtime aldeia: $($remoteCheck.runtime_sha256)"
    Ok '19 prédios / 95 assets / 4 mapas confirmados.'

    Info '[4/8] Instalando no mesmo caminho do jogo para não trocar o arquivo que você abre...'
    $rollback = Join-Path $ParentRoot ('_ROLLBACK_RT73_' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    if (Test-Path -LiteralPath $InstallRoot) { Move-Item -LiteralPath $InstallRoot -Destination $rollback -Force }
    try {
        Copy-Item -LiteralPath $source.FullName -Destination $InstallRoot -Recurse -Force
        Prune-DevFiles $InstallRoot
        $localCheck = Validate-FreshRepo $InstallRoot
        Ok 'Instalação nova validada no disco.'
    } catch {
        if (Test-Path -LiteralPath $InstallRoot) { Remove-Item -LiteralPath $InstallRoot -Recurse -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $rollback) { Move-Item -LiteralPath $rollback -Destination $InstallRoot -Force }
        throw
    }

    Info '[5/8] Apagando a instalação antiga e arquivos de versões antigas do PC...'
    if (Test-Path -LiteralPath $rollback) { Remove-Item -LiteralPath $rollback -Recurse -Force }
    Clean-OldDownloads
    Ok 'Versões antigas locais removidas.'

    Info '[6/8] Gerando auditoria local final...'
    $auditDir = Join-Path $InstallRoot 'AUDITORIA_LOCAL_RT73'
    Ensure-Dir $auditDir
    $audit = [ordered]@{
        version = 'RT73'
        commit = $Commit
        installed_at = (Get-Date).ToString('s')
        install_root = $InstallRoot
        html_sha256 = $localCheck.html_sha256
        runtime_sha256 = $localCheck.runtime_sha256
        buildings = '19/19'
        building_assets = '95/95'
        village_maps = '4/4'
        old_local_versions_cleaned = $true
        github_source = 'kaalflash12/reinos-tribais-online'
        gitlab_used = $false
        cloudflare_used = $false
    }
    $audit | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $auditDir 'AUDITORIA_RT73_LOCAL.json') -Encoding UTF8
    Ok "Auditoria: $auditDir"

    Info '[7/8] Criando atalho e verificando GitHub Pages...'
    $gamePath = Join-Path $InstallRoot 'JOGAR_REINOS_TRIBAIS.html'
    Create-Shortcut $gamePath
    try {
        $r = Invoke-WebRequest -Uri ($PagesUrl + '?rt73=' + [DateTime]::UtcNow.Ticks) -UseBasicParsing -Headers @{'User-Agent'='Reinos-Tribais-RT73';'Cache-Control'='no-cache'} -TimeoutSec 20
        if ($r.Content.Contains('RT73 Final') -and $r.Content.Contains('rt73-village-runtime.js')) { Ok 'GitHub Pages já está servindo RT73.' }
        else { Warn 'GitHub Pages ainda pode estar propagando; o GitHub main e a instalação local já são RT73.' }
    } catch { Warn 'Não consegui testar Pages agora; isso não altera a instalação local.' }

    Info '[8/8] Abrindo a RT73...'
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
    Start-Process $gamePath

    Banner 'RT73 PRONTA'
    Ok "Instalada em: $InstallRoot"
    Ok 'A versão antiga local foi removida depois da validação da nova.'
    Ok 'Aldeia RT73 usa os 19 prédios com assets v54 diretos, sem duplicar v60/v63/v70/v71/v72.'
    Ok 'GitHub já contém a mesma RT73.'
    Write-Host ''
}
catch {
    Write-Host ''
    Write-Host 'RT73 PAROU COM ERRO' -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Yellow
    Write-Host ''
    Write-Host 'A versão antiga só é apagada DEPOIS que a nova passa na validação.' -ForegroundColor Yellow
    Write-Host ''
    Read-Host 'Pressione ENTER para fechar'
    exit 1
}
