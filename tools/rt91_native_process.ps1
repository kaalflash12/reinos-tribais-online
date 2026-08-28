Set-StrictMode -Version 2.0

function ConvertTo-RTWindowsCommandLineArgument {
  [CmdletBinding()]
  param([AllowEmptyString()][string]$Value)

  if($null -eq $Value){ return '""' }
  if($Value.Length -eq 0){ return '""' }
  if($Value -notmatch '[\s"]'){ return $Value }

  $sb = New-Object System.Text.StringBuilder
  [void]$sb.Append('"')
  $slashes = 0
  foreach($ch in $Value.ToCharArray()){
    if($ch -eq '\'){
      $slashes++
      continue
    }
    if($ch -eq '"'){
      if($slashes -gt 0){ [void]$sb.Append(('\' * ($slashes * 2))) }
      [void]$sb.Append('\"')
      $slashes = 0
      continue
    }
    if($slashes -gt 0){
      [void]$sb.Append(('\' * $slashes))
      $slashes = 0
    }
    [void]$sb.Append($ch)
  }
  if($slashes -gt 0){ [void]$sb.Append(('\' * ($slashes * 2))) }
  [void]$sb.Append('"')
  return $sb.ToString()
}

function Join-RTWindowsCommandLineArguments {
  [CmdletBinding()]
  param([string[]]$ArgumentList = @())
  return (($ArgumentList | ForEach-Object { ConvertTo-RTWindowsCommandLineArgument -Value ([string]$_) }) -join ' ')
}

function Invoke-RTNative {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory=$true)][string]$FilePath,
    [string[]]$ArgumentList = @(),
    [int]$TimeoutSeconds = 0,
    [hashtable]$Environment = @(),
    [string]$WorkingDirectory = ''
  )

  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $FilePath
  $psi.Arguments = Join-RTWindowsCommandLineArguments -ArgumentList $ArgumentList
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.CreateNoWindow = $true
  if($WorkingDirectory){ $psi.WorkingDirectory = $WorkingDirectory }
  foreach($key in $Environment.Keys){
    $psi.EnvironmentVariables[[string]$key] = [string]$Environment[$key]
  }

  $proc = New-Object System.Diagnostics.Process
  $proc.StartInfo = $psi
  try {
    if(-not $proc.Start()){ throw "Falha ao iniciar processo nativo: $FilePath" }
    $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
    $stderrTask = $proc.StandardError.ReadToEndAsync()

    if($TimeoutSeconds -gt 0){
      $finished = $proc.WaitForExit($TimeoutSeconds * 1000)
      if(-not $finished){
        try { $proc.Kill() } catch {}
        try { $proc.WaitForExit() } catch {}
        throw "Timeout de processo nativo apos ${TimeoutSeconds}s: $FilePath"
      }
    } else {
      $proc.WaitForExit()
    }

    $stdout = $stdoutTask.GetAwaiter().GetResult()
    $stderr = $stderrTask.GetAwaiter().GetResult()
    return [pscustomobject]@{
      FilePath = $FilePath
      Arguments = $psi.Arguments
      ExitCode = [int]$proc.ExitCode
      StdOut = [string]$stdout
      StdErr = [string]$stderr
    }
  }
  finally {
    $proc.Dispose()
  }
}

function Assert-RTNativeSuccess {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory=$true)]$Result,
    [string]$Label = 'processo nativo'
  )
  if([int]$Result.ExitCode -ne 0){
    $err = ([string]$Result.StdErr).Trim()
    if($err.Length -gt 1200){ $err = $err.Substring(0,1200) + '...' }
    throw "$Label terminou com exit code $($Result.ExitCode). STDERR: $err"
  }
  return $Result
}

# Contract markers used by the Windows PowerShell 5.1 self-test.
$script:RT91_NATIVE_PROCESS_CONTRACT = 'RT91_NATIVE_PROCESS_PS51_V1'
$script:RT91_NATIVE_STDERR_IS_DATA = 'STDERR_DOES_NOT_DEFINE_FAILURE'
$script:RT91_NATIVE_EXITCODE_IS_AUTHORITY = 'EXITCODE_DEFINES_FAILURE'
