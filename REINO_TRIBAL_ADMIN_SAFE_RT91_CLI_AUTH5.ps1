param(
  [string]$Repositorio = 'kaalflash12/reinos-tribais-online',
  [string]$DenoOrg = 'mestrederpg35',
  [string]$DenoApp = 'reino-tribal-api',
  [string]$DenoVersion = '2.9.5',
  [string]$DenoExeOverride = '',
  [switch]$ValidateOnly,
  [switch]$PreflightOnly,
  [switch]$IdentityOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$ExecutorVersion = 'RT91'
$ExecutorRevision = 'SAFE-CLI-AUTH-5'
$ExecutorContract = 'ADMIN_AUTHORITY_NO_SOURCE_DEPLOY_RT91'
$ExpectedBackend = 'https://reino-tribal-api.mestrederpg35.deno.net'
$BaseCommit = '133abc213cc3f269e1a5019a7c361847f8f72abe'
$BaseFile = 'REINO_TRIBAL_ADMIN_SAFE_RT91_CLI_AUTH.ps1'
$Repo = 'kaalflash12/reinos-tribais-online'
$Curl = (Get-Command curl.exe -ErrorAction Stop).Source
$Tmp = Join-Path $env:TEMP ('rt91-cli-auth5-' + [Guid]::NewGuid().ToString('N'))
$BasePath = Join-Path $Tmp 'RT91_BASE.ps1'
$PatchedPath = Join-Path $Tmp 'RT91_CLI_AUTH5_PATCHED.ps1'

$RequiredBaseMarkers = @(
  "`$ExecutorVersion = 'RT91'",
  "`$ExecutorRevision = 'SAFE-CLI-AUTH-2'",
  "`$ExecutorContract = 'ADMIN_AUTHORITY_NO_SOURCE_DEPLOY_RT91'",
  "`$ExpectedBackend = 'https://reino-tribal-api.mestrederpg35.deno.net'",
  "'deploy','env','update-value'",
  'ANTI_DOWNGRADE: nenhum source deploy executado = PASS',
  'REINO_TRIBAL_ADMIN_RT91_VALIDADO'
)

try {
  New-Item -ItemType Directory -Force -Path $Tmp | Out-Null
  Write-Host ''
  Write-Host '=== REINO TRIBAL RT91 CLI-AUTH-5 ===' -ForegroundColor Cyan
  Write-Host ('BASE PINADA: ' + $BaseCommit) -ForegroundColor DarkGray

  $url = "https://raw.githubusercontent.com/$Repo/$BaseCommit/$BaseFile"
  & $Curl --fail --silent --show-error --location --http1.1 --tlsv1.2 --retry 5 --retry-all-errors --connect-timeout 20 --max-time 120 --output $BasePath $url
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path $BasePath) -or (Get-Item $BasePath).Length -lt 5000) {
    throw 'Falha baixando executor-base RT91 CLI-AUTH-2 pinado.'
  }

  $text = [IO.File]::ReadAllText($BasePath)
  foreach ($needle in $RequiredBaseMarkers) {
    if (-not $text.Contains($needle)) { throw "Executor-base nao cumpre contrato: $needle" }
  }
  if ($text.Contains("'deploy','--org'")) { throw 'ANTI-DOWNGRADE: source deploy detectado no executor-base.' }
  if ($text.Contains('console.deno.com/auth/interactive') -or $text.Contains('console.deno.com/auth/exchange')) {
    throw 'Auth HTTP manual proibido detectado no executor-base.'
  }

  # 1) CORS: aceitar apenas a origem publica real do GitHub Pages.
  $oldCors = "if(`$h -notmatch '(?im)^access-control-allow-origin:\s*\*'){Falhar 'CORS sem Access-Control-Allow-Origin esperado.'}"
  $newCors = "if(`$h -notmatch '(?im)^access-control-allow-origin:\s*https://kaalflash12\.github\.io\s*`$'){Falhar ('CORS allow-origin nao autoriza GitHub Pages.' + [Environment]::NewLine + `$h)}"
  if (-not $text.Contains($oldCors)) { throw 'Trecho CORS legado esperado nao foi encontrado; patch recusado.' }
  $text = $text.Replace($oldCors,$newCors)

  # 2) Autenticacao: chamada DIRETA ao deno.exe, sem ProcessStartInfo.Arguments.
  #    Isso impede o bug observado em Windows PowerShell onde o Deno recebeu zero argumentos e abriu o REPL.
  $authPattern = '(?s)function Garantir-DenoAuth \{.*?\r?\n\}\r?\n\r?\nfunction Baixar-E-Validar-MainAtual'
  $newAuth = @'
function Garantir-DenoAuth {
  Etapa 'Autenticacao oficial do Deno Deploy CLI'
  Write-Host 'O Deno CLI validara o app por env list. Se precisar autenticar, ele abrira o navegador oficial automaticamente.' -ForegroundColor Yellow
  Write-Host 'COMANDO: deno deploy env list --org mestrederpg35 --app reino-tribal-api' -ForegroundColor DarkGray
  & $DenoExe deploy env list --org $DenoOrg --app $DenoApp
  $denoAuthCode = $LASTEXITCODE
  if ($denoAuthCode -ne 0) { Falhar "Deno deploy env list terminou com codigo $denoAuthCode." }
  Ok 'Login Deno confirmado pelo comando documentado env list e keyring oficial.'
}

function Baixar-E-Validar-MainAtual
'@
  if (-not [regex]::IsMatch($text,$authPattern)) { throw 'Funcao Garantir-DenoAuth esperada nao foi encontrada; patch recusado.' }
  $text = [regex]::Replace($text,$authPattern,[System.Text.RegularExpressions.MatchEvaluator]{ param($m) $newAuth },1)

  # 3) Validacao read-only do app: substituir subcomando apps/get nao documentado por env/list.
  $oldApp = "`$app=Executar-Nativo -Exe `$DenoExe -Args @('deploy','apps','get','--org',`$DenoOrg,'--app',`$DenoApp,'--json','--non-interactive') -TimeoutSec 60 -Rotulo 'Validar app Deno existente'"
  $newApp = "`$app=Executar-Nativo -Exe `$DenoExe -Args @('deploy','env','list','--org',`$DenoOrg,'--app',`$DenoApp) -TimeoutSec 60 -Rotulo 'Validar app Deno por env list'"
  if (-not $text.Contains($oldApp)) { throw 'Trecho apps get esperado nao foi encontrado; patch recusado.' }
  $text = $text.Replace($oldApp,$newApp)

  # 4) update-value: remover flag nao documentada --non-interactive; autenticacao ja esta no keyring.
  $oldPass = "@('deploy','env','update-value','RT_ADMIN_PASSWORD',`$adminPassword,'--org',`$DenoOrg,'--app',`$DenoApp,'--non-interactive')"
  $newPass = "@('deploy','env','update-value','RT_ADMIN_PASSWORD',`$adminPassword,'--org',`$DenoOrg,'--app',`$DenoApp)"
  $oldRecovery = "@('deploy','env','update-value','RT_ADMIN_RECOVERY_KEY',`$recoveryKey,'--org',`$DenoOrg,'--app',`$DenoApp,'--non-interactive')"
  $newRecovery = "@('deploy','env','update-value','RT_ADMIN_RECOVERY_KEY',`$recoveryKey,'--org',`$DenoOrg,'--app',`$DenoApp)"
  if (-not $text.Contains($oldPass) -or -not $text.Contains($oldRecovery)) { throw 'Trecho update-value esperado nao foi encontrado; patch recusado.' }
  $text = $text.Replace($oldPass,$newPass).Replace($oldRecovery,$newRecovery)

  $text = $text.Replace("`$ExecutorRevision = 'SAFE-CLI-AUTH-2'","`$ExecutorRevision = 'SAFE-CLI-AUTH-5'")
  [IO.File]::WriteAllText($PatchedPath,$text,(New-Object Text.UTF8Encoding($false)))

  $tokens=$null;$errors=$null
  [Management.Automation.Language.Parser]::ParseFile($PatchedPath,[ref]$tokens,[ref]$errors)|Out-Null
  if ($errors.Count) { $errors|Format-List|Out-String|Write-Host; throw 'RT91 CLI-AUTH-5 nao passou no parser PowerShell.' }

  $patched = [IO.File]::ReadAllText($PatchedPath)
  foreach ($needle in @(
    "`$ExecutorRevision = 'SAFE-CLI-AUTH-5'",
    "access-control-allow-origin:\s*https://kaalflash12\.github\.io",
    '& $DenoExe deploy env list --org $DenoOrg --app $DenoApp',
    "@('deploy','env','update-value','RT_ADMIN_PASSWORD',`$adminPassword,'--org',`$DenoOrg,'--app',`$DenoApp)",
    "@('deploy','env','update-value','RT_ADMIN_RECOVERY_KEY',`$recoveryKey,'--org',`$DenoOrg,'--app',`$DenoApp)",
    'ANTI_DOWNGRADE: nenhum source deploy executado = PASS',
    'REINO_TRIBAL_ADMIN_RT91_VALIDADO'
  )) { if (-not $patched.Contains($needle)) { throw "Patch RT91 CLI-AUTH-5 incompleto: $needle" } }
  if ($patched.Contains("'deploy','apps','get'")) { throw 'Subcomando Deno apps get nao documentado ainda presente.' }
  if ($patched.Contains('--non-interactive')) { throw 'Flag Deno --non-interactive nao documentada ainda presente.' }
  if ($patched.Contains('console.deno.com/auth/interactive') -or $patched.Contains('console.deno.com/auth/exchange')) { throw 'Auth HTTP manual reapareceu.' }
  if ($patched.Contains("'deploy','--org'")) { throw 'ANTI-DOWNGRADE: source deploy apareceu apos patch.' }

  Write-Host 'PASS: RT91 CLI-AUTH-5 parseado.' -ForegroundColor Green
  Write-Host 'PASS: DENO_DIRECT_ARGUMENT_FORWARDING_CONTRACT' -ForegroundColor Green
  Write-Host 'PASS: CORS_GITHUB_PAGES_EXACT_ORIGIN_CONTRACT' -ForegroundColor Green
  Write-Host 'PASS: DENO_ENV_LIST_AUTH_CONTRACT' -ForegroundColor Green
  Write-Host 'PASS: DENO_DOCUMENTED_CLI_ONLY_CONTRACT' -ForegroundColor Green
  Write-Host 'PASS: ANTI_DOWNGRADE_NO_SOURCE_DEPLOY_CONTRACT' -ForegroundColor Green

  $childArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$PatchedPath)
  if ($IdentityOnly) { $childArgs += '-IdentityOnly' }
  if ($PreflightOnly) { $childArgs += '-PreflightOnly' }
  if ($ValidateOnly) { $childArgs += '-ValidateOnly' }
  if ($DenoExeOverride) { $childArgs += @('-DenoExeOverride',$DenoExeOverride) }
  & powershell.exe @childArgs
  $code=$LASTEXITCODE
  if($code -ne 0){throw "RT91 CLI-AUTH-5 terminou com codigo $code"}
} finally {
  Remove-Item $Tmp -Recurse -Force -ErrorAction SilentlyContinue
}
