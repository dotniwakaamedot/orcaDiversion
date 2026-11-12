Set-StrictMode -Version Latest
function Read-IssueReviewConfig {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$ConfigPath)
    if (-not [IO.Path]::IsPathRooted($ConfigPath)) { throw 'Configuration path must be absolute.' }
    $config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    if ($null -eq $config -or $config -is [array] -or $config -isnot [pscustomobject]) { throw 'Expected JSON object.' }
    $keys = @('repo_root', 'state_root', 'codex_path', 'prompt_path', 'base_branch')
    $actual = @($config.PSObject.Properties.Name)
    if ($actual.Count -ne $keys.Count -or @($actual | Where-Object { $_ -cnotin $keys }).Count -ne 0) { throw 'Unknown or missing configuration keys.' }
    foreach ($key in $keys) {
        $value = $config.$key
        if ($value -isnot [string] -or [string]::IsNullOrWhiteSpace($value) -or $value -match '[\x00-\x1f"]') { throw 'Invalid configuration value.' }
        if ($key -ne 'base_branch' -and -not [IO.Path]::IsPathRooted($value)) { throw 'Absolute paths required.' }
    }
    if ($config.base_branch.StartsWith('-')) { throw 'Invalid base branch.' }
    & git check-ref-format --branch $config.base_branch *> $null
    if ($LASTEXITCODE -ne 0) { throw 'Invalid base branch.' }
    if (-not (Test-Path -LiteralPath $config.repo_root -PathType Container)) { throw 'Repository does not exist.' }
    if (-not (Test-Path -LiteralPath $config.codex_path -PathType Leaf)) { throw 'Codex entry point does not exist.' }
    if ([IO.Path]::GetExtension($config.codex_path) -notin @('.ps1', '.exe')) { throw 'Unsupported Codex entry point.' }
    if (-not (Test-Path -LiteralPath $config.prompt_path -PathType Leaf)) { throw 'Prompt does not exist.' }
    return $config
}
