param([switch]$ValidateOnly)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$PinnedLauncher = 'https://raw.githubusercontent.com/kaalflash12/reinos-tribais-online/7bacd0bb790dfcd239cadec45b93568f46784fd9/RT_REINO_TRIBAL_GHCLONE_TURSO_BROWSER_20260824.ps1'
$LauncherPath = Join-Path $env:TEMP 'RT_REINO_TRIBAL_TURSO_PESSOAL_BASE.ps1'
$BootstrapFinal = Join-Path $env:TEMP 'IMPLANTAR_REINO_TRIBAL_DENO_TURSO_FINAL.ps1'
$utf8Bom = New-Object Text.UTF8Encoding($true)

Write-Host '=== REINO TRIBAL FINAL - TURSO FREE + DENO ===' -ForegroundColor Cyan
Write-Host 'Organizacoes Turso v2 normalizadas + fallback v1; banco exclusivo; zero org paga.' -ForegroundColor Green

@($LauncherPath,$BootstrapFinal) | ForEach-Object { Remove-Item $_ -Force -ErrorAction SilentlyContinue }
Invoke-WebRequest -UseBasicParsing -Uri $PinnedLauncher -OutFile $LauncherPath -TimeoutSec 120
if (-not (Test-Path $LauncherPath) -or (Get-Item $LauncherPath).Length -le 0) { throw 'Falha baixando launcher base validado.' }
$raw=[IO.File]::ReadAllText($LauncherPath)
[IO.File]::WriteAllText($LauncherPath,$raw,$utf8Bom)

$tokens=$null;$errors=$null
[System.Management.Automation.Language.Parser]::ParseFile($LauncherPath,[ref]$tokens,[ref]$errors)|Out-Null
if($errors.Count){ throw ('Launcher base nao passou no parser: '+(($errors|ForEach-Object{$_.Message}) -join '; ')) }

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $LauncherPath -ValidateOnly
if($LASTEXITCODE -ne 0){ throw "Launcher base ValidateOnly falhou: $LASTEXITCODE" }
if(-not(Test-Path $BootstrapFinal)){ throw 'Bootstrap final nao foi gerado.' }

$texto=[IO.File]::ReadAllText($BootstrapFinal).Replace("`r`n","`n")
$orgStartMarker="  `$orgs = @(Turso-Request -Method GET -Path '/v1/organizations' -Token `$platformToken)"
$groupsMarker='  $groupsResp = Turso-Request -Method GET -Path "/v1/organizations/$orgSlug/groups" -Token $platformToken'
$dbMarker='  $dbList = Turso-Request -Method GET -Path "/v1/organizations/$orgSlug/databases" -Token $platformToken'
$orgStart=$texto.IndexOf($orgStartMarker,[StringComparison]::Ordinal)
if($orgStart -lt 0){ throw 'Inicio da selecao Turso antiga nao encontrado.' }
$groupsStart=$texto.IndexOf($groupsMarker,$orgStart,[StringComparison]::Ordinal)
if($groupsStart -lt 0){ throw 'Inicio do bloco de groups Turso nao encontrado.' }
$dbStart=$texto.IndexOf($dbMarker,$groupsStart,[StringComparison]::Ordinal)
if($dbStart -lt 0){ throw 'Fim do bloco de groups Turso nao encontrado.' }

$orgNovo=@'
  $orgs = @()
  try {
    $orgResponseV2 = Turso-Request -Method GET -Path '/v2/organizations' -Token $platformToken
    if ($null -ne $orgResponseV2 -and $orgResponseV2.PSObject.Properties['organizations']) {
      $orgs = @($orgResponseV2.organizations)
    } elseif ($null -ne $orgResponseV2) {
      $orgs = @($orgResponseV2)
    }
  } catch {
    Aviso 'Listagem Turso v2 indisponivel; usando fallback v1.'
    $orgs = @()
  }

  if ($orgs.Count -lt 1) {
    $orgResponseV1 = Turso-Request -Method GET -Path '/v1/organizations' -Token $platformToken
    if ($null -ne $orgResponseV1 -and $orgResponseV1.PSObject.Properties['organizations']) {
      $orgs = @($orgResponseV1.organizations)
    } elseif ($null -ne $orgResponseV1) {
      $orgs = @($orgResponseV1)
    }
  }
  $orgs = @($orgs | Where-Object { $_ -and ([string]$_.slug) })
  if ($orgs.Count -lt 1) { Falhar 'A conta Turso autenticada nao retornou nenhuma organizacao com slug utilizavel.' }

  $me = Turso-Request -Method GET -Path '/v1/current-user' -Token $platformToken
  $username = [string]$me.user.username
  $org = $null

  if ($username) {
    $org = $orgs | Where-Object { ([string]$_.slug) -eq $username } | Select-Object -First 1
  }
  if (-not $org -and $orgs.Count -eq 1) {
    $org = $orgs | Select-Object -First 1
  }
  if (-not $org) {
    $org = $orgs | Where-Object { ([string]$_.type) -eq 'personal' } | Sort-Object slug | Select-Object -First 1
  }
  if (-not $org) {
    $org = $orgs | Sort-Object slug | Select-Object -First 1
    if ($org) { Aviso 'Turso nao marcou uma organizacao como personal; usando a primeira organizacao acessivel sem criar plano pago.' }
  }
  if (-not $org) { Falhar 'A conta Turso autenticada nao retornou organizacao utilizavel.' }

  $orgSlug = [string]$org.slug
  if (-not $orgSlug) { Falhar 'A organizacao Turso selecionada nao possui slug.' }
  Ok "Organizacao Turso gratuita selecionada automaticamente: $orgSlug"

'@
$orgNovo=$orgNovo.Replace("`r`n","`n")
$texto=$texto.Substring(0,$orgStart)+$orgNovo+$texto.Substring($groupsStart)

$groupsStart=$texto.IndexOf($groupsMarker,[StringComparison]::Ordinal)
$dbStart=$texto.IndexOf($dbMarker,$groupsStart,[StringComparison]::Ordinal)
if($groupsStart -lt 0 -or $dbStart -lt 0){ throw 'Bloco de groups Turso desapareceu apos patch da organizacao.' }

$groupsNovo=@'
  $dedicatedGroupName = 'reino-tribal-prod'
  $groupsResp = Turso-Request -Method GET -Path "/v1/organizations/$orgSlug/groups" -Token $platformToken
  $groups = @($groupsResp.groups)
  $dedicatedGroup = $groups | Where-Object { ([string]$_.name) -eq $dedicatedGroupName } | Select-Object -First 1

  if ($dedicatedGroup) {
    $groupName = $dedicatedGroupName
    Ok "Group Turso exclusivo reutilizado: $groupName"
  } else {
    $location = ''
    try {
      $locResp = Turso-Request -Method GET -Path 'https://api.turso.tech/v1/locations' -Token $platformToken
      $keys = @($locResp.locations.PSObject.Properties.Name)
      if ($keys.Count -gt 0) {
        if ($keys -contains 'aws-us-east-1') { $location = 'aws-us-east-1' }
        else { $location = [string]($keys | Select-Object -First 1) }
      }
    } catch {
      Aviso 'Nao foi possivel listar locations para criar group dedicado; sera tentado fallback seguro.'
    }

    if ($location) {
      try {
        $createdGroup = Turso-Request -Method POST -Path "/v1/organizations/$orgSlug/groups" -Token $platformToken -Body @{ name=$dedicatedGroupName; location=$location }
        $groupName = [string]$createdGroup.group.name
        if (-not $groupName) { $groupName = $dedicatedGroupName }
        Ok "Group Turso exclusivo criado: $groupName"
      } catch {
        $groupName = ''
        Aviso 'O plano/arquitetura Turso nao permitiu criar outro placement group. O banco continuara isolado no group existente.'
      }
    } else {
      $groupName = ''
    }

    if (-not $groupName) {
      if ($groups.Count -lt 1) { Falhar 'Turso nao possui group existente e nao permitiu criar o group do Reino Tribal.' }
      $fallbackGroup = $groups | Select-Object -First 1
      $groupName = [string]$fallbackGroup.name
      if (-not $groupName) { Falhar 'Turso retornou group existente sem nome.' }
      Aviso "Usando placement group existente ($groupName); isolamento de dados permanece no banco exclusivo $TursoDatabase."
    }
  }

'@
$groupsNovo=$groupsNovo.Replace("`r`n","`n")
$texto=$texto.Substring(0,$groupsStart)+$groupsNovo+$texto.Substring($dbStart)

foreach($fragment in @($orgNovo,$groupsNovo)){
  if($fragment -match '\[0\]'){ throw 'O bloco Turso corrigido voltou a conter indexacao [0].' }
}
foreach($forbidden in @(
  'Nenhuma organização Turso independente foi encontrada nessa conta.',
  '$managed = @($orgs',
  'Organizações Turso independentes:',
  "Read-Host 'Escolha o número da organização para o Reino Tribal'",
  "Read-Host 'Turso Platform API Token'",
  'codeload.github.com',
  'Baixando branch isolada do Reino Tribal'
)){
  if($texto.Contains($forbidden)){ throw "Fluxo Turso antigo/manual reapareceu: $forbidden" }
}
foreach($needle in @(
  "Turso-Request -Method GET -Path '/v2/organizations'",
  "Turso-Request -Method GET -Path '/v1/organizations'",
  "PSObject.Properties['organizations']",
  "Turso-Request -Method GET -Path '/v1/current-user'",
  '$orgs.Count -eq 1',
  'Organizacao Turso gratuita selecionada automaticamente:',
  "`$dedicatedGroupName = 'reino-tribal-prod'",
  "'deploy','orgs','list','--json'",
  '$appMeta.productionUrl'
)){
  if(-not $texto.Contains($needle)){ throw "Contrato final ausente: $needle" }
}

[IO.File]::WriteAllText($BootstrapFinal,$texto,$utf8Bom)
$tokens=$null;$errors=$null
[System.Management.Automation.Language.Parser]::ParseFile($BootstrapFinal,[ref]$tokens,[ref]$errors)|Out-Null
if($errors.Count){ throw ('Bootstrap Turso final nao passou no parser: '+(($errors|ForEach-Object{$_.Message+' @ '+$_.Extent.StartLineNumber+':'+$_.Extent.StartColumnNumber}) -join "`n")) }

Write-Host 'PASS: TURSO = ORGANIZACOES V2/V1 NORMALIZADAS.' -ForegroundColor Green
Write-Host 'PASS: TURSO = ZERO INDEXACAO VAZIA NO BLOCO ORGANIZACAO/GROUP.' -ForegroundColor Green
Write-Host 'PASS: TURSO = BANCO REINO TRIBAL EXCLUSIVO, SEM CRIAR ORGANIZACAO PAGA.' -ForegroundColor Green
Write-Host 'PASS: TURSO = GROUP EXCLUSIVO QUANDO SUPORTADO, FALLBACK PARA GROUP EXISTENTE.' -ForegroundColor Green
Write-Host 'PASS: DENO = ORGANIZACAO AUTOMATICA + PRODUCTIONURL OFICIAL.' -ForegroundColor Green
Write-Host 'PASS: PARSER FINAL VALIDADO.' -ForegroundColor Green

if($ValidateOnly){ Write-Host 'TURSO_V2_V1_NO_INDEX_VALIDATE_PASS' -ForegroundColor Green; return }

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $BootstrapFinal
$code=$LASTEXITCODE
if($code -ne 0){ throw "Implantacao final parou no proximo erro real. Codigo: $code" }
