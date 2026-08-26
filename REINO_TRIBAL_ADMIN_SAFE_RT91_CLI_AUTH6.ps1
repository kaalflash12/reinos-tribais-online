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
$ExecutorRevision = 'SAFE-CLI-AUTH-6'
$ExecutorContract = 'ADMIN_AUTHORITY_NO_SOURCE_DEPLOY_RT91'
$ExpectedBackend = 'https://reino-tribal-api.mestrederpg35.deno.net'
$BaseCommit = '133abc213cc3f269e1a5019a7c361847f8f72abe'
$BaseFile = 'REINO_TRIBAL_ADMIN_SAFE_RT91_CLI_AUTH.ps1'
$Repo = 'kaalflash12/reinos-tribais-online'
$Curl = (Get-Command curl.exe -ErrorAction Stop).Source
$Tmp = Join-Path $env:TEMP ('rt91-cli-auth6-' + [Guid]::NewGuid().ToString('N'))
$BasePath = Join-Path $Tmp 'RT91_BASE.ps1'
$PatchedPath = Join-Path $Tmp 'RT91_CLI_AUTH6_PATCHED.ps1'

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
  Write-Host '=== REINO TRIBAL RT91 CLI-AUTH-6 ===' -ForegroundColor Cyan
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

  # 1) CORS exato para GitHub Pages publico.
  $oldCors = "if(`$h -notmatch '(?im)^access-control-allow-origin:\s*\*'){Falhar 'CORS sem Access-Control-Allow-Origin esperado.'}"
  $newCors = "if(`$h -notmatch '(?im)^access-control-allow-origin:\s*https://kaalflash12\.github\.io\s*`$'){Falhar ('CORS allow-origin nao autoriza GitHub Pages.' + [Environment]::NewLine + `$h)}"
  if (-not $text.Contains($oldCors)) { throw 'Trecho CORS legado esperado nao foi encontrado; patch recusado.' }
  $text = $text.Replace($oldCors,$newCors)

  # 2) Auth Deno: argv direto no PowerShell. Nenhum ProcessStartInfo para deno deploy.
  $authPattern = '(?s)function Garantir-DenoAuth \{.*?\r?\n\}\r?\n\r?\nfunction Baixar-E-Validar-MainAtual'
  $newAuth = @'
function Garantir-DenoAuth {
  Etapa 'Autenticacao oficial do Deno Deploy CLI'
  Write-Host 'COMANDO DIRETO: deno deploy env list --org mestrederpg35 --app reino-tribal-api' -ForegroundColor DarkGray
  Write-Host 'Se o Deno precisar autenticar, autorize no navegador oficial. O processo continua no mesmo console.' -ForegroundColor Yellow
  & $DenoExe deploy env list --org $DenoOrg --app $DenoApp
  $denoAuthCode = $LASTEXITCODE
  if ($denoAuthCode -ne 0) { Falhar "Deno deploy env list terminou com codigo $denoAuthCode." }
  Ok 'Login Deno e app confirmados por env list com argv direto.'
}

function Baixar-E-Validar-MainAtual
'@
  if (-not [regex]::IsMatch($text,$authPattern)) { throw 'Funcao Garantir-DenoAuth esperada nao foi encontrada; patch recusado.' }
  $text = [regex]::Replace($text,$authPattern,[System.Text.RegularExpressions.MatchEvaluator]{ param($m) $newAuth },1)

  # 3) A validacao redundante de app deixa de usar ProcessStartInfo; auth acima ja validou org/app.
  $oldApp1 = "`$app=Executar-Nativo -Exe `$DenoExe -Args @('deploy','apps','get','--org',`$DenoOrg,'--app',`$DenoApp,'--json','--non-interactive') -TimeoutSec 60 -Rotulo 'Validar app Deno existente'"
  $oldApp2 = "Exigir-Sucesso `$app 'App Deno reino-tribal-api nao foi encontrado.'"
  $newApp1 = "Write-Host 'PASS: app Deno ja validado no env list direto.' -ForegroundColor Green"
  if (-not $text.Contains($oldApp1) -or -not $text.Contains($oldApp2)) { throw 'Bloco apps get esperado nao foi encontrado; patch recusado.' }
  $text = $text.Replace($oldApp1,$newApp1).Replace($oldApp2,'')

  # 4) update-value: chamadas diretas, argumentos separados nativamente pelo PowerShell.
  $oldPass1 = "`$up1=Executar-Nativo -Exe `$DenoExe -Args @('deploy','env','update-value','RT_ADMIN_PASSWORD',`$adminPassword,'--org',`$DenoOrg,'--app',`$DenoApp,'--non-interactive') -TimeoutSec 90 -Rotulo 'Atualizar RT_ADMIN_PASSWORD'"
  $oldPass2 = "Exigir-Sucesso `$up1 'Deno recusou RT_ADMIN_PASSWORD.'"
  $newPass = @'
  & $DenoExe deploy env update-value RT_ADMIN_PASSWORD $adminPassword --org $DenoOrg --app $DenoApp
  $up1Code = $LASTEXITCODE
  if ($up1Code -ne 0) { Falhar "Deno recusou RT_ADMIN_PASSWORD. exit=$up1Code" }
'@
  $oldRecovery1 = "`$up2=Executar-Nativo -Exe `$DenoExe -Args @('deploy','env','update-value','RT_ADMIN_RECOVERY_KEY',`$recoveryKey,'--org',`$DenoOrg,'--app',`$DenoApp,'--non-interactive') -TimeoutSec 90 -Rotulo 'Atualizar RT_ADMIN_RECOVERY_KEY'"
  $oldRecovery2 = "Exigir-Sucesso `$up2 'Deno recusou RT_ADMIN_RECOVERY_KEY.'"
  $newRecovery = @'
  & $DenoExe deploy env update-value RT_ADMIN_RECOVERY_KEY $recoveryKey --org $DenoOrg --app $DenoApp
  $up2Code = $LASTEXITCODE
  if ($up2Code -ne 0) { Falhar "Deno recusou RT_ADMIN_RECOVERY_KEY. exit=$up2Code" }
'@
  foreach($required in @($oldPass1,$oldPass2,$oldRecovery1,$oldRecovery2)){if(-not $text.Contains($required)){throw 'Bloco update-value esperado nao foi encontrado; patch recusado.'}}
  $text = $text.Replace($oldPass1,$newPass).Replace($oldPass2,'').Replace($oldRecovery1,$newRecovery).Replace($oldRecovery2,'')

  $text = $text.Replace("`$ExecutorRevision = 'SAFE-CLI-AUTH-2'","`$ExecutorRevision = 'SAFE-CLI-AUTH-6'")
  [IO.File]::WriteAllText($PatchedPath,$text,(New-Object Text.UTF8Encoding($false)))

  $tokens=$null;$errors=$null
  [Management.Automation.Language.Parser]::ParseFile($PatchedPath,[ref]$tokens,[ref]$errors)|Out-Null
  if ($errors.Count) { $errors|Format-List|Out-String|Write-Host; throw 'RT91 CLI-AUTH-6 nao passou no parser PowerShell.' }

  $patched = [IO.File]::ReadAllText($PatchedPath)
  foreach ($needle in @(
    "`$ExecutorRevision = 'SAFE-CLI-AUTH-6'",
    "access-control-allow-origin:\s*https://kaalflash12\.github\.io",
    '& $DenoExe deploy env list --org $DenoOrg --app $DenoApp',
    '& $DenoExe deploy env update-value RT_ADMIN_PASSWORD $adminPassword --org $DenoOrg --app $DenoApp',
    '& $DenoExe deploy env update-value RT_ADMIN_RECOVERY_KEY $recoveryKey --org $DenoOrg --app $DenoApp',
    'ANTI_DOWNGRADE: nenhum source deploy executado = PASS',
    'REINO_TRIBAL_ADMIN_RT91_VALIDADO'
  )) { if (-not $patched.Contains($needle)) { throw "Patch RT91 CLI-AUTH-6 incompleto: $needle" } }
  foreach($forbidden in @("'deploy','apps','get'",'--non-interactive','console.deno.com/auth/interactive','console.deno.com/auth/exchange',"'deploy','--org'")){
    if($patched.Contains($forbidden)){throw "RT91 CLI-AUTH-6 ainda contem padrao proibido: $forbidden"}
  }

  Write-Host 'PASS: RT91 CLI-AUTH-6 parseado.' -ForegroundColor Green
  Write-Host 'PASS: DENO_ALL_DEPLOY_DIRECT_ARGV_CONTRACT' -ForegroundColor Green
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
  if($code -ne 0){throw "RT91 CLI-AUTH-6 terminou com codigo $code"}
} finally {
  Remove-Item $Tmp -Recurse -Force -ErrorAction SilentlyContinue
}
