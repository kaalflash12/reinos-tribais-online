$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Origem = 'https://raw.githubusercontent.com/kaalflash12/reinos-tribais-online/0a957ab795202a9e7542f44f11d6174a121b8f0d/IMPLANTAR_REINO_TRIBAL_DENO_TURSO.ps1'
$Destino = Join-Path $env:TEMP 'IMPLANTAR_REINO_TRIBAL_DENO_TURSO_FINAL.ps1'

Write-Host '=== REINO TRIBAL - DENO + TURSO + GITHUB PAGES ===' -ForegroundColor Cyan
Write-Host 'Zero Vercel / Zero WSL / Zero infraestrutura de outro jogo.' -ForegroundColor Green

Remove-Item $Destino -Force -ErrorAction SilentlyContinue
Invoke-WebRequest -UseBasicParsing -Uri $Origem -OutFile $Destino -TimeoutSec 120
if (-not (Test-Path $Destino) -or (Get-Item $Destino).Length -le 0) {
  throw 'Falha baixando o bootstrap final do Reino Tribal.'
}

$texto = [IO.File]::ReadAllText($Destino)
$proibidos = @('ver'+'cel','bw-v151','bacathegas','bacaworld','cloudflare','mongodb','neon','supabase.co')
foreach ($p in $proibidos) {
  if ($texto.IndexOf($p,[StringComparison]::OrdinalIgnoreCase) -ge 0) {
    throw "Bootstrap contém infraestrutura proibida: $p. Nada foi executado."
  }
}

$antigo = @'
    Aviso 'Se o Deno pedir autenticação, confirme somente no login oficial. Esta é a única etapa interativa do Deno.'
    Push-Location $workPath
    try {
      & $DenoExe deploy create . --app $DenoApp --source local --runtime-mode dynamic --entrypoint deno/main.js --build-timeout 5 --build-memory-limit 1024 --region global --no-wait
      $createCode = $LASTEXITCODE
    } finally { Pop-Location }
    if ($createCode -ne 0) { Falhar 'Não foi possível criar o app Deno exclusivo do Reino Tribal.' }
'@

$novo = @'
    Aviso 'Se o Deno pedir autenticação, confirme somente no login oficial.'
    Push-Location $workPath
    try {
      & $DenoExe deploy create . --app $DenoApp --source local --runtime-mode dynamic --entrypoint deno/main.js --build-timeout 5 --build-memory-limit 1024 --region global --no-wait
      $createCode = $LASTEXITCODE
      if ($createCode -ne 0) {
        Aviso 'Se sua conta Deno Deploy ainda não tiver uma organização, crie ou selecione uma no console oficial que será aberto.'
        Start-Process 'https://console.deno.com'
        [void](Read-Host 'Depois de criar/selecionar a organização Deno Deploy, pressione ENTER para UMA única nova tentativa')
        & $DenoExe deploy create . --app $DenoApp --source local --runtime-mode dynamic --entrypoint deno/main.js --build-timeout 5 --build-memory-limit 1024 --region global --no-wait
        $createCode = $LASTEXITCODE
      }
    } finally { Pop-Location }
    if ($createCode -ne 0) { Falhar 'Não foi possível criar o app Deno exclusivo do Reino Tribal após a única tentativa de recuperação.' }
'@

$ocorrencias = ([regex]::Matches($texto,[regex]::Escape($antigo))).Count
if ($ocorrencias -ne 1) {
  throw "Contrato inesperado do bootstrap: bloco Deno encontrado $ocorrencias vez(es). Nada foi executado."
}
$texto = $texto.Replace($antigo,$novo)

if (([regex]::Matches($texto,'deploy create \. --app \$DenoApp')).Count -ne 2) {
  throw 'Contrato de tentativa única do Deno não foi preservado.'
}
if ($texto -match '(?is)Deno Deploy: app exclusivo.*?while\s*\(') {
  throw 'Loop de provisionamento Deno detectado. Nada foi executado.'
}
if ($texto -match '\$Pid\b') {
  throw 'Variável PowerShell reservada $PID reapareceu. Nada foi executado.'
}
if (-not $texto.Contains('function Stop-Tree([int]$ProcessId)')) {
  throw 'Hotfix ProcessId ausente. Nada foi executado.'
}
if (-not $texto.Contains('UTF8Encoding($false)') -or -not $texto.Contains('WriteAllLines($envFile')) {
  throw 'Proteção UTF-8 sem BOM ausente. Nada foi executado.'
}

$utf8Bom = New-Object Text.UTF8Encoding($true)
[IO.File]::WriteAllText($Destino,$texto,$utf8Bom)

$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile($Destino,[ref]$tokens,[ref]$errors) | Out-Null
if ($errors.Count -gt 0) {
  $msg = ($errors | ForEach-Object { $_.Message + ' @ ' + $_.Extent.StartLineNumber + ':' + $_.Extent.StartColumnNumber }) -join "`n"
  throw "Bootstrap transformado não passou no parser. Nada foi executado.`n$msg"
}

Write-Host 'PASS: isolamento validado.' -ForegroundColor Green
Write-Host 'PASS: ProcessId validado.' -ForegroundColor Green
Write-Host 'PASS: env UTF-8 sem BOM validado.' -ForegroundColor Green
Write-Host 'PASS: Deno limitado a tentativa inicial + uma recuperação.' -ForegroundColor Green
Write-Host 'PASS: parser PowerShell validado.' -ForegroundColor Green

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Destino
$codigo = $LASTEXITCODE
if ($codigo -ne 0) {
  throw "Implantação parou no erro real. Código de saída: $codigo"
}
