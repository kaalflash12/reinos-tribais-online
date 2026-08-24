param([switch]$ValidateOnly)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$PinnedLauncher = 'https://raw.githubusercontent.com/kaalflash12/reinos-tribais-online/7bacd0bb790dfcd239cadec45b93568f46784fd9/RT_REINO_TRIBAL_GHCLONE_TURSO_BROWSER_20260824.ps1'
$LauncherPath = Join-Path $env:TEMP 'RT_REINO_TRIBAL_TURSO_PESSOAL_BASE.ps1'
$BootstrapFinal = Join-Path $env:TEMP 'IMPLANTAR_REINO_TRIBAL_DENO_TURSO_FINAL.ps1'
$utf8Bom = New-Object Text.UTF8Encoding($true)

Write-Host '=== REINO TRIBAL FINAL - TURSO PESSOAL FREE + DENO ===' -ForegroundColor Cyan
Write-Host 'Sem organizacao Turso paga. Banco exclusivo na organizacao pessoal da conta.' -ForegroundColor Green

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
  $orgs = @(Turso-Request -Method GET -Path '/v1/organizations' -Token $platformToken)
  if ($orgs.Count -lt 1) { Falhar 'A conta Turso autenticada nao retornou nenhuma organizacao acessivel.' }

  $me = Turso-Request -Method GET -Path '/v1/current-user' -Token $platformToken
  $username = [string]$me.user.username
  $org = $null

  if ($username) {
    $org = @($orgs | Where-Object { ([string]$_.slug) -eq $username } | Select-Object -First 1)[0]
  }
  if (-not $org -and $orgs.Count -eq 1) {
    $org = $orgs[0]
  }
  if (-not $org) {
    $org = @($orgs | Where-Object { ([string]$_.type) -eq 'personal' } | Sort-Object slug | Select-Object -First 1)[0]
  }
  if (-not $org) {
    Falhar 'A conta Turso nao expoe uma organizacao pessoal identificavel no plano gratuito. Nenhuma organizacao paga sera criada automaticamente.'
  }

  $orgSlug = [string]$org.slug
  if (-not $orgSlug) { Falhar 'A organizacao pessoal Turso selecionada nao possui slug.' }
  Ok "Organizacao pessoal Turso selecionada automaticamente: $orgSlug"

'@
$orgNovo=$orgNovo.Replace("`r`n","`n")
$texto=$texto.Substring(0,$orgStart)+$orgNovo+$texto.Substring($groupsStart)

# Recalcula marcadores depois da troca da selecao de organizacao.
$groupsStart=$texto.IndexOf($groupsMarker,[StringComparison]::Ordinal)
$dbStart=$texto.IndexOf($dbMarker,$groupsStart,[StringComparison]::Ordinal)
if($groupsStart -lt 0 -or $dbStart -lt 0){ throw 'Bloco de groups Turso desapareceu apos patch da organizacao.' }

$groupsNovo=@'
  $dedicatedGroupName = 'reino-tribal-prod'
  $groupsResp = Turso-Request -Method GET -Path "/v1/organizations/$orgSlug/groups" -Token $platformToken
  $groups = @($groupsResp.groups)
  $dedicatedGroup = @($groups | Where-Object { ([string]$_.name) -eq $dedicatedGroupName } | Select-Object -First 1)[0]

  if ($dedicatedGroup) {
    $groupName = $dedicatedGroupName
    Ok "Group Turso exclusivo reutilizado: $groupName"
  } else {
    $location = ''
    try {
      $locResp = Turso-Request -Method GET -Path 'https://api.turso.tech/v1/locations' -Token $platformToken
      $keys = @($locResp.locations.PSObject.Properties.Name)
      if ($keys.Count -gt 0) {
        $location = if ($keys -contains 'aws-us-east-1') { 'aws-us-east-1' } else { [string]$keys[0] }
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
      $groupName = [string]$groups[0].name
      if (-not $groupName) { Falhar 'Turso retornou group existente sem nome.' }
      Aviso "Usando placement group existente ($groupName); isolamento de dados permanece no banco exclusivo $TursoDatabase."
    }
  }

'@
$groupsNovo=$groupsNovo.Replace("`r`n","`n")
$texto=$texto.Substring(0,$groupsStart)+$groupsNovo+$texto.Substring($dbStart)

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
  "Turso-Request -Method GET -Path '/v1/current-user'",
  '$orgs.Count -eq 1',
  "([string]`$_.type) -eq 'personal'",
  'Organizacao pessoal Turso selecionada automaticamente:',
  "`$dedicatedGroupName = 'reino-tribal-prod'",
  'Group Turso exclusivo',
  "'/v1/organizations' -Token `$platformToken",
  "'deploy','orgs','list','--json'",
  '$appMeta.productionUrl'
)){
  if(-not $texto.Contains($needle)){ throw "Contrato final ausente: $needle" }
}

[IO.File]::WriteAllText($BootstrapFinal,$texto,$utf8Bom)
$tokens=$null;$errors=$null
[System.Management.Automation.Language.Parser]::ParseFile($BootstrapFinal,[ref]$tokens,[ref]$errors)|Out-Null
if($errors.Count){ throw ('Bootstrap Turso pessoal nao passou no parser: '+(($errors|ForEach-Object{$_.Message+' @ '+$_.Extent.StartLineNumber+':'+$_.Extent.StartColumnNumber}) -join "`n")) }

Write-Host 'PASS: TURSO = ORGANIZACAO PESSOAL GRATUITA.' -ForegroundColor Green
Write-Host 'PASS: TURSO = BANCO REINO TRIBAL EXCLUSIVO, SEM CRIAR ORGANIZACAO PAGA.' -ForegroundColor Green
Write-Host 'PASS: TURSO = GROUP EXCLUSIVO QUANDO SUPORTADO, FALLBACK PARA GROUP EXISTENTE SEM COMPARTILHAR BANCO.' -ForegroundColor Green
Write-Host 'PASS: TURSO = ZERO ESCOLHA MANUAL DE ORGANIZACAO.' -ForegroundColor Green
Write-Host 'PASS: DENO = ORGANIZACAO AUTOMATICA + PRODUCTIONURL OFICIAL.' -ForegroundColor Green
Write-Host 'PASS: PARSER FINAL VALIDADO.' -ForegroundColor Green

if($ValidateOnly){ Write-Host 'TURSO_PERSONAL_FREE_VALIDATE_PASS' -ForegroundColor Green; return }

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $BootstrapFinal
$code=$LASTEXITCODE
if($code -ne 0){ throw "Implantacao final parou no proximo erro real. Codigo: $code" }
