$ErrorActionPreference='Stop'
$stage=Split-Path -Parent $PSScriptRoot
. (Join-Path $stage 'adapters/windows/issue_review_config.ps1')
. (Join-Path $stage 'adapters/windows/issue_review_task_configuration.ps1')
$scratch=Join-Path $env:TEMP ("issue workflow test '"+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $scratch
Write-Output ("scratch="+$scratch)
try {
    $repo=Join-Path $scratch 'repo'
    $null=New-Item -ItemType Directory -Path $repo
    & git init -q -b main $repo
    if ($LASTEXITCODE -ne 0) { throw 'git init failed.' }
    & git -C $repo -c user.name=Test -c user.email=test@example.invalid commit -q --allow-empty -m initial
    if ($LASTEXITCODE -ne 0) { throw 'git commit failed.' }
    & git -C $repo branch alternative
    if ($LASTEXITCODE -ne 0) { throw 'git branch failed.' }
    $null=New-Item -ItemType Directory -Path (Join-Path $repo 'docs')
    'test instructions' | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $repo 'AGENTS.md')
    'test workflow' | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $repo 'docs/agent-workflow.md')
    $codex=(Get-Command powershell.exe).Source
    $prompt=Join-Path $stage 'adapters/windows/issue-review-prompt.md'
    $configPath=Join-Path $scratch 'settings.json'
    $valid=@{repo_root=$repo;state_root=(Join-Path $scratch 'state');codex_path=$codex;prompt_path=$prompt;base_branch='main'}
    $valid | ConvertTo-Json | Set-Content -Encoding UTF8 -LiteralPath $configPath
    $v=Read-IssueReviewConfig -ConfigPath $configPath
    if ($v.base_branch -ne 'main') { throw 'Valid config not preserved.' }
    foreach ($kind in @('missing','unknown','invalid_branch','relative','quote','newline')) {
        $bad=$valid.Clone()
        switch ($kind) {
            'missing' { $bad.Remove('base_branch') }
            'unknown' { $bad['extra']='x' }
            'invalid_branch' { $bad['base_branch']='../bad' }
            'relative' { $bad['state_root']='relative' }
            'quote' { $bad['state_root']=$scratch+'"bad' }
            'newline' { $bad['state_root']=$scratch+"`n"+'bad' }
        }
        $bad | ConvertTo-Json | Set-Content -Encoding UTF8 -LiteralPath $configPath
        $rejected=$false
        try { $null=Read-IssueReviewConfig -ConfigPath $configPath } catch { $rejected=$true }
        if (-not $rejected) { throw ("Invalid config accepted: "+$kind) }
    }
    $valid | ConvertTo-Json | Set-Content -Encoding UTF8 -LiteralPath $configPath
    $launcher=Join-Path $stage 'adapters/windows/run_issue_review_hidden.py'
    $pythonw=$env:ISSUE_TEST_PYTHONW
    if ([string]::IsNullOrWhiteSpace($pythonw)) { throw 'ISSUE_TEST_PYTHONW must identify a verified windowless interpreter.' }
    Assert-WindowlessPython -PythonwPath $pythonw
    foreach ($invalidPython in @($codex, (Get-Command python.exe).Source)) {
        $rejected=$false
        try { Assert-WindowlessPython -PythonwPath $invalidPython } catch { $rejected=$true }
        if (-not $rejected) { throw 'Non-pythonw executable accepted.' }
    }
    $impostor=Join-Path $scratch 'pythonw.exe'
    Copy-Item -LiteralPath $codex -Destination $impostor
    $rejected=$false
    try { Assert-WindowlessPython -PythonwPath $impostor } catch { $rejected=$true }
    if (-not $rejected) { throw 'A renamed non-Python executable was accepted.' }
    $t=New-IssueReviewTaskConfiguration -RepoRoot $repo -ConfigPath $configPath -PythonwPath $pythonw -LauncherPath $launcher -CurrentUser 'test-user' -TaskName 'test-task' -TimeZoneId ([TimeZoneInfo]::Local.Id) -StartAt (Get-Date).AddHours(1) -Interval 'PT1H'
    if (-not $t.Hidden -or $t.Arguments -notlike '*--config*') { throw 'Task settings invalid.' }
    $script:called=0
    $null=Invoke-IssueReviewTaskWriter -Configuration $t -Writer {param($x) $script:called++}
    if ($script:called -ne 1) { throw 'Writer not invoked exactly once.' }
    $rejected=$false
    try { $null=Invoke-IssueReviewTaskWriter -Configuration $t } catch { $rejected=$true }
    if (-not $rejected) { throw 'Missing writer accepted.' }
    $runner=Join-Path $stage 'adapters/windows/run_issue_review.ps1'
    $output=& powershell.exe -NoProfile -NonInteractive -File $runner -ConfigPath $configPath -Preflight
    if ($LASTEXITCODE -ne 0) { throw 'Preflight failed.' }
    $observed=($output | Out-String | ConvertFrom-Json)
    if ($observed.ModelInvoked -ne $false -or $observed.BaseBranch -ne 'main') { throw 'Preflight unexpectedly invoked model or changed base.' }
    $valid.base_branch='alternative'
    $valid.state_root=Join-Path $scratch 'other-state'
    $valid | ConvertTo-Json | Set-Content -Encoding UTF8 -LiteralPath $configPath
    $output=& powershell.exe -NoProfile -NonInteractive -File $runner -ConfigPath $configPath -Preflight
    if ($LASTEXITCODE -ne 0) { throw 'Second configuration preflight failed.' }
    $observed=($output | Out-String | ConvertFrom-Json)
    if ($observed.BaseBranch -ne $valid.base_branch -or $observed.StateRoot -ne $valid.state_root) { throw 'Second configuration ignored.' }
    $lockPath=Join-Path $valid.state_root 'running.lock'
    $held=[IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try {
        $ErrorActionPreference='Continue'
        & powershell.exe -NoProfile -NonInteractive -File $runner -ConfigPath $configPath 2>$null
        $lockExit=$LASTEXITCODE
    } finally { $ErrorActionPreference='Stop'; $held.Dispose() }
    if ($lockExit -ne 75) { throw ('Expected locked runner status 75, received '+$lockExit) }
    $stub=Join-Path $scratch 'codex-stub.ps1'
    'exit 17' | Set-Content -Encoding UTF8 -LiteralPath $stub
    $valid.codex_path=$stub
    $valid.state_root=Join-Path $scratch 'failure-state'
    $valid | ConvertTo-Json | Set-Content -Encoding UTF8 -LiteralPath $configPath
    & powershell.exe -NoProfile -NonInteractive -File $runner -ConfigPath $configPath
    if ($LASTEXITCODE -ne 17) { throw ('Expected stub status 17, received '+$LASTEXITCODE) }
    $runs=@(Get-ChildItem -LiteralPath $valid.state_root -Directory)
    if ($runs.Count -ne 1) { throw 'Expected exactly one failure run.' }
    $status=Get-Content -Raw -Encoding UTF8 (Join-Path $runs[0].FullName 'status.json') | ConvertFrom-Json
    $monitor=Get-Content -Raw -Encoding UTF8 (Join-Path $runs[0].FullName 'cleanup-monitor.json') | ConvertFrom-Json
    if ($status.outcome -ne 'cli_failed' -or $status.exit_code -ne 17 -or $monitor.report_state -ne 'missing') { throw 'Failure or cleanup status not preserved.' }
    $valid.state_root=Join-Path $scratch 'success-state'
    @'
$idx=[array]::IndexOf($args,'--output-last-message')
if ($args[0] -ne 'exec' -or $idx -lt 0 -or $args[$idx+2] -ne '-') { exit 33 }
[IO.File]::WriteAllText($args[$idx+1], 'stub report')
exit 0
'@ | Set-Content -Encoding UTF8 -LiteralPath $stub
    $valid | ConvertTo-Json | Set-Content -Encoding UTF8 -LiteralPath $configPath
    & powershell.exe -NoProfile -NonInteractive -File $runner -ConfigPath $configPath
    if ($LASTEXITCODE -ne 0) { throw 'Success stub runner failed.' }
    $runs=@(Get-ChildItem -LiteralPath $valid.state_root -Directory)
    $status=Get-Content -Raw -Encoding UTF8 (Join-Path $runs[0].FullName 'status.json') | ConvertFrom-Json
    if ($status.outcome -ne 'completed' -or -not (Test-Path -LiteralPath (Join-Path $runs[0].FullName 'final-message.md'))) { throw 'Success report missing.' }
    $fakeModule=Join-Path $scratch 'modules/ScheduledTasks'
    $null=New-Item -ItemType Directory -Force -Path $fakeModule
    $marker=Join-Path $scratch 'module-loaded.txt'
    ("[IO.File]::WriteAllText('"+$marker.Replace("'","''")+"','loaded')") | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $fakeModule 'ScheduledTasks.psm1')
    $oldModulePath=$env:PSModulePath
    $valid.base_branch='does-not-exist'
    $valid.state_root=Join-Path $scratch 'registration-state'
    $valid | ConvertTo-Json | Set-Content -Encoding UTF8 -LiteralPath $configPath
    $register=Join-Path $stage 'adapters/windows/register_issue_review_task.ps1'
    $injected=@{
        ConfigPath=$configPath; PythonwPath=$pythonw; TaskName='test-task'
        TimeZoneId=[TimeZoneInfo]::Local.Id; StartAt=(Get-Date).AddHours(1)
        Interval='PT1H'; TestMode=$true; Configuration=$t
    }
    $capture=[pscustomobject]@{ Preflight=0; Writer=0; Received=$null }
    $preflight={param($value) $capture.Preflight++; if ($value.Arguments -ne $t.Arguments) { throw 'Unexpected task settings.' }}.GetNewClosure()
    $writer={param($value) $capture.Writer++; $capture.Received=$value}.GetNewClosure()
    & $register @injected -PreflightCheck $preflight -TaskWriter $writer -WhatIf
    if ($capture.Preflight -ne 1 -or $capture.Writer -ne 0) { throw 'WhatIf wrote or skipped preflight.' }
    & $register @injected -PreflightCheck $preflight -TaskWriter $writer -Confirm:$false
    if ($capture.Preflight -ne 2 -or $capture.Writer -ne 1 -or $capture.Received.Arguments -ne $t.Arguments -or $capture.Received.Executable -ne $pythonw) { throw 'Success did not pass task exactly once.' }
    $rejected=$false
    try { & $register @injected -PreflightCheck { throw 'preflight failed' } -TaskWriter $writer -Confirm:$false } catch { $rejected=$true }
    if (-not $rejected -or $capture.Writer -ne 1) { throw 'Preflight failure reached writer.' }
    $rejected=$false
    try { & $register @injected -PreflightCheck $preflight -TaskWriter { throw 'writer failed' } -Confirm:$false } catch { $rejected=$true }
    if (-not $rejected) { throw 'Writer failure was swallowed.' }
    try {
        $env:PSModulePath=(Join-Path $scratch 'modules')+[IO.Path]::PathSeparator+$oldModulePath
        $ErrorActionPreference='Continue'
        & powershell.exe -NoProfile -NonInteractive -File $register -ConfigPath $configPath -PythonwPath $pythonw -TaskName test-task -TimeZoneId ([TimeZoneInfo]::Local.Id) -StartAt '2030-01-01 12:00:00' -Interval PT1H -Validated 2>$null
        $registrationExit=$LASTEXITCODE
    } finally { $ErrorActionPreference='Stop'; $env:PSModulePath=$oldModulePath }
    if ($registrationExit -eq 0 -or (Test-Path -LiteralPath $marker)) { throw 'Preflight failure did not stop registration before Scheduler access.' }
    Write-Output 'config, pythonw, writer, two preflights, lock, failure monitor, success and registration preflight failure passed'
} finally {
    if ([IO.Path]::GetFullPath($scratch).StartsWith([IO.Path]::GetFullPath($env:TEMP)+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $scratch -Recurse -Force
    }
    Write-Output ("scratch_exists="+(Test-Path -LiteralPath $scratch))
}
