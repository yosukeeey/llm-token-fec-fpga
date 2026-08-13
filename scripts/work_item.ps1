[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("start", "verify")]
    [string]$Command = "verify",

    [int]$Issue,

    [string]$Slug,

    [string]$Base = "origin/main",

    [string]$WorktreeRoot
)

$ErrorActionPreference = "Stop"

function Invoke-Git {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments,

        [string]$WorkingDirectory = (Get-Location).Path
    )

    $output = & git -C $WorkingDirectory @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw ($output -join [Environment]::NewLine)
    }

    return @($output)
}

$repositoryRoot = ([string](@(Invoke-Git -Arguments @("rev-parse", "--show-toplevel"))[-1])).Trim()

if ($Command -eq "start") {
    if ($Issue -lt 1) {
        throw "Issue must be a positive integer."
    }
    if ($Slug -notmatch "^[a-z0-9]+(?:-[a-z0-9]+)*$") {
        throw "Slug must contain lowercase letters, digits, and single hyphens."
    }

    $branch = "issue/$Issue-$Slug"
    $existingBranch = Invoke-Git -Arguments @("branch", "--list", $branch) -WorkingDirectory $repositoryRoot
    if ($existingBranch.Count -ne 0) {
        throw "Branch already exists: $branch"
    }

    if ([string]::IsNullOrWhiteSpace($WorktreeRoot)) {
        $repositoryName = Split-Path -Leaf $repositoryRoot
        $WorktreeRoot = Join-Path (Split-Path -Parent $repositoryRoot) "$repositoryName-worktrees"
    }

    $target = [System.IO.Path]::GetFullPath((Join-Path $WorktreeRoot "issue-$Issue-$Slug"))
    if (Test-Path -LiteralPath $target) {
        throw "Worktree path already exists: $target"
    }

    Invoke-Git -Arguments @("worktree", "add", "-b", $branch, $target, $Base) -WorkingDirectory $repositoryRoot | Out-Null
    Write-Output $target
    return
}

$currentBranch = ([string](@(Invoke-Git -Arguments @("branch", "--show-current") -WorkingDirectory $repositoryRoot)[-1])).Trim()
if ($currentBranch -notmatch "^issue/(?<issue>[1-9][0-9]*)-[a-z0-9]+(?:-[a-z0-9]+)*$") {
    throw "Current branch must match issue/<number>-<slug>: $currentBranch"
}

$branchRecord = "branch refs/heads/$currentBranch"
$worktreeRecords = Invoke-Git -Arguments @("worktree", "list", "--porcelain") -WorkingDirectory $repositoryRoot
$worktreeCount = @($worktreeRecords | Where-Object { $_ -eq $branchRecord }).Count
if ($worktreeCount -ne 1) {
    throw "Branch must belong to exactly one worktree: $currentBranch"
}

Write-Output "issue=$($Matches.issue) branch=$currentBranch worktree=$repositoryRoot"
