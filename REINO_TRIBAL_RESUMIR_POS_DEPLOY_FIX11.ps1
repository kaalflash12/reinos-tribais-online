param(
  [string]$Repositorio = 'kaalflash12/reinos-tribais-online',
  [string]$DenoApp = 'reino-tribal-api',
  [string]$Branch = 'main',
  [string]$DenoVersion = '2.9.5'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$ToolRoot = Join-Path $env:LOCALAPPDATA 'ReinoTribalTools'
$DenoExe = Join-Path (Join-Path $ToolRoot ("deno-$DenoVersion")) 'deno.exe'
$CredDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'ReinoTribal'
$CredFile = Join-Path $CredDir 'CREDENCIAIS_ADMIN_REINO_TRIBAL.txt'
$WorkRoot = Join-Path $env:TEMP ('reino-tribal-resume-' + [Guid]::NewGuid().ToString('N'))

function Etapa([string]$Texto) { Write-Host "`n=== $Texto ===" -ForegroundColor Cyan }
function Ok([string]$Texto) { Write-Host "PASS: $Texto" -ForegroundColor Green }
function Aviso([string]$Texto) { Write-Host "AVISO: $Texto" -ForegroundColor Yellow }
function Falhar([string]$Texto) { throw $Texto }

function Quote-Arg([string]$Value) {
  if ($null -eq $Value) { return '""' }
  if ($Value -notmatch '[\s"]') { return $Value }
  return '"' + ($Value -replace '(\\*)"','$1$1\"' -replace '(\\+)$','$1$1') + '"'
}

function Stop-Tree([int]$ProcessId) {
  try { & "$env:SystemRoot\System32\taskkill.exe" /PID $ProcessId /T /F *> $null } catch {}
}

function Executar-Nativo {
  param(
    [Parameter(Mandatory=$true)][string]$Exe,
    [string[]]$Args = @(),
    [int]$TimeoutSec = 90,
    [string]$Entrada = '',
    [string]$Diretorio = '',
    [string]$Rotulo = ''
  )
  $label = if ($Rotulo) { $Rotulo } else { Split-Path $Exe -Leaf }
  Write-Host "EXECUTANDO [limite ${TimeoutSec}s]: $label" -ForegroundColor DarkCyan
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $Exe
  $psi.Arguments = (($Args | ForEach-Object { Quote-Arg ([string]$_) }) -join ' ')
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.RedirectStandardInput = $true
  $psi.CreateNoWindow = $true
  if ($Diretorio) { $psi.WorkingDirectory = $Diretorio }
  $p = New-Object System.Diagnostics.Process
  $p.StartInfo = $psi
  if (-not $p.Start()) { Falhar "Nao foi possivel iniciar $label." }
  if ($Entrada) { $p.StandardInput.Write($Entrada) }
  $p.StandardInput.Close()
  $outTask = $p.StandardOutput.ReadToEndAsync()
  $errTask = $p.StandardError.ReadToEndAsync()
  $elapsed = 0
  while (-not $p.WaitForExit(5000)) {
    $elapsed += 5
    Write-Host "... ainda executando: $label (${elapsed}s/${TimeoutSec}s)" -ForegroundColor DarkGray
    if ($elapsed -ge $TimeoutSec) {
      Stop-Tree $p.Id
      return [pscustomobject]@{ Code=124; Stdout=''; Stderr=''; Text="TIMEOUT apos ${TimeoutSec}s: $label"; TimedOut=$true }
    }
  }
  $stdout = $outTask.GetAwaiter().GetResult()
  $stderr = $errTask.GetAwaiter().GetResult()
  return [pscustomobject]@{
    Code=[int]$p.ExitCode
    Stdout=([string]$stdout).Trim()
    Stderr=([string]$stderr).Trim()
    Text=(($stdout + "`n" + $stderr).Trim())
    TimedOut=$false
  }
}

function Exigir-Sucesso($Resultado,[string]$Mensagem) {
  if ($Resultado.Code -ne 0) { Falhar "$Mensagem`n$($Resultado.Text)" }
}

function Novo-Segredo([int]$Bytes = 32) {
  $buf = New-Object byte[] $Bytes
  $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
  try { $rng.GetBytes($buf) } finally { $rng.Dispose() }
  return ([Convert]::ToBase64String($buf).TrimEnd('=').Replace('+','-').Replace('/','_'))
}

function Encontrar-Gh {
  $system = Get-Command gh.exe -ErrorAction SilentlyContinue
  if ($system) { return $system.Source }
  if (Test-Path $ToolRoot) {
    $found = Get-ChildItem $ToolRoot -Filter gh.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { return $found.FullName }
  }
  Falhar 'GitHub CLI nao encontrado.'
}

function Deno-PostJsonRaw {
  param([Parameter(Mandatory=$true)][string]$Url,[Parameter(Mandatory=$true)][hashtable]$Body)
  $json = $Body | ConvertTo-Json -Depth 20 -Compress
  $bytes = [Text.Encoding]::UTF8.GetBytes($json)
  $req = [Net.HttpWebRequest]::Create($Url)
  $req.Method = 'POST'
  $req.ContentType = 'application/json'
  $req.Accept = 'application/json'
  $req.ContentLength = $bytes.Length
  $stream = $req.GetRequestStream()
  try { $stream.Write($bytes,0,$bytes.Length) } finally { $stream.Dispose() }
  $resp = $null
  try { $resp = $req.GetResponse() }
  catch [Net.WebException] {
    $resp = $_.Exception.Response
    if (-not $resp) { throw }
  }
  try {
    $status = [int]$resp.StatusCode
    $reader = New-Object IO.StreamReader($resp.GetResponseStream())
    try { $bodyText = $reader.ReadToEnd() } finally { $reader.Dispose() }
    return [pscustomobject]@{ Ok=($status -ge 200 -and $status -lt 300); Status=$status; Text=[string]$bodyText }
  } finally { if ($resp) { $resp.Close() } }
}

function Garantir-DenoAuth {
  if (-not (Test-Path $DenoExe)) { Falhar "Deno $DenoVersion portatil nao encontrado em $DenoExe. Rode apenas o executor FIX11 completo se o Deno tiver sido removido." }
  $v = Executar-Nativo -Exe $DenoExe -Args @('--version') -TimeoutSec 20 -Rotulo 'Deno portatil existente'
  Exigir-Sucesso $v 'Deno portatil nao executa.'
  if ($v.Text -notmatch "deno $([regex]::Escape($DenoVersion))") { Falhar "Versao Deno inesperada. Esperado: $DenoVersion" }

  $denoToken = [string]$env:DENO_DEPLOY_TOKEN
  if ($denoToken) {
    $existingWho = Executar-Nativo -Exe $DenoExe -Args @('deploy','whoami','--json','--non-interactive') -TimeoutSec 60 -Rotulo 'Validar token Deno existente'
    if ($existingWho.Code -eq 0) { Ok 'Token Deno existente aceito.'; return }
    $env:DENO_DEPLOY_TOKEN = ''
  }

  $verifier = [Guid]::NewGuid().ToString()
  $sha = [Security.Cryptography.SHA256]::Create()
  try { $challenge = [Convert]::ToBase64String($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($verifier))) }
  finally { $sha.Dispose() }

  $beginAuth = Deno-PostJsonRaw -Url 'https://console.deno.com/auth/interactive' -Body @{ challenge=$challenge }
  if (-not $beginAuth.Ok) { Falhar "Deno auth/interactive falhou HTTP $($beginAuth.Status).`n$($beginAuth.Text)" }
  try { $authMeta = $beginAuth.Text | ConvertFrom-Json } catch { Falhar 'Deno auth/interactive retornou JSON invalido.' }
  $deviceCode = [string]$authMeta.code
  $exchangeToken = [string]$authMeta.exchangeToken
  if (-not $deviceCode -or -not $exchangeToken) { Falhar 'Deno auth/interactive nao retornou code/exchangeToken.' }

  Write-Host 'Abrindo o login oficial do Deno Deploy. Apenas confirme o acesso.' -ForegroundColor Yellow
  Start-Process ('https://console.deno.com/auth?code=' + [Uri]::EscapeDataString($deviceCode))

  $deadline = [DateTime]::UtcNow.AddMinutes(5)
  $denoToken = ''
  while ([DateTime]::UtcNow -lt $deadline -and -not $denoToken) {
    Start-Sleep -Seconds 2
    $exchange = Deno-PostJsonRaw -Url 'https://console.deno.com/auth/exchange' -Body @{ exchangeToken=$exchangeToken; verifier=$verifier }
    if ($exchange.Ok) {
      try { $exchangeMeta = $exchange.Text | ConvertFrom-Json } catch { Falhar 'Deno auth/exchange retornou JSON invalido.' }
      $denoToken = [string]$exchangeMeta.token
      break
    }
    $pendingCode = ''
    try { $pendingCode = [string](($exchange.Text | ConvertFrom-Json).code) } catch {}
    if ($pendingCode -ne 'AUTHORIZATION_PENDING') { Falhar "Deno auth/exchange falhou HTTP $($exchange.Status).`n$($exchange.Text)" }
  }
  if (-not $denoToken) { Falhar 'Tempo de confirmacao do Deno expirou.' }
  $env:DENO_DEPLOY_TOKEN = $denoToken
  $who = Executar-Nativo -Exe $DenoExe -Args @('deploy','whoami','--json','--non-interactive') -TimeoutSec 60 -Rotulo 'Validar sessao Deno'
  Exigir-Sucesso $who 'Token Deno nao foi aceito.'
  Ok 'Login Deno confirmado.'
}

function Post-JsonResult([string]$Uri,[hashtable]$Body,[string]$Bearer='') {
  $headers = @{}
  if ($Bearer) { $headers.Authorization = "Bearer $Bearer" }
  try {
    $data = Invoke-RestMethod -Uri $Uri -Method Post -Headers $headers -ContentType 'application/json' -Body ($Body | ConvertTo-Json -Depth 50 -Compress) -TimeoutSec 60
    return [pscustomobject]@{ Ok=$true; Status=200; Data=$data; Error='' }
  } catch {
    $status = 0
    $detail = $_.Exception.Message
    try {
      if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }
      if ($_.Exception.Response -and $_.Exception.Response.GetResponseStream()) {
        $reader = New-Object IO.StreamReader($_.Exception.Response.GetResponseStream())
        $bodyText = $reader.ReadToEnd()
        if ($bodyText) { $detail = $bodyText }
      }
    } catch {}
    return [pscustomobject]@{ Ok=$false; Status=$status; Data=$null; Error=$detail }
  }
}

function Set-GitHubSecret([string]$Gh,[string]$Nome,[string]$Valor) {
  $r = Executar-Nativo -Exe $Gh -Args @('secret','set',$Nome,'-R',$Repositorio) -Entrada $Valor -TimeoutSec 60 -Rotulo "GitHub secret $Nome"
  Exigir-Sucesso $r "Falha gravando GitHub Secret $Nome."
}

function Set-GitHubVariable([string]$Gh,[string]$Nome,[string]$Valor) {
  $r = Executar-Nativo -Exe $Gh -Args @('variable','set',$Nome,'-R',$Repositorio,'--body',$Valor) -TimeoutSec 60 -Rotulo "GitHub variable $Nome"
  Exigir-Sucesso $r "Falha gravando GitHub Variable $Nome."
}

function Obter-BackendMinimo([string]$Gh,[string]$Destino) {
  $tokenResult = Executar-Nativo -Exe $Gh -Args @('auth','token') -TimeoutSec 30 -Rotulo 'Credencial temporaria GitHub'
  Exigir-Sucesso $tokenResult 'Nao foi possivel obter credencial da sessao GitHub.'
  $token = $tokenResult.Stdout.Trim()
  if ($token.Length -lt 20) { Falhar 'Credencial GitHub invalida.' }
  $headers = @{
    Authorization = "Bearer $token"
    Accept = 'application/vnd.github+json'
    'User-Agent' = 'Reino-Tribal-Resume-FIX11'
    'X-GitHub-Api-Version' = '2022-11-28'
  }
  foreach ($relative in @('deno.json','package.json','deno/main.js','api/reino.js','api/admin.js','backend/turso/schema.sql')) {
    $escaped = (($relative -split '/') | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/'
    $escapedBranch = [Uri]::EscapeDataString($Branch)
    $uri = "https://api.github.com/repos/$Repositorio/contents/$escaped?ref=$escapedBranch"
    $meta = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers -TimeoutSec 60
    if ([string]$meta.type -ne 'file' -or -not $meta.content) { Falhar "Conteudo GitHub ausente: $relative" }
    $bytes = [Convert]::FromBase64String((([string]$meta.content) -replace '\s',''))
    $dest = Join-Path $Destino ($relative -replace '/','\')
    New-Item -ItemType Directory -Force -Path (Split-Path $dest -Parent) | Out-Null
    [IO.File]::WriteAllBytes($dest,$bytes)
  }

  $denoConfigPath = Join-Path $Destino 'deno.json'
  $denoConfig = Get-Content -Raw -Path $denoConfigPath | ConvertFrom-Json
  if ($denoConfig.PSObject.Properties['deploy']) {
    $denoConfig.PSObject.Properties.Remove('deploy')
    [IO.File]::WriteAllText($denoConfigPath,($denoConfig | ConvertTo-Json -Depth 50),(New-Object Text.UTF8Encoding($false)))
  }
  $check = Executar-Nativo -Exe $DenoExe -Args @('check','deno/main.js') -Diretorio $Destino -TimeoutSec 180 -Rotulo 'Deno check backend atual'
  Exigir-Sucesso $check 'Backend atual nao passou no deno check.'
  Ok 'Backend atual de seis arquivos obtido de main e validado.'
}

$gh = $null
try {
  Etapa 'Retomada FIX11 - somente credencial ADM'
  $gh = Encontrar-Gh
  $ghStatus = Executar-Nativo -Exe $gh -Args @('auth','status') -TimeoutSec 30 -Rotulo 'GitHub auth status'
  Exigir-Sucesso $ghStatus 'GitHub CLI nao esta autenticado.'
  Garantir-DenoAuth

  $denoOrg = ''
  $orgSaved = Executar-Nativo -Exe $gh -Args @('variable','get','DENO_DEPLOY_ORG','-R',$Repositorio) -TimeoutSec 30 -Rotulo 'Ler DENO_DEPLOY_ORG'
  if ($orgSaved.Code -eq 0 -and $orgSaved.Stdout) { $denoOrg = $orgSaved.Stdout.Trim() }
  if ($denoOrg) {
    $probe = Executar-Nativo -Exe $DenoExe -Args @('deploy','apps','get','--org',$denoOrg,'--app',$DenoApp,'--json','--non-interactive') -TimeoutSec 60 -Rotulo 'Validar app Deno existente'
    if ($probe.Code -ne 0) { $denoOrg = '' }
  }
  if (-not $denoOrg) {
    $orgList = Executar-Nativo -Exe $DenoExe -Args @('deploy','orgs','list','--json','--non-interactive') -TimeoutSec 120 -Rotulo 'Listar organizacoes Deno'
    Exigir-Sucesso $orgList 'Nao foi possivel listar organizacoes Deno.'
    try { $orgs = @($orgList.Stdout | ConvertFrom-Json) } catch { Falhar 'JSON de organizacoes Deno invalido.' }
    foreach ($o in $orgs) {
      $slug = [string]$o.slug
      if (-not $slug) { continue }
      $probe = Executar-Nativo -Exe $DenoExe -Args @('deploy','apps','get','--org',$slug,'--app',$DenoApp,'--json','--non-interactive') -TimeoutSec 45 -Rotulo "Procurar $DenoApp em $slug"
      if ($probe.Code -eq 0) { $denoOrg = $slug; break }
    }
  }
  if (-not $denoOrg) { Falhar 'App Deno reino-tribal-api nao foi encontrado nas organizacoes acessiveis.' }
  Ok "Organizacao Deno: $denoOrg"

  $appInfo = Executar-Nativo -Exe $DenoExe -Args @('deploy','apps','get','--org',$denoOrg,'--app',$DenoApp,'--json','--non-interactive') -TimeoutSec 60 -Rotulo 'Obter backend Deno'
  Exigir-Sucesso $appInfo 'Nao foi possivel ler o app Deno.'
  try { $appMeta = $appInfo.Stdout | ConvertFrom-Json } catch { Falhar 'apps get retornou JSON invalido.' }
  $backend = ([string]$appMeta.productionUrl).TrimEnd('/')
  if ($backend -notmatch '^https://') { Falhar 'Deno nao retornou productionUrl valida.' }
  Ok "Backend existente: $backend"

  $adminPassword = 'RT!' + (Novo-Segredo 30)
  $recoveryKey = Novo-Segredo 48

  Etapa 'Atualizando somente os dois secrets ADM no Deno'
  $up1 = Executar-Nativo -Exe $DenoExe -Args @('deploy','env','update-value','RT_ADMIN_PASSWORD',$adminPassword,'--org',$denoOrg,'--app',$DenoApp,'--non-interactive') -TimeoutSec 90 -Rotulo 'Atualizar RT_ADMIN_PASSWORD'
  Exigir-Sucesso $up1 'Deno recusou update-value de RT_ADMIN_PASSWORD.'
  $up2 = Executar-Nativo -Exe $DenoExe -Args @('deploy','env','update-value','RT_ADMIN_RECOVERY_KEY',$recoveryKey,'--org',$denoOrg,'--app',$DenoApp,'--non-interactive') -TimeoutSec 90 -Rotulo 'Atualizar RT_ADMIN_RECOVERY_KEY'
  Exigir-Sucesso $up2 'Deno recusou update-value de RT_ADMIN_RECOVERY_KEY.'
  Ok 'Secrets ADM atualizados sem tocar no Turso.'

  $recover = $null
  for ($i=1; $i -le 8; $i++) {
    Start-Sleep -Seconds 2
    $recover = Post-JsonResult "$backend/api/reino" @{ action='admin_recover'; recovery_key=$recoveryKey; password=$adminPassword }
    if ($recover.Ok -and $recover.Data.ok) { break }
  }

  if (-not $recover -or -not $recover.Ok -or -not $recover.Data.ok) {
    Aviso 'A producao ainda nao enxergou a nova recovery key. Fazendo apenas um redeploy do backend atual; Turso nao sera reautenticado.'
    New-Item -ItemType Directory -Force -Path $WorkRoot | Out-Null
    Obter-BackendMinimo $gh $WorkRoot
    $deploy = Executar-Nativo -Exe $DenoExe -Args @('deploy','--org',$denoOrg,'--app',$DenoApp,'--prod','--non-interactive') -Diretorio $WorkRoot -TimeoutSec 600 -Rotulo 'Redeploy backend atual'
    Exigir-Sucesso $deploy 'Redeploy Deno falhou.'
    $recover = $null
    for ($i=1; $i -le 20; $i++) {
      Start-Sleep -Seconds 3
      $recover = Post-JsonResult "$backend/api/reino" @{ action='admin_recover'; recovery_key=$recoveryKey; password=$adminPassword }
      if ($recover.Ok -and $recover.Data.ok) { break }
    }
  }
  if (-not $recover -or -not $recover.Ok -or -not $recover.Data.ok) {
    $detail = if ($recover) { "$($recover.Status) $($recover.Error)" } else { 'sem resposta' }
    Falhar "admin_recover nao aceitou a recovery key nova apos atualizacao/redeploy: $detail"
  }
  Ok 'Hash persistido de reinos_admin sincronizado com a senha nova.'

  $login = Post-JsonResult "$backend/api/reino" @{ action='login'; identifier='reinos_admin'; password=$adminPassword }
  if (-not $login.Ok -or -not $login.Data.access_token -or $login.Data.user.role -ne 'admin') { Falhar "Login ADM falhou apos sincronizacao: $($login.Error)" }
  $adminToken = [string]$login.Data.access_token
  $status = Post-JsonResult "$backend/api/reino" @{ action='admin_status' } $adminToken
  if (-not $status.Ok -or -not $status.Data.ok) { Falhar 'admin_status falhou apos login ADM.' }
  $dash = Post-JsonResult "$backend/api/admin" @{ action='dashboard' } $adminToken
  if (-not $dash.Ok -or -not $dash.Data) { Falhar 'Dashboard ADM falhou apos login ADM.' }
  Ok 'Login ADM + admin_status + dashboard passaram.'

  Etapa 'Persistindo apenas a credencial ADM corrigida'
  Set-GitHubSecret $gh 'RT_ADMIN_PASSWORD' $adminPassword
  Set-GitHubSecret $gh 'RT_ADMIN_RECOVERY_KEY' $recoveryKey
  Set-GitHubVariable $gh 'REINO_TRIBAL_API_BASE' $backend
  New-Item -ItemType Directory -Force -Path $CredDir | Out-Null
  $cred = @(
    'REINO TRIBAL - CREDENCIAIS ADMINISTRATIVAS',
    ('Gerado em: ' + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')),
    ('Backend: ' + $backend),
    'Usuario ADM: reinos_admin',
    ('Senha ADM: ' + $adminPassword),
    ('Recovery Key: ' + $recoveryKey)
  ) -join [Environment]::NewLine
  [IO.File]::WriteAllText($CredFile,$cred,(New-Object Text.UTF8Encoding($true)))
  Ok "Credenciais gravadas em: $CredFile"
  Write-Host "`nREINO_TRIBAL_RESUME_FIX11_COMPLETO" -ForegroundColor Green
  Write-Host "Backend: $backend" -ForegroundColor Green
  Write-Host 'Frontend: https://kaalflash12.github.io/reinos-tribais-online/' -ForegroundColor Green
} finally {
  $env:DENO_DEPLOY_TOKEN = ''
  Remove-Item $WorkRoot -Recurse -Force -ErrorAction SilentlyContinue
}
