Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
# RT91_PS51_SELFTEST_TRIGGER=1

. (Join-Path $PSScriptRoot 'rt91_native_process.ps1')

function Assert-RT([bool]$Condition,[string]$Message){
  if(-not $Condition){ throw "SELFTEST FAIL: $Message" }
}
function Pass-RT([string]$Message){ Write-Host "PASS: $Message" }

Assert-RT ($script:RT91_NATIVE_PROCESS_CONTRACT -eq 'RT91_NATIVE_PROCESS_PS51_V1') 'helper contract'
Pass-RT 'helper contract loaded'

$work = Join-Path $env:TEMP ('rt91-ps51-selftest-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work -Force | Out-Null
$fake = Join-Path $work 'fake-deno.exe'
$mutationLog = Join-Path $work 'mutations.log'

$csharp = @'
using System;
using System.IO;
using System.Text;
using System.Collections.Generic;

public static class Program {
  static string FindValue(string[] args, string flag) {
    for(int i=0;i<args.Length-1;i++) if(args[i] == flag) return args[i+1];
    return "";
  }
  static int FindIndex(string[] args, string value) {
    for(int i=0;i<args.Length;i++) if(args[i] == value) return i;
    return -1;
  }
  public static int Main(string[] args) {
    Console.Error.WriteLine("Download https://jsr.io/@deno/deploy/meta.json");
    if(args.Length == 0) return 0;

    if(args[0] == "echoargs") {
      for(int i=1;i<args.Length;i++) {
        string b64 = Convert.ToBase64String(Encoding.UTF8.GetBytes(args[i]));
        Console.Out.WriteLine("ARG:" + b64);
      }
      return 0;
    }
    if(args[0] == "flood") {
      Console.Out.Write(new string('O', 131072));
      Console.Error.Write(new string('E', 131072));
      return 0;
    }
    if(args[0] == "exit4") {
      Console.Error.WriteLine("synthetic exit code 4");
      return 4;
    }
    if(args[0] == "--version") {
      Console.Out.WriteLine("Deno 2.9.5");
      return 0;
    }
    if(args[0] == "check") {
      Console.Out.WriteLine("Check OK");
      return 0;
    }
    if(args[0] == "deploy") {
      if(args.Length >= 2 && args[1] == "whoami") {
        Console.Out.WriteLine("{\"user\":{\"name\":\"Carlos Nobre\"},\"organizations\":[{\"slug\":\"wrong-org\"},{\"slug\":\"good-org\"}]}");
        return 0;
      }
      if(args.Length >= 3 && args[1] == "apps" && args[2] == "get") {
        string org = FindValue(args, "--org");
        if(org != "good-org") { Console.Error.WriteLine("organization/app not found"); return 4; }
        Console.Out.WriteLine("{\"slug\":\"reino-tribal-api\",\"productionUrl\":\"https://reino-tribal-api.mestrederpg35.deno.net\"}");
        return 0;
      }
      if(args.Length >= 3 && args[1] == "env" && args[2] == "list") {
        string org = FindValue(args, "--org");
        if(org != "good-org") return 4;
        Console.Out.WriteLine("[{\"key\":\"RT_ADMIN_PASSWORD\",\"secret\":true},{\"key\":\"RT_ADMIN_RECOVERY_KEY\",\"secret\":true}]");
        return 0;
      }
      if(args.Length >= 3 && args[1] == "env" && args[2] == "update-value") {
        string org = FindValue(args, "--org");
        if(org != "good-org") return 4;
        int p = FindIndex(args, "update-value");
        if(p < 0 || p + 1 >= args.Length) return 9;
        string variable = args[p+1];
        string log = Environment.GetEnvironmentVariable("RT_FAKE_LOG") ?? "";
        if(log.Length > 0) File.AppendAllText(log, "UPDATE:" + variable + Environment.NewLine);
        Console.Out.WriteLine("updated " + variable);
        return 0;
      }
    }
    Console.Error.WriteLine("unsupported fake command");
    return 9;
  }
}
'@

try {
  Add-Type -TypeDefinition $csharp -Language CSharp -OutputAssembly $fake -OutputType ConsoleApplication
  Assert-RT (Test-Path -LiteralPath $fake) 'fake-deno.exe compiled'
  Pass-RT 'fake-deno.exe compiled on Windows runner'

  $values = @(
    'plain',
    'with space',
    'dollar$sign',
    'bang!',
    'quote"inside',
    'C:\trail\',
    '',
    'two\\slashes"quote',
    'unicode-ç-ã-漢字'
  )
  $echoArgs = @('echoargs') + $values
  $r = Invoke-RTNative -FilePath $fake -ArgumentList $echoArgs -TimeoutSeconds 30
  Assert-RT ($r.ExitCode -eq 0) 'echoargs exit code'
  Assert-RT ($r.StdErr -match 'Download https://jsr.io/@deno/deploy/meta.json') 'stderr informational data captured'
  $actual = @()
  foreach($line in ($r.StdOut -split "`r?`n")){
    if($line.StartsWith('ARG:')){
      $b64 = $line.Substring(4)
      $actual += [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64))
    }
  }
  Assert-RT ($actual.Count -eq $values.Count) "argument count expected=$($values.Count) actual=$($actual.Count)"
  for($i=0;$i -lt $values.Count;$i++){
    Assert-RT ($actual[$i] -ceq $values[$i]) "argument forwarding index=$i expected=[$($values[$i])] actual=[$($actual[$i])]"
  }
  Pass-RT 'argv forwarding preserves spaces, dollar, bang, quotes, trailing backslashes, empty and unicode'

  $r4 = Invoke-RTNative -FilePath $fake -ArgumentList @('exit4') -TimeoutSeconds 30
  Assert-RT ($r4.ExitCode -eq 4) 'real exit code 4 preserved'
  Assert-RT ($r4.StdErr -match 'Download https://jsr.io/@deno/deploy/meta.json') 'stderr retained on exit 4'
  Pass-RT 'stderr does not become NativeCommandError and exit code 4 is preserved'

  $flood = Invoke-RTNative -FilePath $fake -ArgumentList @('flood') -TimeoutSeconds 30
  Assert-RT ($flood.ExitCode -eq 0) 'flood exit code'
  Assert-RT ($flood.StdOut.Length -ge 131072) 'large stdout captured'
  Assert-RT ($flood.StdErr.Length -ge 131072) 'large stderr captured'
  Pass-RT 'simultaneous stdout/stderr >64KB does not deadlock'

  $ver = Invoke-RTNative -FilePath $fake -ArgumentList @('--version') -TimeoutSeconds 30
  Assert-RT ($ver.ExitCode -eq 0 -and $ver.StdOut -match 'Deno 2.9.5') 'version command'
  $check = Invoke-RTNative -FilePath $fake -ArgumentList @('check','deno/main.js') -TimeoutSeconds 30
  Assert-RT ($check.ExitCode -eq 0) 'check command'
  Pass-RT 'deno version/check simulation works with informational stderr'

  $envMap = @{ RT_FAKE_LOG = $mutationLog }
  $bad = Invoke-RTNative -FilePath $fake -ArgumentList @('deploy','apps','get','--org','wrong-org','--app','reino-tribal-api','--json') -TimeoutSeconds 30 -Environment $envMap
  Assert-RT ($bad.ExitCode -eq 4) 'wrong org must fail'
  Assert-RT (-not (Test-Path -LiteralPath $mutationLog)) 'wrong org cannot mutate'
  Pass-RT 'negative org/app probe leaves mutation log absent'

  $good = Invoke-RTNative -FilePath $fake -ArgumentList @('deploy','apps','get','--org','good-org','--app','reino-tribal-api','--json') -TimeoutSeconds 30 -Environment $envMap
  Assert-RT ($good.ExitCode -eq 0) 'good app probe exit'
  $app = $good.StdOut | ConvertFrom-Json
  Assert-RT ($app.productionUrl -eq 'https://reino-tribal-api.mestrederpg35.deno.net') 'canonical production URL contract'
  Pass-RT 'canonical app domain verified before mutation'

  $envList = Invoke-RTNative -FilePath $fake -ArgumentList @('deploy','env','list','--org','good-org','--app','reino-tribal-api','--json') -TimeoutSeconds 30 -Environment $envMap
  Assert-RT ($envList.ExitCode -eq 0) 'env list preflight'
  Assert-RT ($envList.StdOut -match 'RT_ADMIN_PASSWORD' -and $envList.StdOut -match 'RT_ADMIN_RECOVERY_KEY') 'required env names visible'
  Pass-RT 'env list preflight succeeds'

  $secretA = 'SECRET_VALUE_MUST_NOT_BE_LOGGED_A'
  $secretB = 'SECRET_VALUE_MUST_NOT_BE_LOGGED_B'
  $u1 = Invoke-RTNative -FilePath $fake -ArgumentList @('deploy','env','update-value','RT_ADMIN_PASSWORD',$secretA,'--org','good-org','--app','reino-tribal-api') -TimeoutSeconds 30 -Environment $envMap
  $u2 = Invoke-RTNative -FilePath $fake -ArgumentList @('deploy','env','update-value','RT_ADMIN_RECOVERY_KEY',$secretB,'--org','good-org','--app','reino-tribal-api') -TimeoutSeconds 30 -Environment $envMap
  Assert-RT ($u1.ExitCode -eq 0 -and $u2.ExitCode -eq 0) 'both update-value commands'
  $logText = Get-Content -Raw -LiteralPath $mutationLog
  Assert-RT ($logText -match 'UPDATE:RT_ADMIN_PASSWORD') 'password variable update recorded'
  Assert-RT ($logText -match 'UPDATE:RT_ADMIN_RECOVERY_KEY') 'recovery variable update recorded'
  Assert-RT ($logText -notmatch [regex]::Escape($secretA)) 'password secret value absent from log'
  Assert-RT ($logText -notmatch [regex]::Escape($secretB)) 'recovery secret value absent from log'
  Pass-RT 'exactly named secret updates work and secret values are not logged'

  Write-Host 'RT91_WINDOWS_POWERSHELL51_NATIVE_SELFTEST_PASS'
}
finally {
  Remove-Item -Recurse -Force -LiteralPath $work -ErrorAction SilentlyContinue
}
