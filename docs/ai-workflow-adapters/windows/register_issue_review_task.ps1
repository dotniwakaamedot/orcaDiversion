[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium')]
param(
    [Parameter(Mandatory=$true)][string]$ConfigPath,
    [Parameter(Mandatory=$true)][string]$PythonwPath,
    [Parameter(Mandatory=$true)][string]$TaskName,
    [Parameter(Mandatory=$true)][string]$TimeZoneId,
    [Parameter(Mandatory=$true)][datetime]$StartAt,
    [Parameter(Mandatory=$true)][string]$Interval,
    [switch]$Validated,
    [switch]$TestMode,
    [psobject]$Configuration,
    [scriptblock]$TaskWriter,
    [scriptblock]$PreflightCheck
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'issue_review_config.ps1')
. (Join-Path $PSScriptRoot 'issue_review_task_configuration.ps1')
function Invoke-ReviewedRegistration {
    param([psobject]$Task, [scriptblock]$Preflight, [scriptblock]$Writer)
    if ($null -eq $Preflight -or $null -eq $Writer) { throw 'Explicit preflight and writer are required.' }
    & $Preflight $Task
    if ($PSCmdlet.ShouldProcess($Task.TaskName, 'Register reviewed issue task')) {
        Invoke-IssueReviewTaskWriter -Configuration $Task -Writer $Writer
    }
}
if ($TestMode) {
    if ($null -eq $Configuration) { throw 'TestMode requires configuration.' }
    Invoke-ReviewedRegistration -Task $Configuration -Preflight $PreflightCheck -Writer $TaskWriter
    return
}
if ($PSBoundParameters.ContainsKey('Configuration') -or $PSBoundParameters.ContainsKey('TaskWriter') -or $PSBoundParameters.ContainsKey('PreflightCheck')) { throw 'Injection requires TestMode.' }
$config=Read-IssueReviewConfig -ConfigPath $ConfigPath
if ((Get-TimeZone).Id -ne $TimeZoneId) { throw 'Machine time zone differs from requested zone.' }
Assert-WindowlessPython -PythonwPath $PythonwPath
$launcher=Join-Path $PSScriptRoot 'run_issue_review_hidden.py'
$task=New-IssueReviewTaskConfiguration -RepoRoot $config.repo_root -ConfigPath $ConfigPath -PythonwPath $PythonwPath -LauncherPath $launcher -CurrentUser ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -TaskName $TaskName -TimeZoneId $TimeZoneId -StartAt $StartAt -Interval $Interval
$info=New-Object Diagnostics.ProcessStartInfo
$info.FileName=(Get-Command powershell.exe -ErrorAction Stop).Source
$runner=Join-Path $PSScriptRoot 'run_issue_review.ps1'
$info.Arguments='-NoProfile -NonInteractive -File "{0}" -ConfigPath "{1}" -Preflight' -f $runner,$ConfigPath
$info.UseShellExecute=$false
$info.CreateNoWindow=$true
$task | ConvertTo-Json -Depth 4
if (-not $WhatIfPreference -and -not $Validated) { throw 'Independent validation required.' }
$check={
    param($t)
    $child=[Diagnostics.Process]::Start($info)
    try { $child.WaitForExit(); if ($child.ExitCode -ne 0) { throw 'Runner preflight failed.' } } finally { $child.Dispose() }
    Import-Module ScheduledTasks -ErrorAction Stop
    $existing=@(ScheduledTasks\Get-ScheduledTask -TaskPath $t.TaskPath -ErrorAction Stop | Where-Object { $_.TaskName -eq $t.TaskName })
    if ($existing.Count -gt 0) { throw 'Task already exists.' }
}
$writer={
        param($t)
        $action=ScheduledTasks\New-ScheduledTaskAction -Execute $t.Executable -Argument $t.Arguments -WorkingDirectory $t.WorkingDirectory
        $trigger=ScheduledTasks\New-ScheduledTaskTrigger -Once -At ([datetime]$t.StartAt) -RepetitionInterval ([Xml.XmlConvert]::ToTimeSpan($t.Interval))
        $principal=ScheduledTasks\New-ScheduledTaskPrincipal -UserId $t.User -LogonType $t.LogonType -RunLevel $t.RunLevel
        $settings=ScheduledTasks\New-ScheduledTaskSettingsSet -Hidden:$t.Hidden -MultipleInstances $t.MultipleInstances -ExecutionTimeLimit ([Xml.XmlConvert]::ToTimeSpan($t.ExecutionTimeLimit)) -AllowStartIfOnBatteries:$t.AllowStartIfOnBatteries -DontStopIfGoingOnBatteries:$t.DontStopIfGoingOnBatteries
        $null=ScheduledTasks\Register-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description $t.Description -ErrorAction Stop
}
Invoke-ReviewedRegistration -Task $task -Preflight $check -Writer $writer
