Set-StrictMode -Version Latest

function ConvertTo-RTProcessArgument {
  param([AllowNull()][string]$Value)
  if ($null -eq $Value) { return '""' }
  if ($Value -notmatch '[\s"]') { return $Value }
  $escaped = $Value -replace '(\\*)"', '$1$1\"'
  $escaped = $escaped -replace '(\\+)$', '$1$1'
  return '"' + $escaped + '"'
}

function Join-RTProcessArguments {
  param([string[]]$ArgumentList)
  return (($ArgumentList | ForEach-Object { ConvertTo-RTProcessArgument ([string]$_) }) -join ' ')
}

function Invoke-RTProcessCapture {
  param(
    [Parameter(Mandatory=$true)][string]$FilePath,
    [Parameter(Mandatory=$true)][string[]]$ArgumentList,
    [string]$WorkingDirectory=''
  )
  $stdoutFile = Join-Path $env:TEMP ('rt91-proc-' + [Guid]::NewGuid().ToString('N') + '.out')
  $stderrFile = Join-Path $env:TEMP ('rt91-proc-' + [Guid]::NewGuid().ToString('N') + '.err')
  try {
    $params = @{
      FilePath = $FilePath
      ArgumentList = (Join-RTProcessArguments $ArgumentList)
      Wait = $true
      PassThru = $true
      NoNewWindow = $true
      RedirectStandardOutput = $stdoutFile
      RedirectStandardError = $stderrFile
      ErrorAction = 'Stop'
    }
    if ($WorkingDirectory) { $params.WorkingDirectory = $WorkingDirectory }
    $proc = Start-Process @params
    $stdout = if (Test-Path $stdoutFile) { [IO.File]::ReadAllText($stdoutFile) } else { '' }
    $stderr = if (Test-Path $stderrFile) { [IO.File]::ReadAllText($stderrFile) } else { '' }
    return [pscustomobject]@{
      Code = [int]$proc.ExitCode
      Stdout = $stdout.Trim()
      Stderr = $stderr.Trim()
    }
  } finally {
    Remove-Item $stdoutFile,$stderrFile -Force -ErrorAction SilentlyContinue
  }
}

function Invoke-RTProcessInteractive {
  param(
    [Parameter(Mandatory=$true)][string]$FilePath,
    [Parameter(Mandatory=$true)][string[]]$ArgumentList,
    [string]$WorkingDirectory=''
  )
  $params = @{
    FilePath = $FilePath
    ArgumentList = (Join-RTProcessArguments $ArgumentList)
    Wait = $true
    PassThru = $true
    NoNewWindow = $true
    ErrorAction = 'Stop'
  }
  if ($WorkingDirectory) { $params.WorkingDirectory = $WorkingDirectory }
  $proc = Start-Process @params
  return [int]$proc.ExitCode
}

function Invoke-RTDenoJson {
  param(
    [Parameter(Mandatory=$true)][string]$DenoExe,
    [Parameter(Mandatory=$true)][string[]]$CommandArgs,
    [string]$WorkingDirectory=''
  )
  $r = Invoke-RTProcessCapture -FilePath $DenoExe -ArgumentList @($CommandArgs + '--json') -WorkingDirectory $WorkingDirectory
  if ($r.Code -ne 0) {
    return [pscustomobject]@{ Ok=$false; Code=$r.Code; Data=$null; Stdout=$r.Stdout; Stderr=$r.Stderr; Text=(($r.Stdout + [Environment]::NewLine + $r.Stderr).Trim()) }
  }
  if ([string]::IsNullOrWhiteSpace($r.Stdout)) {
    return [pscustomobject]@{ Ok=$false; Code=1; Data=$null; Stdout=''; Stderr=$r.Stderr; Text=('JSON vazio. stderr=' + $r.Stderr) }
  }
  try { $data = $r.Stdout | ConvertFrom-Json }
  catch { return [pscustomobject]@{ Ok=$false; Code=1; Data=$null; Stdout=$r.Stdout; Stderr=$r.Stderr; Text=('JSON invalido: ' + $r.Stdout + ' stderr=' + $r.Stderr) } }
  return [pscustomobject]@{ Ok=$true; Code=0; Data=$data; Stdout=$r.Stdout; Stderr=$r.Stderr; Text=$r.Stdout }
}

function Invoke-RTDenoText {
  param(
    [Parameter(Mandatory=$true)][string]$DenoExe,
    [Parameter(Mandatory=$true)][string[]]$CommandArgs,
    [string]$WorkingDirectory=''
  )
  return Invoke-RTProcessCapture -FilePath $DenoExe -ArgumentList $CommandArgs -WorkingDirectory $WorkingDirectory
}

function Invoke-RTDenoInteractive {
  param(
    [Parameter(Mandatory=$true)][string]$DenoExe,
    [Parameter(Mandatory=$true)][string[]]$CommandArgs,
    [string]$WorkingDirectory=''
  )
  return Invoke-RTProcessInteractive -FilePath $DenoExe -ArgumentList $CommandArgs -WorkingDirectory $WorkingDirectory
}
