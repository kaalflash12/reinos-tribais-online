param([switch]$ValidateOnly)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Base imutavel ja validada: Turso browser/callback + Deno recovery.
$BaseLauncher = 'https://raw.githubusercontent.com/kaalflash12/reinos-tribais-online/a47143a7f5f662ea1f7aed6f64cab83b5bc6312d/EXECUTAR_REINO_TRIBAL_DENO_TURSO_FINAL.ps1'
$LauncherTmp = Join-Path $env:TEMP 'RT_BASE_LAUNCHER_VALIDADO.ps1'
$BootstrapFinal = Join-Path $env:TEMP 'IMPLANTAR_REINO_TRIBAL_DENO_TURSO_FINAL.ps1'

Write-Host '=== REINO TRIBAL - DENO + TURSO + GITHUB PAGES ===' -ForegroundColor Cyan
Write-Host 'ZERO VERCEL / ZERO WSL / ZERO INFRAESTRUTURA DE OUTRO JOGO.' -ForegroundColor Green
Write-Host 'Fonte da branch: GitHub CLI autenticado, sem codeload anonimo.' -ForegroundColor Green

Remove-Item $LauncherTmp,$BootstrapFinal -Force -ErrorAction SilentlyContinue
Invoke-WebRequest -UseBasicParsing -Uri $BaseLauncher -OutFile $LauncherTmp -TimeoutSec 120
if (-not (Test-Path $LauncherTmp) -or (Get-Item $LauncherTmp).Length -le 0) {
  throw 'Falha baixando launcher-base validado.'
}

# Windows PowerShell 5.1: grava BOM para preservar os textos do launcher-base.
$baseText = [IO.File]::ReadAllText($LauncherTmp)
[IO.File]::WriteAllText($LauncherTmp,$baseText,(New-Object Text.UTF8Encoding($true)))

# Executa exatamente a transformacao Turso/Deno ja validada, mas SEM provisionar.
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $LauncherTmp -ValidateOnly
if ($LASTEXITCODE -ne 0) {
  throw "Transformacao-base Turso/Deno falhou. Codigo: $LASTEXITCODE"
}
if (-not (Test-Path $BootstrapFinal)) {
  throw 'Bootstrap transformado nao foi gerado pela base validada.'
}

$texto = [IO.File]::ReadAllText($BootstrapFinal).Replace("`r`n","`n")

# Remove o caminho que falhou no PC: download anonimo por codeload + Expand-Archive.
$inicioMarcador = "  Etapa 'Baixando branch isolada do Reino Tribal'"
$fimMarcador = "  `$check = Executar-Nativo -Exe `$DenoExe -Args @('check','deno/main.js')"
$inicio = $texto.IndexOf($inicioMarcador,[StringComparison]::Ordinal)
if ($inicio -lt 0) { throw 'Bloco antigo de obtencao da branch nao foi encontrado.' }
$fim = $texto.IndexOf($fimMarcador,$inicio,[StringComparison]::Ordinal)
if ($fim -lt 0) { throw 'Fim do bloco antigo de obtencao da branch nao foi encontrado.' }

$blocoAntigo = $texto.Substring($inicio,$fim-$inicio)
if (-not $blocoAntigo.Contains('codeload.github.com')) {
  throw 'Contrato inesperado: bloco antigo nao contem codeload; nada foi executado.'
}

$blocoNovo = @'
  Etapa 'Obtendo branch isolada via GitHub autenticado'
  $repoDir = Join-Path $WorkRoot 'repo'
  Remove-Item $repoDir -Recurse -Force -ErrorAction SilentlyContinue

  $git = Get-Command git.exe -ErrorAction SilentlyContinue
  if (-not $git) { Falhar 'Git nao encontrado. GitHub CLI precisa do git.exe para clonar a branch.' }
  $gitv = Executar-Nativo -Exe $git.Source -Args @('--version') -TimeoutSec 20 -Rotulo 'Validar Git'
  Exigir-Sucesso $gitv 'git.exe existe, mas nao executa.'

  $clone = Executar-Nativo -Exe $gh -Args @(
    'repo','clone',$Repositorio,$repoDir,
    '--','--branch',$Branch,'--depth','1','--single-branch'
  ) -TimeoutSec 180 -Rotulo 'Clonar rt-turso-migration via GitHub CLI autenticado'
  Exigir-Sucesso $clone "Falha clonando a branch autenticada do Reino Tribal.`n$($clone.Text)"

  $workPath = $repoDir
  if (-not (Test-Path (Join-Path $workPath 'deno\main.js'))) {
    Falhar 'Clone concluiu, mas deno/main.js nao existe na branch obtida.'
  }
  foreach ($required in @('deno.json','deno\main.js','api\reino.js','api\admin.js','backend\turso\schema.sql')) {
    if (-not (Test-Path (Join-Path $workPath $required))) { Falhar "Arquivo obrigatorio ausente apos clone: $required" }
  }
  Ok 'Branch rt-turso-migration obtida pelo GitHub autenticado.'

'@
$blocoNovo = $blocoNovo.Replace("`r`n","`n")
$texto = $texto.Substring(0,$inicio) + $blocoNovo + $texto.Substring($fim)

# Contratos: codeload desapareceu; clone autenticado aparece uma unica vez.
if ($texto.Contains('codeload.github.com')) {
  throw 'codeload ainda existe no bootstrap final. Nada foi executado.'
}
foreach ($needle in @(
  "'repo','clone',`$Repositorio,`$repoDir",
  "'--branch',`$Branch,'--depth','1','--single-branch'",
  'Clonar rt-turso-migration via GitHub CLI autenticado',
  'Branch rt-turso-migration obtida pelo GitHub autenticado.',
  'Obter-TursoPlatformTokenBrowser',
  'AcceptTcpClientAsync',
  'Start-Process $authUrl'
)) {
  if (-not $texto.Contains($needle)) { throw "Contrato final ausente: $needle" }
}
if ($texto.Contains("Read-Host 'Turso Platform API Token'")) {
  throw 'Prompt manual do token Turso reapareceu. Nada foi executado.'
}
if ($texto -match '\$Pid\b') {
  throw 'Variavel PowerShell reservada PID reapareceu. Nada foi executado.'
}

[IO.File]::WriteAllText($BootstrapFinal,$texto,(New-Object Text.UTF8Encoding($true)))
$tokens=$null
$errors=$null
[System.Management.Automation.Language.Parser]::ParseFile($BootstrapFinal,[ref]$tokens,[ref]$errors) | Out-Null
if ($errors.Count -gt 0) {
  $msg = ($errors | ForEach-Object { $_.Message + ' @ ' + $_.Extent.StartLineNumber + ':' + $_.Extent.StartColumnNumber }) -join "`n"
  throw "Bootstrap final nao passou no parser.`n$msg"
}

Write-Host 'PASS: TURSO = LOGIN NO NAVEGADOR, SEM COPIAR TOKEN.' -ForegroundColor Green
Write-Host 'PASS: BRANCH = GITHUB CLI AUTENTICADO, SEM CODELOAD.' -ForegroundColor Green
Write-Host 'PASS: CLONE LIMITADO A DEPTH 1 E TIMEOUT.' -ForegroundColor Green
Write-Host 'PASS: PARSER FINAL VALIDADO.' -ForegroundColor Green

if ($ValidateOnly) {
  Write-Host 'FINAL_GITHUB_CLONE_TRANSFORM_PASS' -ForegroundColor Green
  return
}

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $BootstrapFinal
$codigo=$LASTEXITCODE
if ($codigo -ne 0) {
  throw "Implantacao parou no proximo erro real. Codigo de saida: $codigo"
}
