$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

$Helper=Join-Path $PSScriptRoot 'rt91_process_helpers.ps1'
$Tmp=Join-Path $env:TEMP ('rt91-token-bridge-'+[Guid]::NewGuid().ToString('N'))
$Fake=Join-Path $Tmp 'fake-deno-token.exe'

function Assert-True([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}

try {
  New-Item -ItemType Directory -Force -Path $Tmp|Out-Null
  $tokens=$null;$errors=$null
  [Management.Automation.Language.Parser]::ParseFile($Helper,[ref]$tokens,[ref]$errors)|Out-Null
  Assert-True ($errors.Count -eq 0) ('Helper falhou no parser: '+(($errors|Out-String)))

  $source=@'
using System;
public static class Program {
  public static int Main(string[] args){
    Console.Error.WriteLine("Download https://jsr.io/@deno/deploy/meta.json");
    var expected=Environment.GetEnvironmentVariable("FAKE_EXPECT_DENO_TOKEN") ?? "";
    var actual=Environment.GetEnvironmentVariable("DENO_DEPLOY_TOKEN") ?? "";
    if(expected.Length>0 && actual!=expected){
      Console.Error.WriteLine("TOKEN_BRIDGE_MISSING");
      return 9;
    }
    Console.WriteLine("{\"authenticated\":true,\"orgs\":[{\"slug\":\"real-org\"}]}");
    return 0;
  }
}
'@
  Add-Type -TypeDefinition $source -Language CSharp -OutputAssembly $Fake -OutputType ConsoleApplication
  Assert-True (Test-Path $Fake) 'fake-deno-token.exe nao foi compilado.'

  . $Helper
  Remove-Item Env:DENO_DEPLOY_TOKEN -ErrorAction SilentlyContinue
  $env:RT91_DENO_DEPLOY_TOKEN='RT91_TOKEN_BRIDGE_SENTINEL'
  $env:FAKE_EXPECT_DENO_TOKEN='RT91_TOKEN_BRIDGE_SENTINEL'

  $r=Invoke-RTDenoJson -DenoExe $Fake -CommandArgs @('deploy','whoami')
  Assert-True $r.Ok ('Token bridge nao chegou ao processo Deno. '+$r.Text)
  Assert-True ($r.Stderr -match 'Download https://jsr.io') 'stderr informativo nao foi preservado.'
  Assert-True (-not (Test-Path Env:DENO_DEPLOY_TOKEN)) 'DENO_DEPLOY_TOKEN vazou para o processo PowerShell pai.'

  Write-Host 'RT91_WINDOWS_POWERSHELL_51_TOKEN_BRIDGE_SELFTEST_PASS' -ForegroundColor Green
} finally {
  Remove-Item Env:DENO_DEPLOY_TOKEN -ErrorAction SilentlyContinue
  Remove-Item Env:RT91_DENO_DEPLOY_TOKEN -ErrorAction SilentlyContinue
  Remove-Item Env:FAKE_EXPECT_DENO_TOKEN -ErrorAction SilentlyContinue
  Remove-Item $Tmp -Recurse -Force -ErrorAction SilentlyContinue
}
