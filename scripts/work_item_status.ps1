[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory)]
    [ValidateSet("pull-request", "issue", "all")]
    [string]$Command,

    [Parameter(Mandatory)]
    [string]$Repository,

    [int]$PullRequest,

    [int]$Issue,

    [Parameter(Mandatory)]
    [string]$TargetUrl
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$policyPath = Join-Path $PSScriptRoot "work_item_policy.ps1"

function Invoke-GitHubText {
    param([string[]]$Arguments)

    $output = @(& gh @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw ($output -join [Environment]::NewLine)
    }
    return ($output -join [Environment]::NewLine)
}

function Get-GitHubJson {
    param([string]$Path)

    return (Invoke-GitHubText @("api", $Path) | ConvertFrom-Json)
}

function Get-GitHubPagedItems {
    param([string]$Path)

    $pages = Invoke-GitHubText @("api", "--paginate", "--slurp", $Path) |
        ConvertFrom-Json
    $items = [System.Collections.Generic.List[object]]::new()
    foreach ($page in @($pages)) {
        foreach ($item in @($page)) {
            $items.Add($item)
        }
    }
    return $items.ToArray()
}

function Set-WorkItemStatus {
    param(
        [string]$Commit,
        [ValidateSet("pending", "success", "failure")]
        [string]$State,
        [string]$Description
    )

    $arguments = @(
        "api",
        "--method",
        "POST",
        "repos/$Repository/statuses/$Commit",
        "-f",
        "state=$State",
        "-f",
        "context=work-item-policy",
        "-f",
        "description=$Description",
        "-f",
        "target_url=$TargetUrl"
    )
    $lastFailure = $null
    foreach ($attempt in 1..2) {
        try {
            Invoke-GitHubText $arguments | Out-Null
            return
        }
        catch {
            $lastFailure = $_.Exception.Message
        }
    }
    throw $lastFailure
}

function Get-WorkItemPullRequestRecord {
    param([int]$Number)

    $pullRequestRecord = Get-GitHubJson "repos/$Repository/pulls/$Number"
    if ($pullRequestRecord.state -ne "open") {
        throw "PR #$Number must be open."
    }
    if ($null -eq $pullRequestRecord.head.repo -or
        $pullRequestRecord.head.repo.full_name -ne $Repository) {
        throw "PR #$Number branch must belong to this repository."
    }
    $commit = [string]$pullRequestRecord.head.sha
    if ($commit -notmatch "^[0-9a-fA-F]{40}$") {
        throw "PR #$Number has no valid head commit."
    }
    return $pullRequestRecord
}

function Get-AffectedPullRequests {
    param([int]$IssueNumber = 0)

    if ($IssueNumber -gt 0) {
        $branchExpression = "^issue/$IssueNumber-[a-z0-9]+(?:-[a-z0-9]+)*$"
        $closingExpression = "(?im)(?<![A-Za-z])Closes\s+#$IssueNumber\b"
    }
    else {
        $branchExpression = "^issue/"
        $closingExpression = "(?im)(?<![A-Za-z])Closes\s+#[1-9][0-9]*\b"
    }
    return @(
        Get-GitHubPagedItems "repos/$Repository/pulls?state=open&per_page=100" |
            Where-Object {
                $null -ne $_.head.repo -and
                $_.head.repo.full_name -eq $Repository -and (
                    $_.head.ref -match $branchExpression -or
                    [regex]::IsMatch([string]$_.body, $closingExpression)
                )
            } |
            Sort-Object number -Unique
    )
}

if ($Repository -notmatch "^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$") {
    throw "Repository must use owner/name."
}
if ($TargetUrl -notmatch "^https://[^\s]+$") {
    throw "TargetUrl must use HTTPS."
}

if ($Command -eq "pull-request") {
    if ($PullRequest -lt 1) {
        throw "PullRequest must be a positive integer."
    }
    if ($Issue -ne 0) {
        throw "Issue is not valid with pull-request."
    }
}
elseif ($Command -eq "issue" -and $Issue -lt 1) {
    throw "Issue must be a positive integer."
}
if ($Command -eq "issue" -and $PullRequest -ne 0) {
    throw "PullRequest is not valid with issue."
}
if ($Command -eq "all" -and ($Issue -ne 0 -or $PullRequest -ne 0)) {
    throw "Issue and PullRequest are not valid with all."
}
$pullRequestNumbers = @(
    if ($Command -eq "pull-request") {
        $PullRequest
    }
    elseif ($Command -eq "issue") {
        Get-AffectedPullRequests $Issue | ForEach-Object { [int]$_.number }
    }
    else {
        Get-AffectedPullRequests | ForEach-Object { [int]$_.number }
    }
)
$reports = [System.Collections.Generic.List[object]]::new()
$failures = [System.Collections.Generic.List[string]]::new()
foreach ($pullRequestNumber in $pullRequestNumbers) {
    try {
        $pullRequestRecord = Get-WorkItemPullRequestRecord $pullRequestNumber
        $pendingFailure = $null
        try {
            Set-WorkItemStatus ([string]$pullRequestRecord.head.sha) "pending" "Work item policy is running"
        }
        catch {
            $pendingFailure = $_.Exception.Message
        }
        $reports.Add([pscustomobject]@{
            Number = $pullRequestNumber
            Commit = [string]$pullRequestRecord.head.sha
            PendingFailure = $pendingFailure
        })
    }
    catch {
        $failures.Add($_.Exception.Message)
    }
}

foreach ($report in $reports) {
    $reportFailures = [System.Collections.Generic.List[string]]::new()
    if ($null -ne $report.PendingFailure) {
        $reportFailures.Add("pending status failed: $($report.PendingFailure)")
    }
    try {
        & $policyPath pull-request -Repository $Repository -PullRequest $report.Number |
            Out-Null
        $currentRecord = Get-WorkItemPullRequestRecord $report.Number
        if ([string]$currentRecord.head.sha -ne $report.Commit) {
            throw "PR head changed during validation."
        }
    }
    catch {
        $reportFailures.Add($_.Exception.Message)
    }

    $state = if ($reportFailures.Count -eq 0) { "success" } else { "failure" }
    $description = if ($state -eq "success") {
        "Work item policy passed"
    }
    else {
        "Work item policy failed"
    }
    try {
        Set-WorkItemStatus $report.Commit $state $description
    }
    catch {
        $reportFailures.Add("final status failed: $($_.Exception.Message)")
    }
    if ($reportFailures.Count -ne 0) {
        $failures.Add("PR #$($report.Number) failed: $($reportFailures -join '; ')")
    }
}
if ($failures.Count -ne 0) {
    throw ($failures -join [Environment]::NewLine)
}
if ($Command -eq "pull-request") {
    Write-Output "work-item status: PR #$PullRequest reported"
}
elseif ($Command -eq "issue") {
    Write-Output "work-item status: Issue #$Issue refreshed for $($reports.Count) open PR(s)"
}
else {
    Write-Output "work-item status: all work items refreshed for $($reports.Count) open PR(s)"
}
