[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$statusPath = Join-Path $PSScriptRoot "work_item_status.ps1"
$passed = 0

function Assert-Pass {
    param(
        [string]$Name,
        [scriptblock]$Action
    )

    & $Action | Out-Null
    $script:passed++
    Write-Output "PASS $Name"
}

function Assert-Fail {
    param(
        [string]$Name,
        [scriptblock]$Action
    )

    $failed = $false
    try {
        & $Action | Out-Null
    }
    catch {
        $failed = $true
    }
    if (-not $failed) {
        throw "Expected failure: $Name"
    }
    $script:passed++
    Write-Output "PASS $Name"
}

function Assert-StatusLog {
    param(
        [string]$Name,
        [string[]]$Expected
    )

    $actual = if (Test-Path -LiteralPath $env:WORK_ITEM_STATUS_LOG) {
        @(Get-Content -LiteralPath $env:WORK_ITEM_STATUS_LOG)
    }
    else {
        @()
    }
    if (($actual -join "`n") -cne ($Expected -join "`n")) {
        throw "$Name status mismatch. Expected '$($Expected -join ', ')', got '$($actual -join ', ')'"
    }
    $script:passed++
    Write-Output "PASS $Name"
}

function Reset-StatusLog {
    Remove-Item -LiteralPath $env:WORK_ITEM_STATUS_LOG -ErrorAction SilentlyContinue
}

$validIssueBody = @'
### Objective

Create one observable result.

### In scope

- Policy scripts

### Out of scope

- None.

### Constraints

- PowerShell 7

### Acceptance criteria

- Valid input passes.

### Validation

- Run the policy tests.

### Work item isolation

- [x] This Issue will use one branch, one worktree, and one PR.
'@

$pullRequestBody123 = @'
## Change

- Add policy validation.

## Reason

- Prevent inconsistent work items.

## Validation commands

__FENCE__text
.\scripts\test_work_item_status.ps1
__FENCE__

## Validation results

- All cases passed.

## Artifacts

- None.

## Remaining issues

- None.

## Scope check

- [x] Changes stay within the linked Issue.
- [x] No unrelated files changed.
- [x] The diff was inspected.

Closes #123
'@
$pullRequestBody123 = $pullRequestBody123.Replace(
    "__FENCE__",
    (([string][char]96) * 3)
)
$pullRequestBody124 = $pullRequestBody123 -replace "#123", "#124"

$temporaryRoot = [System.IO.Path]::GetFullPath(
    (Join-Path ([System.IO.Path]::GetTempPath()) "work-item-status-$([guid]::NewGuid().ToString('N'))")
)
$temporaryPrefix = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
if (-not $temporaryRoot.StartsWith(
    $temporaryPrefix,
    [System.StringComparison]::OrdinalIgnoreCase
)) {
    throw "Unexpected temporary path."
}

$fakeBin = Join-Path $temporaryRoot "bin"
$oldPath = $env:PATH
try {
    New-Item -ItemType Directory -Path $fakeBin -Force | Out-Null
    $env:WORK_ITEM_STATUS_LOG = Join-Path $temporaryRoot "statuses.log"
    Set-Content -LiteralPath (Join-Path $fakeBin "gh.ps1") -Encoding Utf8 -Value @'
$argumentText = $args -join " "
if ($argumentText -match "api --method POST repos/[^/]+/[^/]+/statuses/(?<sha>[0-9a-fA-F]{40})") {
    $state = [string]@($args | Where-Object { $_ -like "state=*" })[0]
    $context = [string]@($args | Where-Object { $_ -like "context=*" })[0]
    $target = [string]@($args | Where-Object { $_ -like "target_url=*" })[0]
    if ($state -eq "state=pending" -and $Matches.sha -eq $env:WORK_ITEM_STATUS_FAIL_PENDING_SHA) {
        Write-Error "Injected pending failure"
        exit 1
    }
    Add-Content -LiteralPath $env:WORK_ITEM_STATUS_LOG -Value "$($Matches.sha) $state $context $target"
    Write-Output "{}"
    exit 0
}
if ($argumentText -match "/issues/(?<issue>[0-9]+)$") {
    $name = "WORK_ITEM_STATUS_ISSUE_$($Matches.issue)_JSON"
    Write-Output (Get-Item -LiteralPath "Env:$name").Value
    exit 0
}
if ($argumentText -match "/pulls/(?<pull>[0-9]+)$") {
    $name = "WORK_ITEM_STATUS_PULL_$($Matches.pull)_JSON"
    Write-Output (Get-Item -LiteralPath "Env:$name").Value
    exit 0
}
if ($argumentText -match "/branches\?") {
    Write-Output $env:WORK_ITEM_STATUS_BRANCH_PAGES
    exit 0
}
if ($argumentText -match "/pulls\?") {
    Write-Output $env:WORK_ITEM_STATUS_PULL_PAGES
    exit 0
}
if ($argumentText -match "repos/[^/]+/[^/]+$") {
    Write-Output '{"default_branch":"main"}'
    exit 0
}
throw "Unexpected gh arguments: $argumentText"
'@
    $env:PATH = "$fakeBin;$oldPath"

    $sha123 = "a" * 40
    $sha124 = "b" * 40
    $pull123 = [ordered]@{
        number = 7
        state = "open"
        body = $pullRequestBody123
        base = [ordered]@{ ref = "main" }
        head = [ordered]@{
            ref = "issue/123-status-test"
            sha = $sha123
            repo = [ordered]@{ full_name = "example/repository" }
        }
    }
    $pull124 = [ordered]@{
        number = 8
        state = "open"
        body = $pullRequestBody124
        base = [ordered]@{ ref = "main" }
        head = [ordered]@{
            ref = "issue/124-status-test"
            sha = $sha124
            repo = [ordered]@{ full_name = "example/repository" }
        }
    }
    $forkPull = [ordered]@{
        number = 9
        state = "open"
        body = $pullRequestBody123
        base = [ordered]@{ ref = "main" }
        head = [ordered]@{
            ref = "issue/123-fork"
            sha = "c" * 40
            repo = [ordered]@{ full_name = "outside/repository" }
        }
    }
    $env:WORK_ITEM_STATUS_PULL_7_JSON = $pull123 | ConvertTo-Json -Depth 5 -Compress
    $env:WORK_ITEM_STATUS_PULL_8_JSON = $pull124 | ConvertTo-Json -Depth 5 -Compress
    $env:WORK_ITEM_STATUS_PULL_9_JSON = $forkPull | ConvertTo-Json -Depth 5 -Compress
    $env:WORK_ITEM_STATUS_ISSUE_123_JSON = [ordered]@{
        number = 123
        state = "open"
        body = $validIssueBody
    } | ConvertTo-Json -Compress
    $env:WORK_ITEM_STATUS_ISSUE_124_JSON = [ordered]@{
        number = 124
        state = "closed"
        body = $validIssueBody
    } | ConvertTo-Json -Compress
    $env:WORK_ITEM_STATUS_BRANCH_PAGES = @(@(
        [ordered]@{ name = "issue/123-status-test" },
        [ordered]@{ name = "issue/124-status-test" }
    )) | ConvertTo-Json -Depth 4 -Compress
    $env:WORK_ITEM_STATUS_PULL_PAGES = @(@(
        $pull123,
        $pull124,
        $forkPull
    )) | ConvertTo-Json -Depth 6 -Compress

    $common = @{
        Repository = "example/repository"
        TargetUrl = "https://example.invalid/actions/runs/1"
    }

    Reset-StatusLog
    Assert-Pass "direct PR success" {
        & $statusPath pull-request @common -PullRequest 7
    }
    Assert-StatusLog "direct PR sequence" @(
        "$sha123 state=pending context=work-item-policy target_url=$($common.TargetUrl)",
        "$sha123 state=success context=work-item-policy target_url=$($common.TargetUrl)"
    )

    Reset-StatusLog
    $env:WORK_ITEM_STATUS_FAIL_PENDING_SHA = $sha123
    Assert-Fail "pending failure continues to final failure" {
        & $statusPath pull-request @common -PullRequest 7
    }
    Assert-StatusLog "pending failure final status" @(
        "$sha123 state=failure context=work-item-policy target_url=$($common.TargetUrl)"
    )
    Remove-Item Env:WORK_ITEM_STATUS_FAIL_PENDING_SHA

    Reset-StatusLog
    $env:WORK_ITEM_STATUS_ISSUE_123_JSON = [ordered]@{
        number = 123
        state = "open"
        body = ($validIssueBody -replace "### Validation", "### Verification")
    } | ConvertTo-Json -Compress
    Assert-Fail "invalid Issue body failure" {
        & $statusPath pull-request @common -PullRequest 7
    }
    Assert-StatusLog "invalid Issue body sequence" @(
        "$sha123 state=pending context=work-item-policy target_url=$($common.TargetUrl)",
        "$sha123 state=failure context=work-item-policy target_url=$($common.TargetUrl)"
    )

    Reset-StatusLog
    $env:WORK_ITEM_STATUS_ISSUE_123_JSON = [ordered]@{
        number = 123
        state = "open"
        body = $validIssueBody
    } | ConvertTo-Json -Compress
    Assert-Pass "restored Issue body success" {
        & $statusPath pull-request @common -PullRequest 7
    }
    Assert-StatusLog "restored Issue body sequence" @(
        "$sha123 state=pending context=work-item-policy target_url=$($common.TargetUrl)",
        "$sha123 state=success context=work-item-policy target_url=$($common.TargetUrl)"
    )

    Reset-StatusLog
    Assert-Fail "closed Issue failure" {
        & $statusPath pull-request @common -PullRequest 8
    }
    Assert-StatusLog "closed Issue sequence" @(
        "$sha124 state=pending context=work-item-policy target_url=$($common.TargetUrl)",
        "$sha124 state=failure context=work-item-policy target_url=$($common.TargetUrl)"
    )

    Reset-StatusLog
    $env:WORK_ITEM_STATUS_ISSUE_124_JSON = [ordered]@{
        number = 124
        state = "open"
        body = $validIssueBody
    } | ConvertTo-Json -Compress
    Assert-Pass "reopened Issue success" {
        & $statusPath pull-request @common -PullRequest 8
    }
    Assert-StatusLog "reopened Issue sequence" @(
        "$sha124 state=pending context=work-item-policy target_url=$($common.TargetUrl)",
        "$sha124 state=success context=work-item-policy target_url=$($common.TargetUrl)"
    )

    Reset-StatusLog
    $env:WORK_ITEM_STATUS_BRANCH_PAGES = @(@(
        [ordered]@{ name = "issue/123-status-test" },
        [ordered]@{ name = "issue/123-conflict" },
        [ordered]@{ name = "issue/124-status-test" }
    )) | ConvertTo-Json -Depth 4 -Compress
    Assert-Fail "conflicting branch failure" {
        & $statusPath pull-request @common -PullRequest 7
    }
    Assert-StatusLog "conflicting branch sequence" @(
        "$sha123 state=pending context=work-item-policy target_url=$($common.TargetUrl)",
        "$sha123 state=failure context=work-item-policy target_url=$($common.TargetUrl)"
    )

    Reset-StatusLog
    $env:WORK_ITEM_STATUS_BRANCH_PAGES = @(@(
        [ordered]@{ name = "issue/123-status-test" },
        [ordered]@{ name = "issue/124-status-test" }
    )) | ConvertTo-Json -Depth 4 -Compress
    Assert-Pass "conflicting branch removal success" {
        & $statusPath pull-request @common -PullRequest 7
    }
    Assert-StatusLog "conflicting branch removal sequence" @(
        "$sha123 state=pending context=work-item-policy target_url=$($common.TargetUrl)",
        "$sha123 state=success context=work-item-policy target_url=$($common.TargetUrl)"
    )

    $env:WORK_ITEM_STATUS_ISSUE_124_JSON = [ordered]@{
        number = 124
        state = "closed"
        body = $validIssueBody
    } | ConvertTo-Json -Compress

    Reset-StatusLog
    Assert-Pass "Issue selector excludes unrelated and fork PRs" {
        & $statusPath issue @common -Issue 123
    }
    Assert-StatusLog "Issue selector sequence" @(
        "$sha123 state=pending context=work-item-policy target_url=$($common.TargetUrl)",
        "$sha123 state=success context=work-item-policy target_url=$($common.TargetUrl)"
    )

    Reset-StatusLog
    $env:WORK_ITEM_STATUS_ISSUE_123_JSON = [ordered]@{
        number = 123
        state = "open"
        body = ($validIssueBody -replace "### Validation", "### Verification")
    } | ConvertTo-Json -Compress
    $env:WORK_ITEM_STATUS_ISSUE_124_JSON = [ordered]@{
        number = 124
        state = "open"
        body = $validIssueBody
    } | ConvertTo-Json -Compress
    Assert-Fail "full scan continues after failure" {
        & $statusPath all @common
    }
    Assert-StatusLog "full scan final statuses" @(
        "$sha123 state=pending context=work-item-policy target_url=$($common.TargetUrl)",
        "$sha124 state=pending context=work-item-policy target_url=$($common.TargetUrl)",
        "$sha123 state=failure context=work-item-policy target_url=$($common.TargetUrl)",
        "$sha124 state=success context=work-item-policy target_url=$($common.TargetUrl)"
    )

    Reset-StatusLog
    $env:WORK_ITEM_STATUS_PULL_PAGES = "[[]]"
    Assert-Pass "empty full scan" {
        & $statusPath all @common
    }
    Assert-StatusLog "empty full scan status" @()

    Assert-Fail "invalid repository rejection" {
        & $statusPath all -Repository "invalid" -TargetUrl $common.TargetUrl
    }
    Assert-Fail "invalid target URL rejection" {
        & $statusPath all -Repository $common.Repository -TargetUrl "http://example.invalid"
    }
    Assert-Fail "missing PR rejection" {
        & $statusPath pull-request @common
    }
    Assert-Fail "mixed PR and Issue rejection" {
        & $statusPath pull-request @common -PullRequest 7 -Issue 123
    }
    Assert-Fail "missing Issue rejection" {
        & $statusPath issue @common
    }
    Assert-Fail "mixed all selector rejection" {
        & $statusPath all @common -Issue 123
    }
}
finally {
    $env:PATH = $oldPath
    Get-ChildItem Env:WORK_ITEM_STATUS_* -ErrorAction SilentlyContinue |
        Remove-Item -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}

Write-Output "work_item_status: $passed cases passed"
