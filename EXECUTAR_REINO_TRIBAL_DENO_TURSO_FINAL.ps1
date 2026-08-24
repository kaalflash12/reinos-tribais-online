param([switch]$ValidateOnly)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Origem = 'https://raw.githubusercontent.com/kaalflash12/reinos-tribais-online/0a957ab795202a9e7542f44f11d6174a121b8f0d/IMPLANTAR_REINO_TRIBAL_DENO_TURSO.ps1'
$Destino = Join-Path $env:TEMP 'IMPLANTAR_REINO_TRIBAL_DENO_TURSO_FINAL.ps1'

Write-Host '=== REINO TRIBAL - DENO + TURSO + GITHUB PAGES ===' -ForegroundColor Cyan
Write-Host 'ZERO VERCEL / ZERO WSL / ZERO INFRAESTRUTURA DE OUTRO JOGO.' -ForegroundColor Green

Remove-Item $Destino -Force -ErrorAction SilentlyContinue
Invoke-WebRequest -UseBasicParsing -Uri $Origem -OutFile $Destino -TimeoutSec 120
if (-not (Test-Path $Destino) -or (Get-Item $Destino).Length -le 0) {
  throw 'Falha baixando o bootstrap final do Reino Tribal.'
}

$texto = [IO.File]::ReadAllText($Destino).Replace("`r`n","`n")
$proibidos = @('ver'+'cel','bw-v151','bacathegas','bacaworld','cloudflare','mongodb','neon','supabase.co')
foreach ($p in $proibidos) {
  if ($texto.IndexOf($p,[StringComparison]::OrdinalIgnoreCase) -ge 0) {
    throw "Bootstrap contem infraestrutura proibida: $p. Nada foi executado."
  }
}

# Todos os marcadores abaixo sao ASCII para funcionar igual no Windows PowerShell 5.1,
# independentemente de BOM/encoding do proprio launcher.
$secaoMarcador = "Etapa 'Deno Deploy: app exclusivo do Reino Tribal'"
$envMarcador = '  $envFile = Join-Path $WorkRoot ''.env.reino-tribal.production'''
$codigoMarcador = '      $createCode = $LASTEXITCODE'

$secaoInicio = $texto.IndexOf($secaoMarcador,[StringComparison]::Ordinal)
if ($secaoInicio -lt 0) { throw 'Secao Deno nao encontrada. Nada foi executado.' }
$envInicio = $texto.IndexOf($envMarcador,$secaoInicio)
if ($envInicio -lt 0) { throw 'Fim da secao Deno nao encontrado. Nada foi executado.' }
$secaoOriginal = $texto.Substring($secaoInicio,$envInicio-$secaoInicio)
if (([regex]::Matches($secaoOriginal,'deploy create \. --app \$DenoApp')).Count -ne 1) {
  throw 'Secao Deno original nao contem exatamente uma criacao. Nada foi executado.'
}

$codigoInicio = $texto.IndexOf($codigoMarcador,$secaoInicio)
if ($codigoInicio -lt 0 -or $codigoInicio -ge $envInicio) {
  throw 'Ponto de insercao Deno nao encontrado. Nada foi executado.'
}
$linhaFim = $texto.IndexOf("`n",$codigoInicio)
if ($linhaFim -lt 0 -or $linhaFim -ge $envInicio) {
  throw 'Fim da linha de status Deno nao encontrado. Nada foi executado.'
}
$posInsercao = $linhaFim + 1

$recuperacao = @'
      if ($createCode -ne 0) {
        Aviso 'Se a conta Deno ainda nao tiver organizacao, crie ou selecione uma no console oficial que sera aberto.'
        Start-Process 'https://console.deno.com'
        [void](Read-Host 'Depois de criar/selecionar a organizacao Deno, pressione ENTER para UMA unica nova tentativa')
        & $DenoExe deploy create . --app $DenoApp --source local --runtime-mode dynamic --entrypoint deno/main.js --build-timeout 5 --build-memory-limit 1024 --region global --no-wait
        $createCode = $LASTEXITCODE
      }
'@
$recuperacao = $recuperacao.Replace("`r`n","`n") + "`n"
$texto = $texto.Substring(0,$posInsercao) + $recuperacao + $texto.Substring($posInsercao)

$envInicioDepois = $texto.IndexOf($envMarcador,$secaoInicio)
$secaoFinal = $texto.Substring($secaoInicio,$envInicioDepois-$secaoInicio)
if (([regex]::Matches($secaoFinal,'deploy create \. --app \$DenoApp')).Count -ne 2) {
  throw 'Contrato Deno final nao possui exatamente tentativa inicial + uma recuperacao.'
}
if ($secaoFinal -match '\bwhile\s*\(') {
  throw 'Loop de provisionamento Deno detectado. Nada foi executado.'
}
if (-not $secaoFinal.Contains("Start-Process 'https://console.deno.com'")) {
  throw 'Recuperacao da organizacao Deno nao foi inserida.'
}
if ($texto -match '\$Pid\b') {
  throw 'Variavel PowerShell reservada PID reapareceu. Nada foi executado.'
}
if (-not $texto.Contains('function Stop-Tree([int]$ProcessId)')) {
  throw 'Hotfix ProcessId ausente. Nada foi executado.'
}
if (-not $texto.Contains('UTF8Encoding($false)') -or -not $texto.Contains('WriteAllLines($envFile')) {
  throw 'Protecao UTF-8 sem BOM ausente. Nada foi executado.'
}

$utf8Bom = New-Object Text.UTF8Encoding($true)
[IO.File]::WriteAllText($Destino,$texto,$utf8Bom)

$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile($Destino,[ref]$tokens,[ref]$errors) | Out-Null
if ($errors.Count -gt 0) {
  $msg = ($errors | ForEach-Object { $_.Message + ' @ ' + $_.Extent.StartLineNumber + ':' + $_.Extent.StartColumnNumber }) -join "`n"
  throw "Bootstrap transformado nao passou no parser. Nada foi executado.`n$msg"
}

Write-Host 'PASS: ISOLAMENTO VALIDADO.' -ForegroundColor Green
Write-Host 'PASS: PROCESSID VALIDADO.' -ForegroundColor Green
Write-Host 'PASS: ENV UTF-8 SEM BOM VALIDADO.' -ForegroundColor Green
Write-Host 'PASS: DENO = TENTATIVA INICIAL + UMA RECUPERACAO.' -ForegroundColor Green
Write-Host 'PASS: PARSER POWERSHELL VALIDADO.' -ForegroundColor Green

if ($ValidateOnly) {
  Write-Host 'FINAL_LAUNCHER_TRANSFORM_PASS' -ForegroundColor Green
  return
}

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Destino
$codigo = $LASTEXITCODE
if ($codigo -ne 0) {
  throw "Implantacao parou no erro real. Codigo de saida: $codigo"
}
