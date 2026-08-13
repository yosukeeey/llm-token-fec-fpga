[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory)]
    [ValidateSet(
        "available",
        "active",
        "pull-request",
        "issue-body",
        "pull-request-body"
    )]
    [string]$Command,

    [string]$Repository,

    [int]$Issue,

    [string]$Branch,

    [int]$PullRequest,

    [string]$IssueBody,

    [string]$PullRequestBody
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$branchPattern = "^issue/(?<issue>[1-9][0-9]*)-[a-z0-9]+(?:-[a-z0-9]+)*$"
$issueSections = @(
    "Objective",
    "In scope",
    "Out of scope",
    "Constraints",
    "Acceptance criteria",
    "Validation",
    "Work item isolation"
)
$pullRequestSections = @(
    "Change",
    "Reason",
    "Validation commands",
    "Validation results",
    "Artifacts",
    "Remaining issues",
    "Scope check"
)
$placeholderPattern = "(?i)(<[^>\r\n]+>|\b(?:TODO|TBD)\b|_No response_)"

function ConvertFrom-WorkItemSections {
    param(
        [string]$Body,
        [int]$HeadingLevel,
        [string[]]$RequiredSections
    )

    $heading = "#" * $HeadingLevel
    $escapedHeading = [regex]::Escape($heading)
    $matches = [regex]::Matches(
        [string]$Body,
        "(?ms)^$escapedHeading (?<name>[^\r\n]+)\r?\n(?<content>.*?)(?=^$escapedHeading |\z)"
    )
    $names = @($matches | ForEach-Object { $_.Groups["name"].Value.Trim() })
    if (($names -join "\n") -cne ($RequiredSections -join "\n")) {
        throw "Required headings must appear once and in the defined order: $($RequiredSections -join ', ')"
    }

    $sections = @{}
    foreach ($match in $matches) {
        $name = $match.Groups["name"].Value.Trim()
        if ($sections.ContainsKey($name)) {
            throw "Duplicate heading: $name"
        }
        $sections[$name] = $match.Groups["content"].Value
    }
    return $sections
}

function Remove-WorkItemGuidance {
    param([string]$Value)

    return [regex]::Replace([string]$Value, "(?s)<!--.*?-->", "").Trim()
}

function Assert-WorkItemValue {
    param(
        [string]$Name,
        [string]$Value,
        [switch]$AllowNone
    )

    $cleanValue = Remove-WorkItemGuidance $Value
    if ([string]::IsNullOrWhiteSpace($cleanValue)) {
        throw "$Name must not be empty."
    }
    if ($cleanValue -match $placeholderPattern) {
        throw "$Name contains a placeholder."
    }
    if (-not $AllowNone -and $cleanValue -match "(?i)^[-*\s]*None\.?\s*$") {
        throw "$Name must not be None."
    }
}

function Assert-WorkItemIssueBody {
    param([string]$Body)

    $sections = ConvertFrom-WorkItemSections $Body 3 $issueSections
    Assert-WorkItemValue "Objective" $sections["Objective"]
    Assert-WorkItemValue "In scope" $sections["In scope"]
    Assert-WorkItemValue "Out of scope" $sections["Out of scope"] -AllowNone
    Assert-WorkItemValue "Constraints" $sections["Constraints"] -AllowNone
    Assert-WorkItemValue "Acceptance criteria" $sections["Acceptance criteria"]
    Assert-WorkItemValue "Validation" $sections["Validation"]

    $isolation = Remove-WorkItemGuidance $sections["Work item isolation"]
    $checked = [regex]::Matches(
        $isolation,
        "(?im)^\s*-\s*\[[xX]\]\s*This Issue will use one branch, one worktree, and one PR\.\s*$"
    )
    if ($checked.Count -ne 1 -or $isolation -match "(?im)^\s*-\s*\[ \]") {
        throw "Work item isolation must be checked."
    }
}

function Assert-WorkItemPullRequestBody {
    param(
        [string]$Body,
        [int]$ExpectedIssue
    )

    $cleanBody = Remove-WorkItemGuidance $Body
    if ($cleanBody -match $placeholderPattern) {
        throw "PR body contains a placeholder."
    }

    $sections = ConvertFrom-WorkItemSections $Body 2 $pullRequestSections
    Assert-WorkItemValue "Change" $sections["Change"]
    Assert-WorkItemValue "Reason" $sections["Reason"]
    Assert-WorkItemValue "Validation commands" $sections["Validation commands"]
    Assert-WorkItemValue "Validation results" $sections["Validation results"]
    Assert-WorkItemValue "Artifacts" $sections["Artifacts"] -AllowNone
    Assert-WorkItemValue "Remaining issues" $sections["Remaining issues"] -AllowNone

    $fence = [regex]::Escape(([string][char]96) * 3)
    $commandBlocks = [regex]::Matches(
        $sections["Validation commands"],
        "(?ms)$fence[^\r\n]*\r?\n(?<commands>.*?)$fence"
    )
    $hasCommand = @(
        $commandBlocks |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_.Groups["commands"].Value) }
    ).Count -gt 0
    if (-not $hasCommand) {
        throw "Validation commands must contain a non-empty code block."
    }

    $scopeCheck = Remove-WorkItemGuidance $sections["Scope check"]
    $requiredChecks = @(
        "Changes stay within the linked Issue.",
        "No unrelated files changed.",
        "The diff was inspected."
    )
    foreach ($requiredCheck in $requiredChecks) {
        $escapedCheck = [regex]::Escape($requiredCheck)
        if ($scopeCheck -notmatch "(?im)^\s*-\s*\[[xX]\]\s*$escapedCheck\s*$") {
            throw "Scope check is incomplete: $requiredCheck"
        }
    }
    if ($scopeCheck -match "(?im)^\s*-\s*\[ \]") {
        throw "Scope check contains an unchecked item."
    }

    $closingReferences = [regex]::Matches(
        [string]$Body,
        "(?im)(?<![A-Za-z])Closes\s+#(?<issue>[1-9][0-9]*)\b"
    )
    if ($closingReferences.Count -ne 1) {
        throw "PR body must contain exactly one Closes #<number>."
    }
    if ([int]$closingReferences[0].Groups["issue"].Value -ne $ExpectedIssue) {
        throw "Branch and PR body must reference the same Issue."
    }
}

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

function Assert-WorkItemRepository {
    param([string]$Value)

    if ($Value -notmatch "^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$") {
        throw "Repository must use owner/name."
    }
}

function Get-WorkItemIssue {
    param(
        [string]$RepositoryName,
        [int]$IssueNumber
    )

    $issueRecord = Get-GitHubJson "repos/$RepositoryName/issues/$IssueNumber"
    if ($null -ne $issueRecord.PSObject.Properties["pull_request"]) {
        throw "#$IssueNumber is a PR, not an Issue."
    }
    if ($issueRecord.state -ne "open") {
        throw "Issue #$IssueNumber must be open."
    }
    Assert-WorkItemIssueBody ([string]$issueRecord.body)
    return $issueRecord
}

function Get-WorkItemBranches {
    param(
        [string]$RepositoryName,
        [int]$IssueNumber
    )

    return @(
        Get-GitHubPagedItems "repos/$RepositoryName/branches?per_page=100" |
            Where-Object {
                $_.name -match "^issue/$IssueNumber-[a-z0-9]+(?:-[a-z0-9]+)*$"
            }
    )
}

function Get-WorkItemPullRequests {
    param(
        [string]$RepositoryName,
        [int]$IssueNumber
    )

    $branchExpression = "^issue/$IssueNumber-[a-z0-9]+(?:-[a-z0-9]+)*$"
    $closingExpression = "(?im)(?<![A-Za-z])Closes\s+#$IssueNumber\b"
    return @(
        Get-GitHubPagedItems "repos/$RepositoryName/pulls?state=all&per_page=100" |
            Where-Object {
                $_.head.ref -match $branchExpression -or
                [regex]::IsMatch([string]$_.body, $closingExpression)
            }
    )
}

switch ($Command) {
    "issue-body" {
        Assert-WorkItemIssueBody $IssueBody
        Write-Output "work-item policy: Issue body passed"
    }
    "pull-request-body" {
        if ($Issue -lt 1) {
            throw "Issue must be a positive integer."
        }
        Assert-WorkItemPullRequestBody $PullRequestBody $Issue
        Write-Output "work-item policy: PR body passed"
    }
    "available" {
        Assert-WorkItemRepository $Repository
        if ($Issue -lt 1) {
            throw "Issue must be a positive integer."
        }
        Get-WorkItemIssue $Repository $Issue | Out-Null
        if (@(Get-WorkItemBranches $Repository $Issue).Count -ne 0) {
            throw "Issue #$Issue already has a branch."
        }
        if (@(Get-WorkItemPullRequests $Repository $Issue).Count -ne 0) {
            throw "Issue #$Issue already has a PR."
        }
        Write-Output "work-item policy: Issue #$Issue is available"
    }
    "active" {
        Assert-WorkItemRepository $Repository
        if ($Branch -notmatch $branchPattern) {
            throw "Branch must match issue/<number>-<slug>."
        }
        $issueNumber = [int]$Matches.issue
        Get-WorkItemIssue $Repository $issueNumber | Out-Null

        $branches = @(Get-WorkItemBranches $Repository $issueNumber)
        if ($branches.Count -gt 1 -or (
            $branches.Count -eq 1 -and
            $branches[0].name -ne $Branch
        )) {
            throw "Issue #$issueNumber has a conflicting branch."
        }

        $pullRequests = @(Get-WorkItemPullRequests $Repository $issueNumber)
        if ($pullRequests.Count -gt 1 -or (
            $pullRequests.Count -eq 1 -and
            $pullRequests[0].head.ref -ne $Branch
        )) {
            throw "Issue #$issueNumber has a conflicting PR."
        }
        if ($pullRequests.Count -eq 1) {
            Assert-WorkItemPullRequestBody ([string]$pullRequests[0].body) $issueNumber
        }
        Write-Output "work-item policy: Issue #$issueNumber is active"
    }
    "pull-request" {
        Assert-WorkItemRepository $Repository
        if ($PullRequest -lt 1) {
            throw "PullRequest must be a positive integer."
        }

        $repositoryRecord = Get-GitHubJson "repos/$Repository"
        $pullRequestRecord = Get-GitHubJson "repos/$Repository/pulls/$PullRequest"
        if ($pullRequestRecord.state -ne "open") {
            throw "PR #$PullRequest must be open."
        }
        if ($pullRequestRecord.base.ref -ne $repositoryRecord.default_branch) {
            throw "PR must target the default branch."
        }
        if ($pullRequestRecord.head.repo.full_name -ne $Repository) {
            throw "PR branch must belong to this repository."
        }

        $Branch = [string]$pullRequestRecord.head.ref
        if ($Branch -notmatch $branchPattern) {
            throw "Branch must match issue/<number>-<slug>."
        }
        $issueNumber = [int]$Matches.issue
        Assert-WorkItemPullRequestBody ([string]$pullRequestRecord.body) $issueNumber
        Get-WorkItemIssue $Repository $issueNumber | Out-Null

        $branches = @(Get-WorkItemBranches $Repository $issueNumber)
        if ($branches.Count -ne 1 -or $branches[0].name -ne $Branch) {
            throw "Issue #$issueNumber must have exactly one branch."
        }

        $pullRequests = @(Get-WorkItemPullRequests $Repository $issueNumber)
        if ($pullRequests.Count -ne 1 -or $pullRequests[0].number -ne $PullRequest) {
            throw "Issue #$issueNumber must have exactly one PR."
        }
        Write-Output "work-item policy: PR #$PullRequest passed"
    }
}
