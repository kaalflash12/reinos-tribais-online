$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Origem = 'https://raw.githubusercontent.com/kaalflash12/reinos-tribais-online/rt-turso-migration/CONFIGURAR_TURSO_REINO_TRIBAL_AUTO.ps1'
$Destino = Join-Path $env:TEMP 'REINO_TRIBAL_AUTO_CORRIGIDO_V2.ps1'

Write-Host '=== REINO TRIBAL - HOTFIX WINDOWS POWERSHELL V2 ===' -ForegroundColor Cyan
Write-Host 'Baixando o bootstrap de producao...' -ForegroundColor Cyan
Remove-Item $Destino -Force -ErrorAction SilentlyContinue
Invoke-WebRequest -UseBasicParsing -Uri $Origem -OutFile $Destino -TimeoutSec 120
if (-not (Test-Path $Destino) -or (Get-Item $Destino).Length -le 0) {
  throw 'Falha ao baixar o bootstrap de producao.'
}

$texto = [IO.File]::ReadAllText($Destino)

# 1) Windows PowerShell 5.1 trata $HOME como variavel automatica somente leitura.
$texto = [regex]::Replace($texto, '\$home\b', '$vercelCliHome')
if ([regex]::IsMatch($texto, '\$home\b')) {
  throw 'Hotfix HOME incompleto. Nada sera executado.'
}

# 2) Native commands que escrevem em STDERR com exit 0 viram NativeCommandError quando
# ErrorActionPreference=Stop e a saida e redirecionada. Centraliza essas verificacoes.
$anchor = "function Falhar([string]`$Texto) { throw `$Texto }"
$helper = @'
function Testar-NativoSilencioso([string]$Exe, [string[]]$Args) {
  $anterior = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    & $Exe @Args 1>$null 2>$null
    return [int]$LASTEXITCODE
  } finally {
    $ErrorActionPreference = $anterior
  }
}
'@
if (-not $texto.Contains($anchor)) { throw 'Nao encontrei o ponto de injecao do helper nativo.' }
$texto = $texto.Replace($anchor, $anchor + "`r`n`r`n" + $helper.Trim())

$substituicoes = [ordered]@{
  '& $system.Source --version *> $null' = '$nativeCode = Testar-NativoSilencioso $system.Source @(''--version'')'
  '& $existing.FullName --version *> $null' = '$nativeCode = Testar-NativoSilencioso $existing.FullName @(''--version'')'
  '& $gh.FullName --version *> $null' = '$nativeCode = Testar-NativoSilencioso $gh.FullName @(''--version'')'
  '& $bin --version *> $null' = '$nativeCode = Testar-NativoSilencioso $bin @(''--version'')'
  '& $gh auth status *> $null' = '$nativeCode = Testar-NativoSilencioso $gh @(''auth'',''status'')'
  '& $gh repo view $Repositorio *> $null' = '$nativeCode = Testar-NativoSilencioso $gh @(''repo'',''view'',$Repositorio)'
  '& $vercel whoami --scope $VercelScope *> $null' = '$nativeCode = Testar-NativoSilencioso $vercel @(''whoami'',''--scope'',$VercelScope)'
  '& $Vercel env rm $Nome production --yes --scope $VercelScope *> $null' = '$null = Testar-NativoSilencioso $Vercel @(''env'',''rm'',$Nome,''production'',''--yes'',''--scope'',$VercelScope)'
}
foreach ($par in $substituicoes.GetEnumerator()) {
  $texto = $texto.Replace([string]$par.Key, [string]$par.Value)
}

$texto = $texto.Replace('if ($LASTEXITCODE -eq 0) { return $system.Source }','if ($nativeCode -eq 0) { return $system.Source }')
$texto = $texto.Replace('if ($LASTEXITCODE -eq 0) { return $existing.FullName }','if ($nativeCode -eq 0) { return $existing.FullName }')
$texto = $texto.Replace("if (`$LASTEXITCODE -ne 0) { Falhar 'gh.exe portátil não executa.' }", "if (`$nativeCode -ne 0) { Falhar 'gh.exe portátil não executa.' }")
$texto = $texto.Replace('if ($LASTEXITCODE -eq 0) { return $bin }','if ($nativeCode -eq 0) { return $bin }')
$texto = $texto.Replace("if (`$LASTEXITCODE -ne 0) { Falhar 'Vercel CLI local não executa.' }", "if (`$nativeCode -ne 0) { Falhar 'Vercel CLI local não executa.' }")
$texto = $texto.Replace('if ($LASTEXITCODE -ne 0) { Falhar "A conta GitHub autenticada não acessa $Repositorio." }','if ($nativeCode -ne 0) { Falhar "A conta GitHub autenticada não acessa $Repositorio." }')
$texto = $texto.Replace("if (`$LASTEXITCODE -ne 0) { Falhar 'A Vercel continua sem autenticação após o login.' }", "if (`$nativeCode -ne 0) { Falhar 'A Vercel continua sem autenticação após o login.' }")

# Capturar() tambem precisa aceitar stderr normal sem disparar NativeCommandError.
$rxCapturar = '(?ms)function Capturar\(\[string\]\$Exe, \[string\[\]\]\$Args\) \{\r?\n  \$out = & \$Exe @Args 2>&1\r?\n  \[pscustomobject\]@\{ Code=\$LASTEXITCODE; Text=\(\(\$out \| ForEach-Object \{ "\$_" \}\) -join "`n"\)\.Trim\(\) \}\r?\n\}'
$capturarNovo = @'
function Capturar([string]$Exe, [string[]]$Args) {
  $anterior = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    $out = & $Exe @Args 2>&1
    $code = [int]$LASTEXITCODE
  } finally {
    $ErrorActionPreference = $anterior
  }
  [pscustomobject]@{ Code=$code; Text=(($out | ForEach-Object { "$_" }) -join "`n").Trim() }
}
'@
$antesCapturar = $texto
$texto = [regex]::Replace($texto, $rxCapturar, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $capturarNovo.Trim() })
if ($texto -eq $antesCapturar) { throw 'Nao consegui substituir Capturar(). Nada sera executado.' }

$proibidos = @(
  '& $bin --version *> $null',
  '& $system.Source --version *> $null',
  '& $existing.FullName --version *> $null',
  '& $gh.FullName --version *> $null',
  '& $gh auth status *> $null',
  '& $gh repo view $Repositorio *> $null',
  '& $vercel whoami --scope $VercelScope *> $null'
)
foreach ($p in $proibidos) {
  if ($texto.Contains($p)) { throw "Hotfix nativo incompleto: $p" }
}

$utf8Bom = New-Object Text.UTF8Encoding($true)
[IO.File]::WriteAllText($Destino, $texto, $utf8Bom)

$tokens = $null
$erros = $null
[System.Management.Automation.Language.Parser]::ParseFile($Destino,[ref]$tokens,[ref]$erros) | Out-Null
if ($erros.Count -gt 0) {
  $msg = ($erros | ForEach-Object { $_.Message + ' @ ' + $_.Extent.StartLineNumber + ':' + $_.Extent.StartColumnNumber }) -join "`n"
  throw "Bootstrap corrigido nao passou no parser. Nada sera executado.`n$msg"
}

Write-Host 'PASS: HOME corrigido.' -ForegroundColor Green
Write-Host 'PASS: stderr nativo com exit 0 nao sera tratado como falha.' -ForegroundColor Green
Write-Host 'PASS: bootstrap corrigido passou no parser.' -ForegroundColor Green

if ($env:RT_VALIDATE_ONLY -eq '1') {
  Write-Host 'PASS: modo de validacao; nenhuma acao externa do bootstrap foi executada.' -ForegroundColor Green
  exit 0
}

Write-Host 'Iniciando configuracao. Se GitHub/Vercel pedirem login, apenas confirme no navegador.' -ForegroundColor Cyan
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Destino
$codigo = $LASTEXITCODE
if ($codigo -ne 0) {
  throw "A configuracao parou no proximo erro real. Codigo de saida: $codigo"
}
Write-Host 'PASS: configuracao concluida.' -ForegroundColor Green
