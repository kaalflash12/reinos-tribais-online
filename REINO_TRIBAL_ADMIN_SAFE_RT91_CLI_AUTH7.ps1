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
$ExecutorRevision = 'SAFE-CLI-AUTH-7'
$ExecutorContract = 'ADMIN_AUTHORITY_NO_SOURCE_DEPLOY_RT91'
$ExpectedBackend = 'https://reino-tribal-api.mestrederpg35.deno.net'
$BaseCommit = '133abc213cc3f269e1a5019a7c361847f8f72abe'
$BaseFile = 'REINO_TRIBAL_ADMIN_SAFE_RT91_CLI_AUTH.ps1'
$Repo = 'kaalflash12/reinos-tribais-online'
$Curl = (Get-Command curl.exe -ErrorAction Stop).Source
$Tmp = Join-Path $env:TEMP ('rt91-cli-auth7-' + [Guid]::NewGuid().ToString('N'))
$BasePath = Join-Path $Tmp 'RT91_BASE.ps1'
$PatchedPath = Join-Path $Tmp 'RT91_CLI_AUTH7_PATCHED.ps1'

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
  Write-Host '=== REINO TRIBAL RT91 CLI-AUTH-7 ===' -ForegroundColor Cyan
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

  $oldCors = "if(`$h -notmatch '(?im)^access-control-allow-origin:\s*\*'){Falhar 'CORS sem Access-Control-Allow-Origin esperado.'}"
  $newCors = "if(`$h -notmatch '(?im)^access-control-allow-origin:\s*https://kaalflash12\.github\.io\s*`$'){Falhar ('CORS allow-origin nao autoriza GitHub Pages.' + [Environment]::NewLine + `$h)}"
  if (-not $text.Contains($oldCors)) { throw 'Trecho CORS legado esperado nao foi encontrado; patch recusado.' }
  $text = $text.Replace($oldCors,$newCors)

  $interactivePattern = '(?s)function Executar-Deno-Interativo \{.*?\r?\n\}\r?\n\r?\nfunction Exigir-Sucesso'
  if ([regex]::IsMatch($text,$interactivePattern)) {
    $text = [regex]::Replace($text,$interactivePattern,'function Exigir-Sucesso',1)
  }

  $authPattern = '(?s)function Garantir-DenoAuth \{.*?\r?\n\}\r?\n\r?\nfunction Baixar-E-Validar-MainAtual'
  $newAuth = @'
function Invoke-DenoJsonDirect {
  param(
    [Parameter(Mandatory=$true)][string[]]$CommandArgs,
    [string]$Rotulo = 'Deno Deploy JSON',
    [switch]$QuietErrors
  )
  Write-Host ('DENO DIRETO: deno ' + ($CommandArgs -join ' ') + ' --json') -ForegroundColor DarkGray
  $errFile = Join-Path $env:TEMP ('rt91-deno-'+[Guid]::NewGuid().ToString('N')+'.err')
  try {
    if($QuietErrors){
      $raw = @(& $DenoExe @CommandArgs --json 2>$errFile)
    } else {
      $raw = @(& $DenoExe @CommandArgs --json)
    }
    $code = $LASTEXITCODE
    $text = (($raw | ForEach-Object { [string]$_ }) -join [Environment]::NewLine).Trim()
    if($code -ne 0){return [pscustomobject]@{Ok=$false;Code=$code;Text=$text;Data=$null}}
    if([string]::IsNullOrWhiteSpace($text)){return [pscustomobject]@{Ok=$false;Code=1;Text='JSON vazio';Data=$null}}
    try{$data=$text|ConvertFrom-Json}catch{return [pscustomobject]@{Ok=$false;Code=1;Text=('JSON invalido: '+$text);Data=$null}}
    return [pscustomobject]@{Ok=$true;Code=0;Text=$text;Data=$data}
  } finally { Remove-Item $errFile -Force -ErrorAction SilentlyContinue }
}

function Add-DenoOrgCandidates {
  param([object]$Node,[System.Collections.Generic.HashSet[string]]$Set)
  if($null -eq $Node){return}
  if($Node -is [string] -or $Node -is [ValueType]){return}
  if($Node -is [System.Collections.IEnumerable] -and -not ($Node -is [pscustomobject])){
    foreach($item in $Node){Add-DenoOrgCandidates -Node $item -Set $Set}
    return
  }
  foreach($prop in $Node.PSObject.Properties){
    if(($prop.Name -eq 'slug' -or $prop.Name -eq 'name') -and $prop.Value -is [string]){
      $v=([string]$prop.Value).Trim()
      if($v -match '^[A-Za-z0-9][A-Za-z0-9._-]{1,127}$'){[void]$Set.Add($v)}
    }
    Add-DenoOrgCandidates -Node $prop.Value -Set $Set
  }
}

function Garantir-DenoAuth {
  Remove-Item Env:DENO_DEPLOY_TOKEN -ErrorAction SilentlyContinue
  Etapa 'Autenticacao Deno + descoberta automatica do org/app'
  Write-Host 'O script nao usa mais slug fixo. Ele descobre os orgs da conta autenticada e procura o app pelo dominio publico exato.' -ForegroundColor Yellow

  $orgs = Invoke-DenoJsonDirect -CommandArgs @('deploy','orgs','list') -Rotulo 'Listar orgs Deno'
  if(-not $orgs.Ok){
    Write-Host 'Sessao Deno ausente ou invalida; iniciando autorizacao oficial no navegador.' -ForegroundColor Yellow
    & $DenoExe deploy orgs list
    $loginCode=$LASTEXITCODE
    if($loginCode -ne 0){Falhar "Autenticacao/listagem de orgs Deno terminou com codigo $loginCode."}
    $orgs = Invoke-DenoJsonDirect -CommandArgs @('deploy','orgs','list') -Rotulo 'Listar orgs apos login'
  }
  if(-not $orgs.Ok){Falhar "Nao foi possivel listar orgs da conta Deno autenticada. exit=$($orgs.Code)"}

  $who = Invoke-DenoJsonDirect -CommandArgs @('deploy','whoami') -Rotulo 'Confirmar identidade Deno'
  if(-not $who.Ok){Falhar "Deno whoami falhou apos autenticacao. exit=$($who.Code)"}

  $orgSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  if(-not [string]::IsNullOrWhiteSpace($DenoOrg)){[void]$orgSet.Add($DenoOrg)}
  Add-DenoOrgCandidates -Node $orgs.Data -Set $orgSet
  Add-DenoOrgCandidates -Node $who.Data -Set $orgSet
  if($orgSet.Count -eq 0){Falhar 'A conta Deno autenticada nao retornou nenhuma organizacao acessivel.'}

  $resolvedOrg=''
  foreach($candidate in @($orgSet)){
    $probe=Invoke-DenoJsonDirect -CommandArgs @('deploy','apps','get','--org',$candidate,'--app',$DenoApp,'--non-interactive') -Rotulo ('Procurar app em '+$candidate) -QuietErrors
    if($probe.Ok){
      $serialized=$probe.Data|ConvertTo-Json -Depth 30 -Compress
      if($serialized.Contains($ExpectedBackend)){$resolvedOrg=$candidate;break}
    }
  }

  if([string]::IsNullOrWhiteSpace($resolvedOrg)){
    foreach($candidate in @($orgSet)){
      $apps=Invoke-DenoJsonDirect -CommandArgs @('deploy','apps','list','--org',$candidate,'--non-interactive') -Rotulo ('Listar apps em '+$candidate) -QuietErrors
      if($apps.Ok){
        $serialized=$apps.Data|ConvertTo-Json -Depth 30 -Compress
        if($serialized.Contains($ExpectedBackend)){$resolvedOrg=$candidate;break}
      }
    }
  }

  if([string]::IsNullOrWhiteSpace($resolvedOrg)){
    $visible=(@($orgSet)|Sort-Object) -join ', '
    Falhar ('AUTH DENO PASS, mas nenhum org acessivel possui o app/dominio canonico '+$ExpectedBackend+'. Orgs visiveis: '+$visible)
  }

  $script:DenoOrg=$resolvedOrg
  $verify=Invoke-DenoJsonDirect -CommandArgs @('deploy','env','list','--org',$script:DenoOrg,'--app',$DenoApp,'--non-interactive') -Rotulo 'Validar acesso aos env vars do app'
  if(-not $verify.Ok){Falhar "O app foi localizado em $script:DenoOrg, mas env list foi recusado. exit=$($verify.Code)"}
  Ok ('DENO_ORG_AUTO_DISCOVERY_CONTRACT: org resolvido = '+$script:DenoOrg)
  Ok 'DENO_CANONICAL_APP_DOMAIN_MATCH_CONTRACT'
}

function Baixar-E-Validar-MainAtual
'@
  if (-not [regex]::IsMatch($text,$authPattern)) { throw 'Funcao Garantir-DenoAuth esperada nao foi encontrada; patch recusado.' }
  $text = [regex]::Replace($text,$authPattern,[System.Text.RegularExpressions.MatchEvaluator]{ param($m) $newAuth },1)

  $oldApp1 = "`$app=Executar-Nativo -Exe `$DenoExe -Args @('deploy','apps','get','--org',`$DenoOrg,'--app',`$DenoApp,'--json','--non-interactive') -TimeoutSec 60 -Rotulo 'Validar app Deno existente'"
  $oldApp2 = "Exigir-Sucesso `$app 'App Deno reino-tribal-api nao foi encontrado.'"
  $newApp1 = "Write-Host ('PASS: app Deno canonico validado automaticamente no org '+`$DenoOrg) -ForegroundColor Green"
  if (-not $text.Contains($oldApp1) -or -not $text.Contains($oldApp2)) { throw 'Bloco apps get esperado nao foi encontrado; patch recusado.' }
  $text = $text.Replace($oldApp1,$newApp1).Replace($oldApp2,'')

  $oldPass1 = "`$up1=Executar-Nativo -Exe `$DenoExe -Args @('deploy','env','update-value','RT_ADMIN_PASSWORD',`$adminPassword,'--org',`$DenoOrg,'--app',`$DenoApp,'--non-interactive') -TimeoutSec 90 -Rotulo 'Atualizar RT_ADMIN_PASSWORD'"
  $oldPass2 = "Exigir-Sucesso `$up1 'Deno recusou RT_ADMIN_PASSWORD.'"
  $newPass = @'
  $up1=Invoke-DenoJsonDirect -CommandArgs @('deploy','env','update-value','RT_ADMIN_PASSWORD',$adminPassword,'--org',$DenoOrg,'--app',$DenoApp,'--non-interactive') -Rotulo 'Atualizar RT_ADMIN_PASSWORD'
  if(-not $up1.Ok){Falhar "Deno recusou RT_ADMIN_PASSWORD. exit=$($up1.Code)"}
'@
  $oldRecovery1 = "`$up2=Executar-Nativo -Exe `$DenoExe -Args @('deploy','env','update-value','RT_ADMIN_RECOVERY_KEY',`$recoveryKey,'--org',`$DenoOrg,'--app',`$DenoApp,'--non-interactive') -TimeoutSec 90 -Rotulo 'Atualizar RT_ADMIN_RECOVERY_KEY'"
  $oldRecovery2 = "Exigir-Sucesso `$up2 'Deno recusou RT_ADMIN_RECOVERY_KEY.'"
  $newRecovery = @'
  $up2=Invoke-DenoJsonDirect -CommandArgs @('deploy','env','update-value','RT_ADMIN_RECOVERY_KEY',$recoveryKey,'--org',$DenoOrg,'--app',$DenoApp,'--non-interactive') -Rotulo 'Atualizar RT_ADMIN_RECOVERY_KEY'
  if(-not $up2.Ok){Falhar "Deno recusou RT_ADMIN_RECOVERY_KEY. exit=$($up2.Code)"}
'@
  foreach($required in @($oldPass1,$oldPass2,$oldRecovery1,$oldRecovery2)){if(-not $text.Contains($required)){throw 'Bloco update-value esperado nao foi encontrado; patch recusado.'}}
  $text = $text.Replace($oldPass1,$newPass).Replace($oldPass2,'').Replace($oldRecovery1,$newRecovery).Replace($oldRecovery2,'')

  $text = $text.Replace("`$ExecutorRevision = 'SAFE-CLI-AUTH-2'","`$ExecutorRevision = 'SAFE-CLI-AUTH-7'")
  [IO.File]::WriteAllText($PatchedPath,$text,(New-Object Text.UTF8Encoding($false)))

  $tokens=$null;$errors=$null
  [Management.Automation.Language.Parser]::ParseFile($PatchedPath,[ref]$tokens,[ref]$errors)|Out-Null
  if ($errors.Count) { $errors|Format-List|Out-String|Write-Host; throw 'RT91 CLI-AUTH-7 nao passou no parser PowerShell.' }

  $patched = [IO.File]::ReadAllText($PatchedPath)
  foreach ($needle in @(
    "`$ExecutorRevision = 'SAFE-CLI-AUTH-7'",
    'DENO_ORG_AUTO_DISCOVERY_CONTRACT',
    'DENO_CANONICAL_APP_DOMAIN_MATCH_CONTRACT',
    "access-control-allow-origin:\s*https://kaalflash12\.github\.io",
    "@('deploy','orgs','list')",
    "@('deploy','whoami')",
    "@('deploy','apps','get','--org',`$candidate,'--app',`$DenoApp,'--non-interactive')",
    "@('deploy','env','update-value','RT_ADMIN_PASSWORD',`$adminPassword,'--org',`$DenoOrg,'--app',`$DenoApp,'--non-interactive')",
    "@('deploy','env','update-value','RT_ADMIN_RECOVERY_KEY',`$recoveryKey,'--org',`$DenoOrg,'--app',`$DenoApp,'--non-interactive')",
    'ANTI_DOWNGRADE: nenhum source deploy executado = PASS',
    'REINO_TRIBAL_ADMIN_RT91_VALIDADO'
  )) { if (-not $patched.Contains($needle)) { throw "Patch RT91 CLI-AUTH-7 incompleto: $needle" } }
  foreach($forbidden in @('console.deno.com/auth/interactive','console.deno.com/auth/exchange',"'deploy','--org'","Executar-Nativo -Exe `$DenoExe -Args @('deploy'")){
    if($patched.Contains($forbidden)){throw "RT91 CLI-AUTH-7 ainda contem caminho proibido: $forbidden"}
  }

  Write-Host 'PASS: RT91 CLI-AUTH-7 parseado.' -ForegroundColor Green
  Write-Host 'PASS: DENO_ORG_AUTO_DISCOVERY_CONTRACT' -ForegroundColor Green
  Write-Host 'PASS: DENO_CANONICAL_APP_DOMAIN_MATCH_CONTRACT' -ForegroundColor Green
  Write-Host 'PASS: DENO_ALL_DEPLOY_DIRECT_ARGV_CONTRACT' -ForegroundColor Green
  Write-Host 'PASS: CORS_GITHUB_PAGES_EXACT_ORIGIN_CONTRACT' -ForegroundColor Green
  Write-Host 'PASS: ANTI_DOWNGRADE_NO_SOURCE_DEPLOY_CONTRACT' -ForegroundColor Green

  $childArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$PatchedPath)
  if ($IdentityOnly) { $childArgs += '-IdentityOnly' }
  if ($PreflightOnly) { $childArgs += '-PreflightOnly' }
  if ($ValidateOnly) { $childArgs += '-ValidateOnly' }
  if ($DenoExeOverride) { $childArgs += @('-DenoExeOverride',$DenoExeOverride) }
  & powershell.exe @childArgs
  $code=$LASTEXITCODE
  if($code -ne 0){throw "RT91 CLI-AUTH-7 terminou com codigo $code"}
} finally {
  Remove-Item $Tmp -Recurse -Force -ErrorAction SilentlyContinue
}
