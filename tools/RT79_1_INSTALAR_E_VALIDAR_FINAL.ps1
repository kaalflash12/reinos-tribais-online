param(
    [string]$Destino = "",
    [string]$ZipPath = "",
    [switch]$NaoAbrir,
    [switch]$AbrirLocal
)

$ErrorActionPreference = 'Stop'
$Build = 'RT79.1'
$OnlineUrl = 'https://kaalflash12.github.io/reinos-tribais-online/'
$ExpectedZipHash = 'a3941000820bd54b36da497401ef709c75a0ee9ddfe753b64f7328e26f7db5cd'
$Expected = @{
    'CHECKSUMS_RT79_1.json' = 'e0ce56146413b643a6f877781bc9736a16f2403e1535baf871910057a211d9d2'
    'index.html' = '7e01cdb7d636b258c4d0c536401be3f3d19725ba11f0424d15b6a5d7d5751226'
    'JOGAR_REINOS_TRIBAIS.html' = '7e01cdb7d636b258c4d0c536401be3f3d19725ba11f0424d15b6a5d7d5751226'
    'rt76-map-ai.js' = 'b73d8a37da5cd3a6f7560b65ec095aa5dadde796279c93647825104c984e2816'
    'rt79-suite.js' = '5d6b762369a8e15a42e2e721f1fca901e985ecf087ecb8f028afee5be077f802'
    'rt79-groups-addon.js' = '77388697658447702abe50075ab8bca497b598e2cd9e0290c6b80a66f9571139'
    'rt79-logistics-ai-addon.js' = 'd2b665254f915b8b97ee10be2fa8b227b337da8c9dbc6ab5bc46a857d7fea0b4'
    'rt79-village-ui.js' = '8c4cfd55fcad3fcd63368f01bdda8f8349f65b87d95c1d569ca62ad49703d01b'
    'rt79-admin-suite.js' = '07b16239e32ca8b8479fdc6a0ea95c24b6864ecd0ed5cf26189cf42ebccc82e2'
    'rt79-admin-logistics-addon.js' = '6ac11562f54f1c1fcc1aa2d004739c9680ff28880c9c15b6af4b001377f9786b'
    'AUDITORIA\MASTER_REQUIREMENTS_RT79_1.json' = '16aff701e7ed30d6eb42a63291e101e964347ebf2ea339b0d6543db62766a523'
    'AUDITORIA\AUDITORIA_RT79_1_714_REQUISITOS.json' = '38a27a2bd5799f415001d4b659f16b984326cbbbef83e2e9a88b77b373631b74'
    'AUDITORIA\AUDITORIA_RT79_1_PUBLIC_BROWSER.json' = '623172bd4c1a239886affe832d5a8133832fdc364483bcb86c014a972d9e2468'
    'AUDITORIA\PROVA_RT79_1_FINAL.json' = 'cebfe6acec9ec9f8caa22b83e29f6d6b807218adbdaa8c1fb1c6322683854c0e'
}

function Step([string]$Text) { Write-Host "[RT79.1] $Text" -ForegroundColor Cyan }
function Fail([string]$Text) { throw "RT79.1: $Text" }

Write-Host '============================================================' -ForegroundColor DarkYellow
Write-Host ' REINOS TRIBAIS RT79.1 - INSTALADOR + AUDITOR DE PACOTE' -ForegroundColor Yellow
Write-Host '============================================================' -ForegroundColor DarkYellow

function Get-ZipCandidate([string]$ManualPath) {
    if ($ManualPath) {
        if (-not (Test-Path -LiteralPath $ManualPath -PathType Leaf)) { Fail "ZipPath nao existe: $ManualPath" }
        return (Resolve-Path -LiteralPath $ManualPath).Path
    }
    $roots = @($PSScriptRoot,'A:\Downloads',(Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads'),([Environment]::GetFolderPath('Desktop'))) |
        Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) } | Select-Object -Unique
    $candidates = @()
    foreach ($root in $roots) {
        $candidates += Get-ChildItem -LiteralPath $root -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like 'RT79_1_JOGO_COMPLETO_REVISADO*.zip' -or $_.Name -like 'RT79.1*REVISADO*.zip' }
    }
    if (-not $candidates) {
        foreach ($root in $roots) {
            $candidates += Get-ChildItem -LiteralPath $root -File -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like 'RT79_1_JOGO_COMPLETO_REVISADO*.zip' -or $_.Name -like 'RT79.1*REVISADO*.zip' }
        }
    }
    $candidates = @($candidates | Sort-Object LastWriteTime -Descending -Unique)
    if (-not $candidates) { Fail 'ZIP RT79.1 revisado nao encontrado ao lado do PowerShell, em Downloads ou na Area de Trabalho.' }
    foreach ($c in $candidates) {
        try {
            $h=(Get-FileHash -Algorithm SHA256 -LiteralPath $c.FullName).Hash.ToLowerInvariant()
            if ($ExpectedZipHash -ne '__ZIP_HASH__' -and $h -eq $ExpectedZipHash) { return $c.FullName }
        } catch {}
    }
    return $candidates[0].FullName
}

$Zip = Get-ZipCandidate $ZipPath
$ZipHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Zip).Hash.ToLowerInvariant()
if ($ExpectedZipHash -ne '__ZIP_HASH__' -and $ZipHash -ne $ExpectedZipHash) { Fail "SHA256 do ZIP divergente. Esperado $ExpectedZipHash; recebido $ZipHash" }
Step "ZIP localizado e hash validado: $Zip"

if (-not $Destino) {
    if (Test-Path 'A:\Downloads') { $Destino='A:\Downloads\RT79_1_JOGO_COMPLETO_REVISADO' }
    else { $Destino=Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads\RT79_1_JOGO_COMPLETO_REVISADO' }
}
$parent=Split-Path $Destino -Parent
if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
$temp=Join-Path ([IO.Path]::GetTempPath()) ('RT79_1_VALIDATE_'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $temp | Out-Null

try {
    Step 'Extraindo para area temporaria'
    Expand-Archive -LiteralPath $Zip -DestinationPath $temp -Force
    $root=$temp
    if (-not (Test-Path (Join-Path $root 'index.html'))) {
        $found=Get-ChildItem -Path $temp -Filter index.html -Recurse -File | Select-Object -First 1
        if (-not $found) { Fail 'index.html ausente no ZIP.' }
        $root=$found.Directory.FullName
    }

    $required=@(
      'index.html','JOGAR_REINOS_TRIBAIS.html','CHECKSUMS_RT79_1.json','JOGAR.cmd','JOGAR_RT79_LOCAL.cmd','JOGAR_RT79_ONLINE.cmd','LEIA_PRIMEIRO_RT79_1.txt',
      'rt76-runtime.js','rt76-map-ai.js','rt76-master-plan.js','rt79-suite.js','rt79-groups-addon.js','rt79-logistics-ai-addon.js','rt79-village-ui.js','rt79-admin-suite.js','rt79-admin-logistics-addon.js',
      'AUDITORIA\MASTER_REQUIREMENTS_RT79_1.json','AUDITORIA\AUDITORIA_RT79_1_714_REQUISITOS.json','AUDITORIA\AUDITORIA_RT79_1_PUBLIC_BROWSER.json','AUDITORIA\PROVA_RT79_1_FINAL.json'
    )
    foreach($rel in $required){ if(-not(Test-Path -LiteralPath (Join-Path $root $rel) -PathType Leaf)){Fail "Arquivo obrigatorio ausente: $rel"} }
    foreach($old in @('JOGAR_RT78_LOCAL.cmd','JOGAR_RT78_ONLINE.cmd','LEIA_PRIMEIRO_RT78.txt')){ if(Test-Path (Join-Path $root $old)){Fail "Arquivo obsoleto indevido no pacote: $old"} }

    Step 'Validando hashes criticos'
    foreach($rel in $Expected.Keys){
        $got=(Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $root $rel)).Hash.ToLowerInvariant()
        if($got -ne $Expected[$rel]){Fail "Hash divergente em $rel. Esperado $($Expected[$rel]); recebido $got"}
    }

    Step 'Validando SHA256 de todo o pacote'
    $manifest=Get-Content -LiteralPath (Join-Path $root 'CHECKSUMS_RT79_1.json') -Raw | ConvertFrom-Json
    $manifestProps=@($manifest.files.PSObject.Properties)
    if($manifestProps.Count -lt 1200){Fail "Manifesto de checksums pequeno demais: $($manifestProps.Count) arquivos."}
    foreach($prop in $manifestProps){
        $rel=[string]$prop.Name;$expectedHash=[string]$prop.Value
        $full=Join-Path $root ($rel -replace '/','\')
        if(-not(Test-Path -LiteralPath $full -PathType Leaf)){Fail "Arquivo do manifesto ausente: $rel"}
        $got=(Get-FileHash -Algorithm SHA256 -LiteralPath $full).Hash.ToLowerInvariant()
        if($got -ne $expectedHash){Fail "Checksum global divergente em $rel."}
    }

    $i1=(Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $root 'index.html')).Hash
    $i2=(Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $root 'JOGAR_REINOS_TRIBAIS.html')).Hash
    if($i1 -ne $i2){Fail 'index.html e JOGAR_REINOS_TRIBAIS.html divergem.'}

    Step 'Validando contrato de 714 requisitos'
    $master=Get-Content -LiteralPath (Join-Path $root 'AUDITORIA\MASTER_REQUIREMENTS_RT79_1.json') -Raw | ConvertFrom-Json
    if([int]$master.total_requirements -ne 714 -or @($master.requirements).Count -ne 714){Fail "Lista-mestre incompleta: total=$($master.total_requirements), itens=$(@($master.requirements).Count)"}
    $blocked=@($master.requirements | Where-Object { $_.rt79_1_status -eq 'BLOCKED_EXTERNAL' })
    if($blocked.Count -ne 3){Fail "Esperados 3 bloqueios externos explicitamente registrados; encontrados $($blocked.Count)."}
    $baseline=@($master.requirements | Where-Object { $_.rt79_1_status -eq 'PASS_BASELINE_PLUS_RT79_1_REGRESSION' })
    $direct=@($master.requirements | Where-Object { $_.rt79_1_status -eq 'PASS_DIRECT_RT79_1_CORRECTION' })
    $research=@($master.requirements | Where-Object { $_.rt79_1_status -eq 'PASS_RESEARCH_SCOPE' })
    $attempted=@($master.requirements | Where-Object { $_.rt79_1_status -eq 'PASS_ATTEMPTED' })
    if($baseline.Count -ne 693 -or $direct.Count -ne 2 -or $research.Count -ne 14 -or $attempted.Count -ne 2){Fail "Matriz RT79.1 inconsistente: baseline=$($baseline.Count), diretos=$($direct.Count), pesquisa=$($research.Count), tentativas=$($attempted.Count)."}
    $browser=Get-Content -LiteralPath (Join-Path $root 'AUDITORIA\AUDITORIA_RT79_1_PUBLIC_BROWSER.json') -Raw | ConvertFrom-Json
    if(-not [bool]$browser.pass){Fail "Gate publico do navegador nao esta em PASS: $($browser.error)"}
    $finalProof=Get-Content -LiteralPath (Join-Path $root 'AUDITORIA\PROVA_RT79_1_FINAL.json') -Raw | ConvertFrom-Json
    if([int]$finalProof.requirements.total -ne 714 -or [int]$finalProof.requirements.blocked_external -ne 3){Fail 'PROVA_RT79_1_FINAL.json inconsistente.'}

    Step 'Validando VERSION/BUILD/save/loaders'
    $html=Get-Content -LiteralPath (Join-Path $root 'index.html') -Raw
    $markers=@('const VERSION = 79;','const RT_BUILD = "79.1";',',79].includes(Number(parsed.version))','rt79-suite.js?v=79.1','rt79-groups-addon.js?v=79.1','rt79-logistics-ai-addon.js?v=79.1','rt79-village-ui.js?v=79.1','rt79-admin-suite.js?v=79.1','rt79-admin-logistics-addon.js?v=79.1','UNIT_STAGE_ART','HERO_ITEM_ART','renderHeroLoadout')
    foreach($m in $markers){ if(-not $html.Contains($m)){Fail "Marcador RT79.1 ausente: $m"} }

    Step 'Validando 19 familias x 5 tiers de predios'
    $bdir=Join-Path $root 'assets\v54\buildings'
    $bstages=@(Get-ChildItem -LiteralPath $bdir -File -Filter '*.png' | Where-Object {$_.Name -match '_l[0-4]\.png$'})
    $families=@($bstages | ForEach-Object {$_.BaseName -replace '_l[0-4]$',''} | Sort-Object -Unique)
    if($families.Count -ne 19 -or $bstages.Count -ne 95){Fail "Predios: esperado 19 familias/95 PNGs; encontrado $($families.Count)/$($bstages.Count)."}
    foreach($fam in $families){
        $h=@()
        0..4 | ForEach-Object { $p=Join-Path $bdir ("{0}_l{1}.png" -f $fam,$_);if(-not(Test-Path $p)){Fail "Tier ausente: $fam L$_"};if($_ -gt 0){$h+=(Get-FileHash -Algorithm SHA256 $p).Hash} }
        if(@($h|Select-Object -Unique).Count -ne 4){Fail "Evolucoes L1-L4 nao sao quatro arquivos distintos: $fam"}
    }

    Step 'Validando 40 artes evolutivas de tropas e 16 overlays do Paladino'
    $udir=Join-Path $root 'assets\v28\units';$units=@('spear','sword','axe','archer','spy','light','marcher','heavy','ram','catapult')
    foreach($u in $units){$h=@();0..3|ForEach-Object{$p=Join-Path $udir ("{0}_{1}.png" -f $u,$_);if(-not(Test-Path $p)){Fail "Arte de tropa ausente: $u $_"};$h+=(Get-FileHash -Algorithm SHA256 $p).Hash};if(@($h|Select-Object -Unique).Count -ne 4){Fail "Estagios visuais nao distintos: $u"}}
    $hero=@(Get-ChildItem -LiteralPath (Join-Path $root 'assets\v28\hero\items') -Filter '*.png' -File);if($hero.Count -lt 16){Fail "Overlays Paladino: $($hero.Count), esperado >=16."}

    Step 'Validando referencias locais de assets'
    $src=''
    Get-ChildItem -LiteralPath $root -File | Where-Object {$_.Extension -in '.html','.js'} | ForEach-Object {$src += (Get-Content $_.FullName -Raw)+"`n"}
    $matches=[regex]::Matches($src,'assets/[A-Za-z0-9_./()\-]+\.(png|jpg|jpeg|webp|svg|gif|ico)','IgnoreCase') | ForEach-Object {$_.Value} | Sort-Object -Unique
    $missing=@();foreach($ref in $matches){$p=Join-Path $root ($ref -replace '/','\');if(-not(Test-Path -LiteralPath $p)){$missing+=$ref}}
    if($missing.Count){Fail ('Assets referenciados ausentes: '+($missing -join ', '))}

    $node=Get-Command node -ErrorAction SilentlyContinue;$nodeStatus='SKIPPED_NODE_NOT_INSTALLED'
    if($node){
        Step 'Validando JavaScript externo com Node'
        foreach($js in @('rt76-runtime.js','rt76-map-ai.js','rt76-master-plan.js','rt79-suite.js','rt79-groups-addon.js','rt79-logistics-ai-addon.js','rt79-village-ui.js','rt79-admin-suite.js','rt79-admin-logistics-addon.js')){& $node.Source --check (Join-Path $root $js);if($LASTEXITCODE -ne 0){Fail "node --check falhou: $js"}}
        $nodeStatus='PASS'
    }

    if(Test-Path $Destino){$backup="${Destino}_BACKUP_$(Get-Date -Format 'yyyyMMdd_HHmmss')";Step "Movendo instalacao anterior para $backup";Move-Item -LiteralPath $Destino -Destination $backup -Force}
    Step "Instalando em $Destino"
    New-Item -ItemType Directory -Force -Path $Destino | Out-Null
    Get-ChildItem -Force $root | ForEach-Object {Copy-Item -LiteralPath $_.FullName -Destination $Destino -Recurse -Force}

    Step 'Criando atalhos local e online na Area de Trabalho'
    $desktop=[Environment]::GetFolderPath('Desktop')
    $localUri=([Uri](Join-Path $Destino 'JOGAR_REINOS_TRIBAIS.html')).AbsoluteUri
    @('[InternetShortcut]',"URL=$localUri",'IconIndex=0') | Set-Content -LiteralPath (Join-Path $desktop 'Reinos Tribais RT79.1 LOCAL.url') -Encoding ASCII
    @('[InternetShortcut]',"URL=$OnlineUrl",'IconIndex=0') | Set-Content -LiteralPath (Join-Path $desktop 'Reinos Tribais RT79.1 ONLINE.url') -Encoding ASCII

    $proof=[ordered]@{ok=$true;build=$Build;installed_at=(Get-Date).ToString('o');zip=$Zip;zip_sha256=$ZipHash;destination=$Destino;requirements=714;external_blockers=3;critical_hashes='PASS';all_file_checksums='PASS';html_identity='PASS';version_build='79 / 79.1';building_tiers='19x5=95 PASS';unit_visual_stages='10x4=40 PASS';paladin_overlays="$($hero.Count) PASS";asset_refs='PASS';node_validation=$nodeStatus;docker='NOT_REQUIRED';online_url=$OnlineUrl}
    $proof|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $Destino 'PROVA_INSTALACAO_RT79_1.json') -Encoding UTF8
    Write-Host '';Write-Host 'RT79.1 INSTALADA E VALIDADA.' -ForegroundColor Green;Write-Host "Destino: $Destino" -ForegroundColor Green
    if(-not $NaoAbrir){if($AbrirLocal){Start-Process (Join-Path $Destino 'JOGAR_REINOS_TRIBAIS.html')}else{Start-Process $OnlineUrl}}
}
finally{if(Test-Path $temp){Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}}
