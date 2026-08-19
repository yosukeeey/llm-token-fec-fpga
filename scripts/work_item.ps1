[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("start", "verify", "cleanup")]
    [string]$Command = "verify",

    [int]$Issue,

    [string]$Slug,

    [string]$Base = "origin/main",

    [string]$WorktreeRoot,

    [switch]$Execute,

    [switch]$DeleteRemote
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

function Test-GitRef {
    param(
        [string]$Reference,
        [string]$WorkingDirectory
    )

    & git -C $WorkingDirectory rev-parse --verify --quiet $Reference 2>&1 | Out-Null
    return $LASTEXITCODE -eq 0
}

function Get-IssueWorktrees {
    param([string]$WorkingDirectory)

    $records = @(
        Invoke-Git -Arguments @("worktree", "list", "--porcelain") -WorkingDirectory $WorkingDirectory
    )
    $worktrees = [System.Collections.Generic.List[object]]::new()
    $path = $null
    foreach ($record in $records) {
        $line = [string]$record
        if ($line -like "worktree *") {
            $path = $line.Substring("worktree ".Length)
            continue
        }
        if ($line -like "branch refs/heads/*" -and $null -ne $path) {
            $branch = $line.Substring("branch refs/heads/".Length)
            if ($branch -cmatch "^issue/[1-9][0-9]*-[a-z0-9]+(?:-[a-z0-9]+)*$") {
                $worktrees.Add([pscustomobject]@{ Path = $path; Branch = $branch })
            }
            $path = $null
        }
    }
    return $worktrees.ToArray()
}

$repositoryRoot = ([string](@(Invoke-Git -Arguments @("rev-parse", "--show-toplevel"))[-1])).Trim()
$repository = Get-GitHubRepository $repositoryRoot

if ($Command -eq "cleanup") {
    # Refresh first: this updates the merge base and prunes remote-tracking
    # references for branches the remote already deleted.
    try {
        Invoke-Git -Arguments @("fetch", "--prune", "origin") -WorkingDirectory $repositoryRoot | Out-Null
    }
    catch {
        Write-Output "cleanup: fetch failed, using the references already present"
    }

    $baseReference = if (Test-GitRef "refs/remotes/origin/main" $repositoryRoot) {
        "refs/remotes/origin/main"
    }
    else {
        "refs/heads/main"
    }
    if (-not (Test-GitRef $baseReference $repositoryRoot)) {
        throw "Base reference is missing: $baseReference"
    }

    $failures = [System.Collections.Generic.List[string]]::new()
    $removed = 0
    foreach ($worktree in Get-IssueWorktrees $repositoryRoot) {
        & git -C $repositoryRoot merge-base --is-ancestor $worktree.Branch $baseReference 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Output "keep $($worktree.Branch): not merged into $baseReference"
            continue
        }
        $changes = @(
            Invoke-Git -Arguments @("status", "--porcelain") -WorkingDirectory $worktree.Path |
                Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
        )
        if ($changes.Count -ne 0) {
            Write-Output "keep $($worktree.Branch): $($changes.Count) uncommitted or untracked path(s)"
            continue
        }
        if (-not $Execute) {
            Write-Output "remove $($worktree.Branch): merged and clean"
            continue
        }

        try {
            Invoke-Git -Arguments @("worktree", "remove", $worktree.Path) -WorkingDirectory $repositoryRoot | Out-Null
            Invoke-Git -Arguments @("branch", "-d", $worktree.Branch) -WorkingDirectory $repositoryRoot | Out-Null
            $removed++
            Write-Output "removed $($worktree.Branch)"

            # The remote branch is shared with other checkouts, so deleting it
            # is opt in and is judged on the remote tip, not the local one.
            $remoteReference = "refs/remotes/origin/$($worktree.Branch)"
            if (-not (Test-GitRef $remoteReference $repositoryRoot)) {
                Write-Output "remote absent $($worktree.Branch)"
            }
            elseif (-not $DeleteRemote) {
                Write-Output "remote kept $($worktree.Branch): pass -DeleteRemote to delete it"
            }
            else {
                & git -C $repositoryRoot merge-base --is-ancestor $remoteReference $baseReference 2>&1 | Out-Null
                if ($LASTEXITCODE -ne 0) {
                    Write-Output "remote kept $($worktree.Branch): remote tip is not merged into $baseReference"
                }
                else {
                    Invoke-Git -Arguments @("push", "origin", "--delete", $worktree.Branch) -WorkingDirectory $repositoryRoot | Out-Null
                    Write-Output "remote deleted $($worktree.Branch)"
                }
            }
        }
        catch {
            $failures.Add("$($worktree.Branch): $($_.Exception.Message)")
            Write-Output "failed $($worktree.Branch)"
        }
    }

    Invoke-Git -Arguments @("worktree", "prune") -WorkingDirectory $repositoryRoot | Out-Null
    if ($failures.Count -ne 0) {
        throw ($failures -join [Environment]::NewLine)
    }
    if (-not $Execute) {
        Write-Output "cleanup: preview only, pass -Execute to remove"
    }
    else {
        Write-Output "cleanup: removed $removed work item(s)"
    }
    return
}

if ($Command -eq "start") {
    if ($Issue -lt 1) {
        throw "Issue must be a positive integer."
    }
    if ($Slug -cnotmatch "^[a-z0-9]+(?:-[a-z0-9]+)*$") {
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
if ($currentBranch -cnotmatch "^issue/(?<issue>[1-9][0-9]*)-[a-z0-9]+(?:-[a-z0-9]+)*$") {
    throw "Current branch must match issue/<number>-<slug>: $currentBranch"
}
$issueNumber = [int]$Matches.issue

$branchRecord = "branch refs/heads/$currentBranch"
$worktreeRecords = Invoke-Git -Arguments @("worktree", "list", "--porcelain") -WorkingDirectory $repositoryRoot
$primaryWorktree = ([string]@(
    $worktreeRecords | Where-Object { $_ -like "worktree *" }
)[0]).Substring("worktree ".Length)
if ([System.IO.Path]::GetFullPath($repositoryRoot) -eq [System.IO.Path]::GetFullPath($primaryWorktree)) {
    throw "Issue branch must use a linked worktree, not the primary checkout."
}
$worktreeCount = @($worktreeRecords | Where-Object { $_ -eq $branchRecord }).Count
if ($worktreeCount -ne 1) {
    throw "Branch must belong to exactly one worktree: $currentBranch"
}

& $policyPath active -Repository $repository -Branch $currentBranch | Out-Null

Write-Output "issue=$issueNumber branch=$currentBranch worktree=$repositoryRoot"
