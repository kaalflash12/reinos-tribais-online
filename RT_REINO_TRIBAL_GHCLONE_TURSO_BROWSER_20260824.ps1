param([switch]$ValidateOnly)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$PinnedLauncher = 'https://raw.githubusercontent.com/kaalflash12/reinos-tribais-online/4240490a8e2e7d57d9da749ab6bc09a92755fdd8/EXECUTAR_REINO_TRIBAL_DENO_TURSO_FINAL.ps1'
$RunPath = Join-Path $env:TEMP 'RT_REINO_TRIBAL_GHCLONE_TURSO_BROWSER_RUN.ps1'
$BootstrapFinal = Join-Path $env:TEMP 'IMPLANTAR_REINO_TRIBAL_DENO_TURSO_FINAL.ps1'

Write-Host '=== RT FINAL 20260824 - GHCLONE + TURSO BROWSER + DENO ORG ===' -ForegroundColor Cyan
Write-Host 'Launcher unico: GitHub autenticado + Turso browser + Deno com organizacao explicita.' -ForegroundColor Green

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

# Deno Deploy atual exige contexto de organizacao. Reutiliza a variável da sessão/repo
# e pede o slug uma única vez apenas quando ainda não existe configuração persistida.
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
  if (-not $denoOrg) {
    Write-Host 'O Deno Deploy atual exige o slug da organizacao. O console oficial sera aberto.' -ForegroundColor Yellow
    Start-Process 'https://console.deno.com'
    $denoOrg = ([string](Read-Host 'Cole somente o slug da organizacao Deno mostrado na URL do console')).Trim()
  }
  if ($denoOrg -notmatch '^[a-z0-9](?:[a-z0-9-]{1,61}[a-z0-9])?$') {
    Falhar 'Slug da organizacao Deno invalido. Use apenas o slug exibido em console.deno.com/<slug>.'
  }
  Ok "Organizacao Deno definida: $denoOrg"

  $probe = Executar-Nativo -Exe $DenoExe -Args @('deploy','env','list','--org',$denoOrg,'--app',$DenoApp) -TimeoutSec 300 -Rotulo 'Autenticar/procurar app Deno'
  if ($probe.Code -ne 0) {
    Aviso 'Se o Deno abrir o navegador, confirme somente o login oficial. Depois o processo continua sozinho.'
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
    Exigir-Sucesso $create "Nao foi possivel criar/autenticar o app Deno exclusivo do Reino Tribal.`n$($create.Text)"
    Ok "App Deno criado/reutilizado: $DenoApp"
  } else {
    Ok "App Deno ja existe: $DenoApp"
  }
  Set-GitHubVariable $gh 'DENO_DEPLOY_ORG' $denoOrg

'@
$denoNovo = $denoNovo.Replace("`r`n","`n")
$texto = $texto.Substring(0,$denoStart) + $denoNovo + $texto.Substring($envStart)

# Env do Deno: --replace elimina prompt/hang em reexecução. update-contexts sem nomes
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

foreach ($needle in @(
  "'repo','clone',`$Repositorio,`$repoDir",
  "'--branch',`$Branch,'--depth','1','--single-branch'",
  'Obter-TursoPlatformTokenBrowser',
  'AcceptTcpClientAsync',
  'Start-Process $authUrl',
  "'variable','get','DENO_DEPLOY_ORG'",
  "'deploy','env','list','--org',`$denoOrg,'--app',`$DenoApp",
  "'deploy','create','.'",
  "'--org',`$denoOrg",
  "'deploy','env','load','--replace',`$envFile,'--org',`$denoOrg,'--app',`$DenoApp",
  "'deploy','env','update-contexts',`$name,'--org',`$denoOrg,'--app',`$DenoApp",
  "'deploy','--org',`$denoOrg,'--app',`$DenoApp,'--prod'",
  "Set-GitHubVariable `$gh 'DENO_DEPLOY_ORG' `$denoOrg"
)) {
  if (-not $texto.Contains($needle)) { throw "Contrato final ausente: $needle" }
}
foreach ($badContext in @("'production','development'", "'development','production'")) {
  if ($texto.Contains($badContext)) { throw "Contexto Deno antigo reapareceu: $badContext" }
}
if ($texto -match '\$Pid\b') { throw 'Variavel PowerShell reservada PID reapareceu.' }

[IO.File]::WriteAllText($BootstrapFinal,$texto,$utf8Bom)
$tokens=$null;$errors=$null
[System.Management.Automation.Language.Parser]::ParseFile($BootstrapFinal,[ref]$tokens,[ref]$errors) | Out-Null
if ($errors.Count -gt 0) {
  $msg = ($errors | ForEach-Object { $_.Message + ' @ ' + $_.Extent.StartLineNumber + ':' + $_.Extent.StartColumnNumber }) -join "`n"
  throw "Bootstrap final com Deno org nao passou no parser.`n$msg"
}

Write-Host 'PASS: launcher unico carregado.' -ForegroundColor Green
Write-Host 'PASS: fonte = GitHub CLI autenticado.' -ForegroundColor Green
Write-Host 'PASS: Turso = login no navegador/callback.' -ForegroundColor Green
Write-Host 'PASS: Deno = organizacao explicita em probe/create/env/deploy.' -ForegroundColor Green
Write-Host 'PASS: Deno env = replace deterministico + contextos All.' -ForegroundColor Green
Write-Host 'PASS: nenhum fluxo codeload/token manual reapareceu.' -ForegroundColor Green

if ($ValidateOnly) {
  Write-Host 'UNIQUE_DENO_ORG_ENV_TRANSFORM_PASS' -ForegroundColor Green
  return
}

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $BootstrapFinal
$code=$LASTEXITCODE
if ($code -ne 0) { throw "Launcher final parou no erro real. Codigo: $code" }