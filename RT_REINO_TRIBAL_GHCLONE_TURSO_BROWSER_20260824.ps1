param([switch]$ValidateOnly)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$PinnedLauncher = 'https://raw.githubusercontent.com/kaalflash12/reinos-tribais-online/4240490a8e2e7d57d9da749ab6bc09a92755fdd8/EXECUTAR_REINO_TRIBAL_DENO_TURSO_FINAL.ps1'
$RunPath = Join-Path $env:TEMP 'RT_REINO_TRIBAL_GHCLONE_TURSO_BROWSER_RUN.ps1'
$BootstrapFinal = Join-Path $env:TEMP 'IMPLANTAR_REINO_TRIBAL_DENO_TURSO_FINAL.ps1'

Write-Host '=== RT FINAL 20260824 - GHCLONE + TURSO BROWSER + DENO AUTO ===' -ForegroundColor Cyan
Write-Host 'Launcher unico: GitHub autenticado + Turso browser + Deno com organizacao automatica.' -ForegroundColor Green

foreach ($old in @(
  (Join-Path $env:TEMP 'EXECUTAR_REINO_TRIBAL_DENO_TURSO_FINAL.ps1'),
  (Join-Path $env:TEMP 'IMPLANTAR_REINO_TRIBAL_DENO_TURSO_FINAL.ps1'),
  (Join-Path $env:TEMP 'RT_BASE_LAUNCHER_VALIDADO.ps1'),
  $RunPath
)) {
  Remove-Item $old -Force -ErrorAction SilentlyContinue
}

Invoke-WebRequest -UseBasicParsing -Uri $PinnedLauncher -OutFile $RunPath -TimeoutSec 120
if (-not (Test-Path $RunPath) -or (Get-Item $RunPath).Length -le 0) {
  throw 'Falha baixando o launcher GHCLONE/Turso Browser validado.'
}

$txt = [IO.File]::ReadAllText($RunPath)
$utf8Bom = New-Object Text.UTF8Encoding($true)
[IO.File]::WriteAllText($RunPath,$txt,$utf8Bom)

$tokens=$null
$errors=$null
[System.Management.Automation.Language.Parser]::ParseFile($RunPath,[ref]$tokens,[ref]$errors) | Out-Null
if ($errors.Count -gt 0) {
  $msg = ($errors | ForEach-Object { $_.Message + ' @ ' + $_.Extent.StartLineNumber + ':' + $_.Extent.StartColumnNumber }) -join "`n"
  throw "Launcher GHCLONE nao passou no parser.`n$msg"
}

$source = [IO.File]::ReadAllText($RunPath)
foreach ($needle in @(
  'Fonte da branch: GitHub CLI autenticado, sem codeload anonimo.',
  '''repo'',''clone'',$Repositorio,$repoDir',
  '''--branch'',$Branch,''--depth'',''1'',''--single-branch''',
  'Obter-TursoPlatformTokenBrowser'
)) {
  if (-not $source.Contains($needle)) { throw "Launcher pinado perdeu contrato obrigatorio: $needle" }
}

# Gera o bootstrap totalmente transformado, sem provisionar nada.
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $RunPath -ValidateOnly
if ($LASTEXITCODE -ne 0) { throw "Transformacao GHCLONE/Turso falhou: $LASTEXITCODE" }
if (-not (Test-Path $BootstrapFinal)) { throw 'Bootstrap final nao foi gerado.' }

$texto = [IO.File]::ReadAllText($BootstrapFinal).Replace("`r`n","`n")
foreach ($forbidden in @('codeload.github.com','Baixando branch isolada do Reino Tribal',"Read-Host 'Turso Platform API Token'")) {
  if ($texto.Contains($forbidden)) { throw "Fluxo antigo reapareceu no bootstrap final: $forbidden" }
}

# Deno Deploy atual: autentica pelo navegador e lista as organizacoes via CLI/JSON.
# Nao pede slug manual. Se ainda nao houver organizacao, abre o console e faz polling limitado.
$denoStartMarker = "  Etapa 'Deno Deploy: app exclusivo do Reino Tribal'"
$envMarker = "  `$envFile = Join-Path `$WorkRoot '.env.reino-tribal.production'"
$denoStart = $texto.IndexOf($denoStartMarker,[StringComparison]::Ordinal)
if ($denoStart -lt 0) { throw 'Secao Deno original nao encontrada.' }
$envStart = $texto.IndexOf($envMarker,$denoStart,[StringComparison]::Ordinal)
if ($envStart -lt 0) { throw 'Fim da secao Deno original nao encontrado.' }

$denoNovo = @'
  Etapa 'Deno Deploy: app exclusivo do Reino Tribal'
  $denoOrg = [string]$env:DENO_DEPLOY_ORG
  if (-not $denoOrg) {
    $orgRepo = Executar-Nativo -Exe $gh -Args @('variable','get','DENO_DEPLOY_ORG','-R',$Repositorio) -TimeoutSec 30 -Rotulo 'Ler DENO_DEPLOY_ORG do GitHub'
    if ($orgRepo.Code -eq 0 -and $orgRepo.Text) { $denoOrg = $orgRepo.Text.Trim() }
  }

  Aviso 'Se o Deno ainda nao estiver autenticado, confirme somente o login oficial que abrir no navegador.'
  $orgList = Executar-Nativo -Exe $DenoExe -Args @('deploy','orgs','list','--json') -TimeoutSec 300 -Rotulo 'Login/listar organizacoes Deno'
  Exigir-Sucesso $orgList "Nao foi possivel autenticar/listar organizacoes do Deno Deploy.`n$($orgList.Text)"
  try { $denoOrgs = @($orgList.Text | ConvertFrom-Json) } catch { Falhar "Deno retornou JSON de organizacoes invalido.`n$($orgList.Text)" }

  if ($denoOrgs.Count -lt 1) {
    Aviso 'A conta Deno ainda nao possui organizacao. O console oficial sera aberto; crie/confirme uma organizacao. O script detectara automaticamente.'
    Start-Process 'https://console.deno.com'
    for ($attempt=1; $attempt -le 24 -and $denoOrgs.Count -lt 1; $attempt++) {
      Start-Sleep -Seconds 5
      $retryOrgs = Executar-Nativo -Exe $DenoExe -Args @('deploy','orgs','list','--json') -TimeoutSec 45 -Rotulo "Detectar organizacao Deno ($attempt/24)"
      if ($retryOrgs.Code -eq 0 -and $retryOrgs.Text) {
        try { $denoOrgs = @($retryOrgs.Text | ConvertFrom-Json) } catch { $denoOrgs = @() }
      }
    }
  }
  if ($denoOrgs.Count -lt 1) { Falhar 'Nenhuma organizacao Deno foi detectada apos o login/criacao no console oficial.' }

  $slugs = @($denoOrgs | ForEach-Object { [string]$_.slug } | Where-Object { $_ })
  if ($denoOrg -and $slugs -notcontains $denoOrg) {
    Aviso "DENO_DEPLOY_ORG salvo ($denoOrg) nao esta acessivel nesta conta; selecao automatica sera refeita."
    $denoOrg = ''
  }

  if (-not $denoOrg) {
    # Primeiro reutiliza a organizacao que ja contenha o app exclusivo.
    foreach ($candidate in ($slugs | Sort-Object)) {
      $existing = Executar-Nativo -Exe $DenoExe -Args @('deploy','apps','get','--org',$candidate,'--app',$DenoApp,'--json') -TimeoutSec 45 -Rotulo "Procurar $DenoApp em $candidate"
      if ($existing.Code -eq 0) { $denoOrg = $candidate; break }
    }
    # Se o app ainda nao existir, prefere o slug da conta; senao usa o primeiro slug de forma deterministica.
    if (-not $denoOrg -and $slugs -contains 'kaalflash12') { $denoOrg = 'kaalflash12' }
    if (-not $denoOrg) { $denoOrg = @($slugs | Sort-Object | Select-Object -First 1)[0] }
  }

  if ($denoOrg -notmatch '^[a-z0-9](?:[a-z0-9-]{1,61}[a-z0-9])?$') {
    Falhar "Slug da organizacao Deno retornado pela propria plataforma e invalido: $denoOrg"
  }
  Ok "Organizacao Deno selecionada automaticamente: $denoOrg"

  $probe = Executar-Nativo -Exe $DenoExe -Args @('deploy','apps','get','--org',$denoOrg,'--app',$DenoApp,'--json') -TimeoutSec 60 -Rotulo 'Procurar app Deno existente'
  if ($probe.Code -ne 0) {
    $create = Executar-Nativo -Exe $DenoExe -Args @(
      'deploy','create','.',
      '--org',$denoOrg,
      '--app',$DenoApp,
      '--source','local',
      '--runtime-mode','dynamic',
      '--entrypoint','deno/main.js',
      '--build-timeout','5',
      '--build-memory-limit','1024',
      '--region','global',
      '--no-wait'
    ) -Diretorio $workPath -TimeoutSec 600 -Rotulo 'Criar app Deno reino-tribal-api'
    Exigir-Sucesso $create "Nao foi possivel criar o app Deno exclusivo do Reino Tribal.`n$($create.Text)"
    Ok "App Deno criado: $DenoApp"
  } else {
    Ok "App Deno ja existe: $DenoApp"
  }
  Set-GitHubVariable $gh 'DENO_DEPLOY_ORG' $denoOrg

'@
$denoNovo = $denoNovo.Replace("`r`n","`n")
$texto = $texto.Substring(0,$denoStart) + $denoNovo + $texto.Substring($envStart)

# Env do Deno: --replace elimina prompt/hang em reexecucao. update-contexts sem nomes
# define context_ids=null (All), evitando nomes de contexto dependentes da plataforma.
$replacements = @(
  @("@('deploy','env','load',`$envFile,'--app',`$DenoApp)", "@('deploy','env','load','--replace',`$envFile,'--org',`$denoOrg,'--app',`$DenoApp)"),
  @("@('deploy','env','update-contexts',`$name,'production','development','--app',`$DenoApp)", "@('deploy','env','update-contexts',`$name,'--org',`$denoOrg,'--app',`$DenoApp)"),
  @("@('deploy','--app',`$DenoApp,'--prod')", "@('deploy','--org',`$denoOrg,'--app',`$DenoApp,'--prod')")
)
foreach ($pair in $replacements) {
  if (-not $texto.Contains($pair[0])) { throw "Comando Deno esperado nao encontrado para patch: $($pair[0])" }
  $texto = $texto.Replace($pair[0],$pair[1])
}

# URL de producao: usa a saida JSON oficial de apps get, nao regex do texto de deploy.
$urlStartMarker = "  `$urls = [regex]::Matches(`$deploy.Text,'https://[A-Za-z0-9.-]+\\.deno\\.net')"
$testsMarker = "  Etapa 'Testes reais: Turso + conta + save/load + ADM'"
$urlStart = $texto.IndexOf($urlStartMarker,[StringComparison]::Ordinal)
$testsStart = $texto.IndexOf($testsMarker,[StringComparison]::Ordinal)
if ($urlStart -lt 0 -or $testsStart -lt 0 -or $testsStart -le $urlStart) { throw 'Bloco antigo de descoberta da URL Deno nao foi encontrado.' }
$urlNovo = @'
  $appInfo = Executar-Nativo -Exe $DenoExe -Args @('deploy','apps','get','--org',$denoOrg,'--app',$DenoApp,'--json') -TimeoutSec 60 -Rotulo 'Obter URL oficial do backend Deno'
  Exigir-Sucesso $appInfo "Deploy terminou, mas apps get falhou.`n$($appInfo.Text)"
  try { $appMeta = $appInfo.Text | ConvertFrom-Json } catch { Falhar "apps get retornou JSON invalido.`n$($appInfo.Text)" }
  $backend = ([string]$appMeta.productionUrl).TrimEnd('/')
  if (-not $backend -or $backend -notmatch '^https://') { Falhar "Deno nao retornou productionUrl valida para $DenoApp." }
  Ok "Backend: $backend"

'@
$urlNovo = $urlNovo.Replace("`r`n","`n")
$texto = $texto.Substring(0,$urlStart) + $urlNovo + $texto.Substring($testsStart)

foreach ($needle in @(
  "'repo','clone',`$Repositorio,`$repoDir",
  "'--branch',`$Branch,'--depth','1','--single-branch'",
  'Obter-TursoPlatformTokenBrowser',
  'AcceptTcpClientAsync',
  'Start-Process $authUrl',
  "'deploy','orgs','list','--json'",
  "'deploy','apps','get','--org',`$candidate,'--app',`$DenoApp,'--json'",
  "'deploy','apps','get','--org',`$denoOrg,'--app',`$DenoApp,'--json'",
  "'deploy','create','.'",
  "'--org',`$denoOrg",
  "'deploy','env','load','--replace',`$envFile,'--org',`$denoOrg,'--app',`$DenoApp",
  "'deploy','env','update-contexts',`$name,'--org',`$denoOrg,'--app',`$DenoApp",
  "'deploy','--org',`$denoOrg,'--app',`$DenoApp,'--prod'",
  "Set-GitHubVariable `$gh 'DENO_DEPLOY_ORG' `$denoOrg",
  '$appMeta.productionUrl'
)) {
  if (-not $texto.Contains($needle)) { throw "Contrato final ausente: $needle" }
}
foreach ($forbidden in @(
  'codeload.github.com',
  'Baixando branch isolada do Reino Tribal',
  "Read-Host 'Turso Platform API Token'",
  "Read-Host 'Cole somente o slug da organizacao Deno",
  "'production','development'"
)) {
  if ($texto.Contains($forbidden)) { throw "Fluxo antigo/manual reapareceu: $forbidden" }
}
if ($texto -match '\$Pid\b') { throw 'Variavel PowerShell reservada PID reapareceu.' }

[IO.File]::WriteAllText($BootstrapFinal,$texto,$utf8Bom)
$tokens=$null;$errors=$null
[System.Management.Automation.Language.Parser]::ParseFile($BootstrapFinal,[ref]$tokens,[ref]$errors) | Out-Null
if ($errors.Count -gt 0) {
  $msg = ($errors | ForEach-Object { $_.Message + ' @ ' + $_.Extent.StartLineNumber + ':' + $_.Extent.StartColumnNumber }) -join "`n"
  throw "Bootstrap final automatico nao passou no parser.`n$msg"
}

Write-Host 'PASS: launcher unico carregado.' -ForegroundColor Green
Write-Host 'PASS: fonte = GitHub CLI autenticado.' -ForegroundColor Green
Write-Host 'PASS: Turso = login no navegador/callback.' -ForegroundColor Green
Write-Host 'PASS: Deno = login navegador + organizacao detectada automaticamente.' -ForegroundColor Green
Write-Host 'PASS: Deno env = replace deterministico + contextos All.' -ForegroundColor Green
Write-Host 'PASS: URL Deno = productionUrl oficial via apps get --json.' -ForegroundColor Green
Write-Host 'PASS: nenhum codeload/token/slug manual reapareceu.' -ForegroundColor Green

if ($ValidateOnly) {
  Write-Host 'UNIQUE_DENO_AUTO_ORG_PRODUCTION_URL_PASS' -ForegroundColor Green
  return
}

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $BootstrapFinal
$code=$LASTEXITCODE
if ($code -ne 0) { throw "Launcher final parou no erro real. Codigo: $code" }