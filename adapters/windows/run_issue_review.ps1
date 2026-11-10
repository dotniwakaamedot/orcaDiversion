[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ConfigPath,
    [switch]$Preflight
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'issue_review_config.ps1')
try {
    $config = Read-IssueReviewConfig -ConfigPath $ConfigPath
} catch {
    [Console]::Error.WriteLine('Invalid issue review configuration.')
    exit 1
}
$RepoRoot = $config.repo_root
$CodexPath = $config.codex_path
$StateRoot = $config.state_root
$promptPath = $config.prompt_path
$utf8 = New-Object System.Text.UTF8Encoding($false)
[Console]::InputEncoding = $utf8
[Console]::OutputEncoding = $utf8
$OutputEncoding = $utf8
$lock = $null
$runDirectory = $null
$exitCode = 1
$reason = 'initialization_failed'
$stage = 'initializing'
$baseBranch = $config.base_branch
$baseCommit = $null
$startedAt = [DateTimeOffset]::Now.ToString('o')

function Write-RunStatus($status) {
    $path = Join-Path $runDirectory 'status.json'
    $temporary = Join-Path $runDirectory ('status-' + [Guid]::NewGuid().ToString('N') + '.tmp')
    $backup = $temporary + '.bak'
    try {
        [IO.File]::WriteAllText($temporary, ($status | ConvertTo-Json), $utf8)
        if ([IO.File]::Exists($path)) { [IO.File]::Replace($temporary, $path, $backup) }
        else { [IO.File]::Move($temporary, $path) }
    } finally {
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
        if ([IO.File]::Exists($backup)) { [IO.File]::Delete($backup) }
    }
}

try {
    if ([string]::IsNullOrWhiteSpace($StateRoot)) { $StateRoot = Join-Path $RepoRoot '.mcf\issue-review' }
    $StateRoot = [IO.Path]::GetFullPath($StateRoot)
    $runId = (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
    $runDirectory = Join-Path $StateRoot $runId
    $null = New-Item -ItemType Directory -Path $runDirectory -Force
    # Publish an initial marker before validation: abrupt termination leaves an identifiable unfinished run.
    $initialStatus = [ordered]@{ schema_version = 2; started_at = $startedAt; finished_at = $null; exit_code = $null; outcome = 'running'; stage = $stage; base_branch = $baseBranch; base_commit_at_start = $null; final_report = 'final-message.md' }
    Write-RunStatus $initialStatus
    $stage = 'repository'
    $reason = 'preflight_failed'
    $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
    if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot '.git'))) { throw 'Git checkout required.' }
    $stage = 'base_commit'
    $baseCommit = & git -C $RepoRoot rev-parse --verify ('refs/heads/' + $baseBranch + '^{commit}')
    if ($LASTEXITCODE -ne 0) { throw 'Local base branch required.' }
    $baseCommit = ([string]$baseCommit).Trim()
    $stage = 'codex_path'
    $CodexPath = (Resolve-Path -LiteralPath $CodexPath).Path
    if ([IO.Path]::GetExtension($CodexPath) -notin @('.ps1', '.exe')) { throw 'Unsupported CLI entry point.' }
    $stage = 'dependencies'
    foreach ($dependency in @('git', 'gh')) { $null = Get-Command $dependency -ErrorAction Stop }
    $stage = 'instructions'
    $prompt = [IO.File]::ReadAllText($promptPath, $utf8)
    if ([string]::IsNullOrWhiteSpace($prompt)) { throw 'Issue review prompt is empty.' }
    foreach ($instruction in @('AGENTS.md', 'docs\agent-workflow.md')) {
        if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot $instruction) -PathType Leaf)) { throw 'Required project instructions missing.' }
    }
    $stage = 'storage'
    $probePath = Join-Path $StateRoot ([IO.Path]::GetRandomFileName())
    try { [IO.File]::WriteAllText($probePath, '', $utf8) }
    finally { if ([IO.File]::Exists($probePath)) { [IO.File]::Delete($probePath) } }
    $cliArguments = @('exec', '-C', $RepoRoot, '--color', 'never', '--output-last-message', '<run-directory>\final-message.md', '-')
    if ($Preflight) {
        [pscustomobject]@{ Mode = 'Preflight'; RepoRoot = $RepoRoot; CodexPath = $CodexPath; StateRoot = $StateRoot; PromptPath = $promptPath; BaseBranch = $baseBranch; BaseCommitAtStart = $baseCommit; Arguments = $cliArguments; ModelInvoked = $false } | ConvertTo-Json -Depth 4
        $exitCode = 0
        $reason = 'preflight_completed'
    } else {
    $stage = 'lock'
    $reason = 'lock_unavailable'
    try {
        $lock = [IO.File]::Open((Join-Path $StateRoot 'running.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    } catch [IO.IOException] {
        [Console]::Error.WriteLine('Issue review is already running, or its lock cannot be opened.')
        $exitCode = 75
        exit 75
    }
    $finalPath = Join-Path $runDirectory 'final-message.md'
    $prompt += "`n`nExecution baseline: local refs/heads/$baseBranch at start is $baseCommit. Follow the approved branch/worktree policy in AGENTS.md. Never implement directly in the coordinator checkout.`n"
    $prompt += "`n`nWorktree cleanup monitoring directory: $runDirectory. Follow docs/task-cleanup-check.md and write worktree-cleanup.md there, including no-target runs. Inspect prior run status and cleanup records; report missing or interrupted runs as unverified, not success.`n"
    $cliArguments[6] = $finalPath
    $stage = 'cli'
    $reason = 'cli_failed'
    $runningStatus = [ordered]@{ schema_version = 2; started_at = $startedAt; finished_at = $null; exit_code = $null; outcome = 'running'; stage = $stage; base_branch = $baseBranch; base_commit_at_start = $baseCommit; final_report = 'final-message.md' }
    Write-RunStatus $runningStatus
    # Use OS pipes even for .ps1 entry points: Console.Error writes must not bypass redirection.
    $processInfo = New-Object Diagnostics.ProcessStartInfo
    $processInfo.UseShellExecute = $false
    $processInfo.CreateNoWindow = $true
    $processInfo.RedirectStandardInput = $true
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true
    $processInfo.WorkingDirectory = $RepoRoot
    if ([IO.Path]::GetExtension($CodexPath) -eq '.ps1') {
        $processInfo.FileName = (Get-Command powershell.exe -ErrorAction Stop).Source
        # -File cannot pass a lone '-' reliably in Windows PowerShell. Encode only literal arguments.
        $literalArguments = (@(@($CodexPath) + $cliArguments) | ForEach-Object { "'" + $_.Replace("'", "''") + "'" }) -join ' '
        $invokeCommand = '[Console]::InputEncoding = New-Object Text.UTF8Encoding($false); & ' + $literalArguments + '; exit $LASTEXITCODE'
        $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($invokeCommand))
        $processArguments = @('-NoProfile', '-NonInteractive', '-EncodedCommand', $encodedCommand)
    } else {
        $processInfo.FileName = $CodexPath
        $processArguments = $cliArguments
    }
    # Windows paths cannot contain quotes. Quoted trailing backslashes must be doubled.
    $processInfo.Arguments = (@($processArguments | ForEach-Object {
        if ($_ -match '"') { throw 'CLI arguments cannot contain quotation marks.' }
        '"' + ([regex]::Replace([string]$_, '(\\+)$', '$1$1')) + '"'
    }) -join ' ')
    $process = $null
    try {
        $process = [Diagnostics.Process]::Start($processInfo)
        $drainOutput = $process.StandardOutput.BaseStream.CopyToAsync([IO.Stream]::Null)
        $drainError = $process.StandardError.BaseStream.CopyToAsync([IO.Stream]::Null)
        $inputWriter = New-Object IO.StreamWriter($process.StandardInput.BaseStream, $utf8)
        try { $inputWriter.WriteLine($prompt) } finally { $inputWriter.Dispose() }
        $process.WaitForExit()
        $null = $drainOutput.GetAwaiter().GetResult()
        $null = $drainError.GetAwaiter().GetResult()
        $exitCode = $process.ExitCode
    } finally { if ($null -ne $process) { try { $process.WaitForExit() } finally { $process.Dispose() } } }
    if ($exitCode -eq 0) {
        if (-not [IO.File]::Exists($finalPath) -or (Get-Item -LiteralPath $finalPath).Length -eq 0) {
            $exitCode = 1
            $reason = 'final_report_missing'
        } else { $reason = 'completed' }
    }
    }
} catch {
    # Exception payloads and native output can contain secrets. Only fixed failure codes are retained.
    $exitCode = 1
    [Console]::Error.WriteLine('Issue review failed. Check the run status and perform a secret-safe manual preflight.')
} finally {
    if ($null -ne $runDirectory) {
        try {
            $status = [ordered]@{ schema_version = 2; started_at = $startedAt; finished_at = [DateTimeOffset]::Now.ToString('o'); exit_code = $exitCode; outcome = $reason; stage = $stage; base_branch = $baseBranch; base_commit_at_start = $baseCommit; final_report = 'final-message.md' }
            Write-RunStatus $status
        } catch { $exitCode = 1; [Console]::Error.WriteLine('Could not write issue review status.') }
    }
    if ($null -ne $runDirectory -and $null -ne $lock -and -not $Preflight) {
        try {
            $cleanupPath = Join-Path $runDirectory 'worktree-cleanup.md'
            $present = [IO.File]::Exists($cleanupPath) -and ((Get-Item -LiteralPath $cleanupPath).Length -gt 0)
            $previousUnfinished = @()
            $previousUnverified = @()
            foreach ($directory in @(Get-ChildItem -LiteralPath $StateRoot -Directory)) {
                if ($directory.FullName -eq $runDirectory) { continue }
                $priorPath = Join-Path $directory.FullName 'status.json'
                if (-not [IO.File]::Exists($priorPath)) { continue }
                try {
                    $prior = Get-Content -LiteralPath $priorPath -Raw -Encoding UTF8 | ConvertFrom-Json
                    if ($prior.outcome -eq 'running') { $previousUnfinished += $directory.Name }
                    elseif ($prior.stage -eq 'cli' -and -not [IO.File]::Exists((Join-Path $directory.FullName 'worktree-cleanup.md'))) { $previousUnverified += $directory.Name }
                } catch { $previousUnverified += $directory.Name }
            }
            $monitor = [ordered]@{ schema_version = 1; checked_at = [DateTimeOffset]::Now.ToString('o'); report = 'worktree-cleanup.md'; report_state = $(if ($present) { 'present_unverified' } else { 'missing' }); previous_unfinished = @($previousUnfinished); previous_missing_or_unreadable = @($previousUnverified) }
            [IO.File]::WriteAllText((Join-Path $runDirectory 'cleanup-monitor.json'), ($monitor | ConvertTo-Json -Depth 4), $utf8)
        } catch { [Console]::Error.WriteLine('Could not write cleanup monitor status.') }
    }
    if ($null -ne $lock) { $lock.Dispose() }
}
exit $exitCode
