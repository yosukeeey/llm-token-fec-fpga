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
$policyPath = Join-Path $PSScriptRoot "work_item_policy.ps1"

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

function Get-GitHubRepository {
    param([string]$WorkingDirectory)

    $remoteOutput = Invoke-Git -Arguments @(
        "remote",
        "get-url",
        "origin"
    ) -WorkingDirectory $WorkingDirectory
    $remote = ([string]@($remoteOutput)[-1]).Trim()
    if ($remote -notmatch "github\.com(?::|/)(?<repository>[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+?)(?:\.git)?/?$") {
        throw "origin must point to a GitHub repository."
    }
    return $Matches.repository
}

$repositoryRoot = ([string](@(Invoke-Git -Arguments @("rev-parse", "--show-toplevel"))[-1])).Trim()
$repository = Get-GitHubRepository $repositoryRoot

if ($Command -eq "start") {
    if ($Issue -lt 1) {
        throw "Issue must be a positive integer."
    }
    if ($Slug -notmatch "^[a-z0-9]+(?:-[a-z0-9]+)*$") {
        throw "Slug must contain lowercase letters, digits, and single hyphens."
    }

    $branch = "issue/$Issue-$Slug"
    & $policyPath available -Repository $repository -Issue $Issue | Out-Null

    $existingBranches = @(
        Invoke-Git -Arguments @(
            "branch",
            "--all",
            "--list",
            "issue/$Issue-*",
            "remotes/origin/issue/$Issue-*"
        ) -WorkingDirectory $repositoryRoot
    )
    if ($existingBranches.Count -ne 0) {
        throw "Issue already has a branch: $($existingBranches.Trim() -join ', ')"
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
$issueNumber = [int]$Matches.issue

$branchRecord = "branch refs/heads/$currentBranch"
$worktreeRecords = Invoke-Git -Arguments @("worktree", "list", "--porcelain") -WorkingDirectory $repositoryRoot
$worktreeCount = @($worktreeRecords | Where-Object { $_ -eq $branchRecord }).Count
if ($worktreeCount -ne 1) {
    throw "Branch must belong to exactly one worktree: $currentBranch"
}

& $policyPath active -Repository $repository -Branch $currentBranch | Out-Null

Write-Output "issue=$issueNumber branch=$currentBranch worktree=$repositoryRoot"
