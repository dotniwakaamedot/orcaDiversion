Set-StrictMode -Version Latest
function New-IssueReviewTaskConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$RepoRoot,
        [Parameter(Mandatory=$true)][string]$ConfigPath,
        [Parameter(Mandatory=$true)][string]$PythonwPath,
        [Parameter(Mandatory=$true)][string]$LauncherPath,
        [Parameter(Mandatory=$true)][string]$CurrentUser,
        [Parameter(Mandatory=$true)][string]$TaskName,
        [Parameter(Mandatory=$true)][string]$TimeZoneId,
        [Parameter(Mandatory=$true)][datetime]$StartAt,
        [Parameter(Mandatory=$true)][string]$Interval
    )
    foreach ($value in @($RepoRoot, $ConfigPath, $PythonwPath, $LauncherPath, $CurrentUser, $TaskName, $TimeZoneId, $Interval)) {
        if ([string]::IsNullOrWhiteSpace($value) -or $value -match '[\x00-\x1f"]') { throw 'Invalid task value.' }
    }
    foreach ($path in @($RepoRoot, $ConfigPath, $PythonwPath, $LauncherPath)) {
        if (-not [IO.Path]::IsPathRooted($path)) { throw 'Absolute paths required.' }
        if ($path.EndsWith('\')) { throw 'Paths ending in backslash cannot be safely quoted.' }
    }
    if ([IO.Path]::GetFileName($PythonwPath) -ine 'pythonw.exe') { throw 'A pythonw.exe executable is required.' }
    if ($TaskName -match '[\\/]') { throw 'Invalid task name.' }
    $null = [TimeZoneInfo]::FindSystemTimeZoneById($TimeZoneId)
    if (([Xml.XmlConvert]::ToTimeSpan($Interval)).TotalMinutes -lt 1) { throw 'Interval must be at least one minute.' }
    [pscustomobject][ordered]@{
        TaskName=$TaskName; TaskPath='\'; Executable=$PythonwPath
        Arguments=('"'+$LauncherPath+'" --config "'+$ConfigPath+'"')
        WorkingDirectory=$RepoRoot; StartAt=$StartAt.ToString('o'); Interval=$Interval
        TimeZoneId=$TimeZoneId; User=$CurrentUser; LogonType='Interactive'; RunLevel='Limited'
        Hidden=$true; MultipleInstances='IgnoreNew'; ExecutionTimeLimit='PT0S'
        AllowStartIfOnBatteries=$true; DontStopIfGoingOnBatteries=$true
        Description='Reviewed issue workflow'; ModelInvoked=$false
    }
}
function Assert-WindowlessPython {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$PythonwPath)
    if ([IO.Path]::GetFileName($PythonwPath) -ine 'pythonw.exe' -or -not (Test-Path -LiteralPath $PythonwPath -PathType Leaf)) {
        throw 'An existing pythonw.exe is required.'
    }
    $info=New-Object Diagnostics.ProcessStartInfo
    $info.FileName=$PythonwPath
    $info.UseShellExecute=$false
    $info.CreateNoWindow=$true
    $info.Arguments='-c "import ctypes,sys; sys.exit(0 if sys.executable.lower().endswith(''pythonw.exe'') and not ctypes.windll.kernel32.GetConsoleWindow() and not ctypes.windll.kernel32.GetConsoleCP() else 1)"'
    $process=[Diagnostics.Process]::Start($info)
    try {
        if (-not $process.WaitForExit(10000)) {
            $process.Kill()
            $process.WaitForExit()
            throw 'pythonw verification timed out.'
        }
        if ($process.ExitCode -ne 0) { throw 'pythonw verification failed.' }
    } finally { $process.Dispose() }
}
function Invoke-IssueReviewTaskWriter {
    param([Parameter(Mandatory=$true)][psobject]$Configuration, [scriptblock]$Writer)
    if ($null -eq $Writer) { throw 'An explicit task writer is required.' }
    & $Writer $Configuration
}
