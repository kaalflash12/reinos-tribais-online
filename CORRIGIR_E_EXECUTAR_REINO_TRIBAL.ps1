$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Origem = 'https://raw.githubusercontent.com/kaalflash12/reinos-tribais-online/rt-turso-migration/CONFIGURAR_TURSO_REINO_TRIBAL_AUTO.ps1'
$Destino = Join-Path $env:TEMP 'REINO_TRIBAL_AUTO_CORRIGIDO.ps1'

Write-Host '=== REINO TRIBAL - HOTFIX DE EXECUCAO ===' -ForegroundColor Cyan
Write-Host 'Baixando o script de producao...' -ForegroundColor Cyan
Remove-Item $Destino -Force -ErrorAction SilentlyContinue
Invoke-WebRequest -UseBasicParsing -Uri $Origem -OutFile $Destino -TimeoutSec 120
if (-not (Test-Path $Destino) -or (Get-Item $Destino).Length -le 0) {
  throw 'Falha ao baixar o script de producao.'
}

$texto = [IO.File]::ReadAllText($Destino)

# Windows PowerShell trata $HOME como variavel automatica somente leitura.
# O bootstrap antigo usava $home como variavel local; PowerShell nao diferencia maiusculas/minusculas.
$rxHome = [regex]::new('\$home\b')
$quantidade = $rxHome.Matches($texto).Count
if ($quantidade -gt 0) {
  Write-Host "Aplicando correcao da variavel HOME ($quantidade ocorrencias)..." -ForegroundColor Yellow
  $texto = $rxHome.Replace($texto, '$vercelCliHome')
}

if ($rxHome.IsMatch($texto)) {
  throw 'A correcao de HOME nao foi aplicada completamente. Nada sera executado.'
}

# Grava UTF-8 com BOM para Windows PowerShell 5.1 nao corromper acentos.
$utf8Bom = New-Object Text.UTF8Encoding($true)
[IO.File]::WriteAllText($Destino, $texto, $utf8Bom)

$tokens = $null
$erros = $null
[System.Management.Automation.Language.Parser]::ParseFile(
  $Destino,
  [ref]$tokens,
  [ref]$erros
) | Out-Null
if ($erros.Count -gt 0) {
  $msg = ($erros | ForEach-Object { $_.Message + ' @ ' + $_.Extent.StartLineNumber + ':' + $_.Extent.StartColumnNumber }) -join "`n"
  throw "O script corrigido nao passou no parser. Nada sera executado.`n$msg"
}

Write-Host 'PASS: script corrigido e validado antes da execucao.' -ForegroundColor Green
Write-Host 'Iniciando configuracao. Se GitHub/Vercel pedirem login, apenas confirme no navegador.' -ForegroundColor Cyan

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Destino
$codigo = $LASTEXITCODE
if ($codigo -ne 0) {
  throw "A configuracao parou no erro real. Codigo de saida: $codigo"
}

Write-Host 'PASS: configuracao concluida.' -ForegroundColor Green
