$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

$RepoRoot=Split-Path $PSScriptRoot -Parent
$Helper=Join-Path $PSScriptRoot 'rt91_process_helpers.ps1'
$Auth=Join-Path $RepoRoot 'REINO_TRIBAL_ADMIN_FINAL_RT91_AUTH9.ps1'
$Tmp=Join-Path $env:TEMP ('rt91-win-selftest-'+[Guid]::NewGuid().ToString('N'))
$Fake=Join-Path $Tmp 'fake-deno.exe'
$Log=Join-Path $Tmp 'fake-deno.log'

function Assert-True([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}

try{
  New-Item -ItemType Directory -Force -Path $Tmp|Out-Null
  foreach($path in @($Helper,$Auth)){
    Assert-True (Test-Path $path) "Arquivo ausente: $path"
    $tokens=$null;$errors=$null
    [Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)|Out-Null
    Assert-True ($errors.Count -eq 0) ("Parser PowerShell falhou em $path : "+(($errors|Out-String)))
  }

  $source=@'
using System;
using System.IO;
using System.Linq;
public static class Program {
  static bool Has(string[] a,string v){ return a.Any(x => string.Equals(x,v,StringComparison.OrdinalIgnoreCase)); }
  static string After(string[] a,string v){ for(int i=0;i<a.Length-1;i++) if(string.Equals(a[i],v,StringComparison.OrdinalIgnoreCase)) return a[i+1]; return ""; }
  public static int Main(string[] args){
    var log=Environment.GetEnvironmentVariable("FAKE_DENO_LOG");
    if(!String.IsNullOrEmpty(log)) File.AppendAllText(log,String.Join("|",args)+Environment.NewLine);
    Console.Error.WriteLine("Download https://jsr.io/@deno/deploy/meta.json");
    if(args.Length==1 && args[0]=="--version"){ Console.WriteLine("deno 2.9.5"); return 0; }
    if(args.Length>=3 && args[0]=="deploy" && args[1]=="whoami"){
      Console.WriteLine("{\"authenticated\":true,\"user\":{\"name\":\"Windows Selftest\"},\"orgs\":[{\"slug\":\"real-org\"}]}"); return 0;
    }
    if(args.Length>=3 && args[0]=="deploy" && args[1]=="orgs" && args[2]=="list"){
      Console.WriteLine("[{\"slug\":\"real-org\"}]"); return 0;
    }
    if(args.Length>=3 && args[0]=="deploy" && args[1]=="apps" && args[2]=="get"){
      var org=After(args,"--org");
      if(Environment.GetEnvironmentVariable("FAKE_DENO_NO_APP")=="1" || org!="real-org"){
        Console.Error.WriteLine("{\"error\":{\"code\":\"NOT_FOUND\",\"message\":\"not found\"}}"); return 4;
      }
      Console.WriteLine("{\"app\":\"reino-tribal-api\",\"productionUrl\":\"https://reino-tribal-api.mestrederpg35.deno.net\",\"domains\":[]}"); return 0;
    }
    if(args.Length>=3 && args[0]=="deploy" && args[1]=="env" && args[2]=="list"){
      if(After(args,"--org")!="real-org"){ Console.Error.WriteLine("org not found"); return 4; }
      Console.WriteLine("[]"); return 0;
    }
    if(args.Length>=3 && args[0]=="deploy" && args[1]=="env" && args[2]=="update-value"){
      if(After(args,"--org")!="real-org"){ Console.Error.WriteLine("org not found"); return 4; }
      Console.WriteLine("{\"ok\":true}"); return 0;
    }
    Console.Error.WriteLine("unexpected args: "+String.Join(" ",args)); return 2;
  }
}
'@
  Add-Type -TypeDefinition $source -Language CSharp -OutputAssembly $Fake -OutputType ConsoleApplication
  Assert-True (Test-Path $Fake) 'fake-deno.exe nao foi compilado.'

  . $Helper
  $env:FAKE_DENO_LOG=$Log
  $env:FAKE_DENO_NO_APP=''

  # Teste direto da causa que falhou no PC: stderr informativo + exit 4 nao podem virar excecao PowerShell.
  $bad=Invoke-RTDenoJson -DenoExe $Fake -CommandArgs @('deploy','apps','get','--org','mestrederpg35','--app','reino-tribal-api','--non-interactive')
  Assert-True (-not $bad.Ok) 'org errado deveria falhar.'
  Assert-True ($bad.Code -eq 4) ('exit code do org errado deveria ser 4, recebido '+$bad.Code)
  Assert-True ($bad.Stderr -match 'Download https://jsr.io') 'stderr informativo nao foi capturado.'

  $good=Invoke-RTDenoJson -DenoExe $Fake -CommandArgs @('deploy','apps','get','--org','real-org','--app','reino-tribal-api','--non-interactive')
  Assert-True $good.Ok 'org correto deveria passar apesar do stderr.'
  Assert-True (($good.Data|ConvertTo-Json -Compress) -match 'reino-tribal-api\.mestrederpg35\.deno\.net') 'productionUrl canonica ausente.'

  # Executa o AUTH9 real em modo de descoberta e testa tambem update-value pelo helper real.
  $env:RT91_FAKE_DENO_SELFTEST='1'
  Remove-Item $Log -Force -ErrorAction SilentlyContinue
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Auth -DenoExeOverride $Fake -DiscoveryTestOnly -PreferredDenoOrg mestrederpg35
  $code=$LASTEXITCODE
  Assert-True ($code -eq 0) ("AUTH9 discovery selftest falhou exit=$code")
  $calls=if(Test-Path $Log){[IO.File]::ReadAllText($Log)}else{''}
  foreach($needle in @('deploy|whoami','deploy|apps|get|--org|real-org','deploy|env|list|--org|real-org','deploy|env|update-value|RT_SELFTEST_ONLY|sentinel|--org|real-org')){
    Assert-True ($calls.Contains($needle)) ("Chamada esperada ausente: $needle`n$calls")
  }
  Assert-True (-not $calls.Contains('RT_ADMIN_PASSWORD')) 'Selftest nao pode tocar RT_ADMIN_PASSWORD.'
  Assert-True (-not $calls.Contains('RT_ADMIN_RECOVERY_KEY')) 'Selftest nao pode tocar RT_ADMIN_RECOVERY_KEY.'

  # Cenario negativo: autenticado, org visivel, app ausente. Deve falhar sem update-value.
  $env:RT91_FAKE_DENO_SELFTEST=''
  $env:FAKE_DENO_NO_APP='1'
  Remove-Item $Log -Force -ErrorAction SilentlyContinue
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Auth -DenoExeOverride $Fake -DiscoveryTestOnly -PreferredDenoOrg mestrederpg35
  $negativeCode=$LASTEXITCODE
  Assert-True ($negativeCode -ne 0) 'Cenario sem app deveria falhar.'
  $negativeCalls=if(Test-Path $Log){[IO.File]::ReadAllText($Log)}else{''}
  Assert-True (-not $negativeCalls.Contains('update-value')) 'Cenario sem app nao pode executar update-value.'

  Write-Host 'RT91_WINDOWS_POWERSHELL_51_NATIVE_STDERR_SELFTEST_PASS' -ForegroundColor Green
}finally{
  Remove-Item Env:RT91_FAKE_DENO_SELFTEST -ErrorAction SilentlyContinue
  Remove-Item Env:FAKE_DENO_LOG -ErrorAction SilentlyContinue
  Remove-Item Env:FAKE_DENO_NO_APP -ErrorAction SilentlyContinue
  Remove-Item $Tmp -Recurse -Force -ErrorAction SilentlyContinue
}
