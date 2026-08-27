Set-StrictMode -Version Latest

function Invoke-RTNativeProcess {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory=$true)][string]$FilePath,
    [Parameter(Mandatory=$true)][string[]]$ArgumentList,
    [string]$WorkingDirectory='',
    [switch]$Interactive
  )

  $sp=@{
    FilePath=$FilePath
    ArgumentList=$ArgumentList
    Wait=$true
    PassThru=$true
    NoNewWindow=$true
  }
  if($WorkingDirectory){$sp.WorkingDirectory=$WorkingDirectory}

  if($Interactive){
    $p=Start-Process @sp
    return [pscustomobject]@{Code=[int]$p.ExitCode;Stdout='';Stderr=''}
  }

  $id=[Guid]::NewGuid().ToString('N')
  $outFile=Join-Path $env:TEMP ('rt91-native-'+$id+'.out')
  $errFile=Join-Path $env:TEMP ('rt91-native-'+$id+'.err')
  try{
    $sp.RedirectStandardOutput=$outFile
    $sp.RedirectStandardError=$errFile
    $p=Start-Process @sp
    $stdout=if(Test-Path $outFile){[IO.File]::ReadAllText($outFile).Trim()}else{''}
    $stderr=if(Test-Path $errFile){[IO.File]::ReadAllText($errFile).Trim()}else{''}
    return [pscustomobject]@{Code=[int]$p.ExitCode;Stdout=$stdout;Stderr=$stderr}
  }finally{
    Remove-Item $outFile,$errFile -Force -ErrorAction SilentlyContinue
  }
}

function Invoke-RTDenoText {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory=$true)][string]$DenoExe,
    [Parameter(Mandatory=$true)][string[]]$CommandArgs,
    [string]$WorkingDirectory=''
  )
  $r=Invoke-RTNativeProcess -FilePath $DenoExe -ArgumentList $CommandArgs -WorkingDirectory $WorkingDirectory
  $text=(($r.Stdout+"`n"+$r.Stderr).Trim())
  return [pscustomobject]@{Ok=($r.Code -eq 0);Code=[int]$r.Code;Text=$text;Stdout=$r.Stdout;Stderr=$r.Stderr}
}

function Invoke-RTDenoJson {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory=$true)][string]$DenoExe,
    [Parameter(Mandatory=$true)][string[]]$CommandArgs
  )
  $args=@($CommandArgs)+@('--json')
  $r=Invoke-RTNativeProcess -FilePath $DenoExe -ArgumentList $args
  if($r.Code -ne 0){
    return [pscustomobject]@{Ok=$false;Code=[int]$r.Code;Text=(($r.Stdout+"`n"+$r.Stderr).Trim());Data=$null;Stdout=$r.Stdout;Stderr=$r.Stderr}
  }
  if([string]::IsNullOrWhiteSpace($r.Stdout)){
    return [pscustomobject]@{Ok=$false;Code=1;Text=('JSON vazio. stderr='+$r.Stderr);Data=$null;Stdout=$r.Stdout;Stderr=$r.Stderr}
  }
  try{$data=$r.Stdout|ConvertFrom-Json}catch{
    return [pscustomobject]@{Ok=$false;Code=1;Text=('JSON invalido: '+$r.Stdout+' stderr='+$r.Stderr);Data=$null;Stdout=$r.Stdout;Stderr=$r.Stderr}
  }
  return [pscustomobject]@{Ok=$true;Code=0;Text=$r.Stdout;Data=$data;Stdout=$r.Stdout;Stderr=$r.Stderr}
}

function Invoke-RTDenoInteractive {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory=$true)][string]$DenoExe,
    [Parameter(Mandatory=$true)][string[]]$CommandArgs
  )
  return Invoke-RTNativeProcess -FilePath $DenoExe -ArgumentList $CommandArgs -Interactive
}
