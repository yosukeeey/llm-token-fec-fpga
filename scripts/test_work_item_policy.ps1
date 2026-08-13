[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$policyPath = Join-Path $PSScriptRoot "work_item_policy.ps1"
$workItemPath = Join-Path $PSScriptRoot "work_item.ps1"
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

$validPullRequestBody = @'
## Change

- Add policy validation.

## Reason

- Prevent inconsistent work items.

## Validation commands

__FENCE__text
.\scripts\test_work_item_policy.ps1
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
$validPullRequestBody = $validPullRequestBody.Replace(
    "__FENCE__",
    (([string][char]96) * 3)
)

Assert-Pass "valid Issue body" {
    & $policyPath issue-body -IssueBody $validIssueBody
}
Assert-Fail "missing Issue heading" {
    & $policyPath issue-body -IssueBody (
        $validIssueBody -replace "### Constraints", "### Limits"
    )
}
Assert-Fail "unchecked Issue isolation" {
    & $policyPath issue-body -IssueBody ($validIssueBody -replace "\[x\]", "[ ]")
}
Assert-Pass "valid PR body" {
    & $policyPath pull-request-body -Issue 123 -PullRequestBody $validPullRequestBody
}
Assert-Fail "PR Issue mismatch" {
    & $policyPath pull-request-body -Issue 124 -PullRequestBody $validPullRequestBody
}
Assert-Fail "empty PR command block" {
    & $policyPath pull-request-body -Issue 123 -PullRequestBody (
        $validPullRequestBody -replace "\.\\scripts\\test_work_item_policy\.ps1", ""
    )
}
Assert-Fail "unchecked PR scope" {
    & $policyPath pull-request-body -Issue 123 -PullRequestBody (
        $validPullRequestBody -replace "\[x\] The diff", "[ ] The diff"
    )
}

$temporaryRoot = [System.IO.Path]::GetFullPath(
    (Join-Path ([System.IO.Path]::GetTempPath()) "work-item-policy-$([guid]::NewGuid().ToString('N'))")
)
$temporaryPrefix = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
if (-not $temporaryRoot.StartsWith(
    $temporaryPrefix,
    [System.StringComparison]::OrdinalIgnoreCase
)) {
    throw "Unexpected temporary path."
}

$repositoryPath = Join-Path $temporaryRoot "repository"
$worktreeRoot = Join-Path $temporaryRoot "worktrees"
$fakeBin = Join-Path $temporaryRoot "bin"
$oldPath = $env:PATH
try {
    New-Item -ItemType Directory -Path $repositoryPath, $fakeBin -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $fakeBin "gh.ps1") -Encoding Utf8 -Value @'
$argumentText = $args -join " "
if ($argumentText -match "/issues/[0-9]+") {
    Write-Output $env:WORK_ITEM_TEST_ISSUE_JSON
    exit 0
}
if ($argumentText -match "/pulls/[0-9]+$") {
    Write-Output $env:WORK_ITEM_TEST_PULL_JSON
    exit 0
}
if ($argumentText -match "/branches\?") {
    Write-Output $env:WORK_ITEM_TEST_BRANCH_PAGES
    exit 0
}
if ($argumentText -match "/pulls\?") {
    Write-Output $env:WORK_ITEM_TEST_PULL_PAGES
    exit 0
}
if ($argumentText -match "repos/[^/]+/[^/]+$") {
    Write-Output $env:WORK_ITEM_TEST_REPOSITORY_JSON
    exit 0
}
throw "Unexpected gh arguments: $argumentText"
'@

    $env:PATH = "$fakeBin;$oldPath"
    $env:WORK_ITEM_TEST_ISSUE_JSON = [ordered]@{
        number = 123
        state = "open"
        body = $validIssueBody
    } | ConvertTo-Json -Compress
    $env:WORK_ITEM_TEST_BRANCH_PAGES = "[[]]"
    $env:WORK_ITEM_TEST_PULL_PAGES = "[[]]"
    $env:WORK_ITEM_TEST_REPOSITORY_JSON = '{"default_branch":"main"}'

    git init -b main $repositoryPath | Out-Null
    git -C $repositoryPath config user.name "work-item-policy-test"
    git -C $repositoryPath config user.email "work-item-policy-test@example.invalid"
    git -C $repositoryPath commit --allow-empty -m "test: initialize repository" | Out-Null
    git -C $repositoryPath remote add origin "https://github.com/example/repository.git"

    $startArguments = @{
        Issue = 123
        Slug = "test-policy"
        Base = "main"
        WorktreeRoot = $worktreeRoot
    }
    Push-Location $repositoryPath
    try {
        $createdPath = & $workItemPath start @startArguments
    }
    finally {
        Pop-Location
    }

    Assert-Pass "temporary worktree verify" {
        Push-Location $createdPath
        try {
            & $workItemPath verify
        }
        finally {
            Pop-Location
        }
    }
    Assert-Fail "main worktree rejection" {
        Push-Location $repositoryPath
        try {
            & $workItemPath verify
        }
        finally {
            Pop-Location
        }
    }

    $env:WORK_ITEM_TEST_ISSUE_JSON = [ordered]@{
        number = 123
        state = "closed"
        body = $validIssueBody
    } | ConvertTo-Json -Compress
    Assert-Fail "closed Issue start rejection" {
        Push-Location $repositoryPath
        try {
            & $workItemPath start @startArguments
        }
        finally {
            Pop-Location
        }
    }

    $env:WORK_ITEM_TEST_ISSUE_JSON = [ordered]@{
        number = 123
        state = "open"
        body = $validIssueBody
    } | ConvertTo-Json -Compress
    $env:WORK_ITEM_TEST_BRANCH_PAGES = '[[{"name":"issue/123-existing"}]]'
    Assert-Fail "duplicate branch start rejection" {
        Push-Location $repositoryPath
        try {
            & $workItemPath start @startArguments
        }
        finally {
            Pop-Location
        }
    }

    $env:WORK_ITEM_TEST_BRANCH_PAGES = "[[]]"
    $duplicatePullRequest = [ordered]@{
        number = 7
        body = $validPullRequestBody
        head = [ordered]@{
            ref = "issue/123-existing"
            repo = [ordered]@{ full_name = "example/repository" }
        }
    } | ConvertTo-Json -Depth 4 -Compress
    $env:WORK_ITEM_TEST_PULL_PAGES = "[[$duplicatePullRequest]]"
    Assert-Fail "duplicate PR start rejection" {
        Push-Location $repositoryPath
        try {
            & $workItemPath start @startArguments
        }
        finally {
            Pop-Location
        }
    }

    $pullRequestRecord = [ordered]@{
        number = 7
        state = "open"
        body = $validPullRequestBody
        base = [ordered]@{ ref = "main" }
        head = [ordered]@{
            ref = "issue/123-test-policy"
            repo = [ordered]@{ full_name = "example/repository" }
        }
    } | ConvertTo-Json -Depth 4 -Compress
    $env:WORK_ITEM_TEST_PULL_JSON = $pullRequestRecord
    $env:WORK_ITEM_TEST_BRANCH_PAGES = '[[{"name":"issue/123-test-policy"}]]'
    $env:WORK_ITEM_TEST_PULL_PAGES = "[[$pullRequestRecord]]"
    Assert-Pass "pull request policy" {
        & $policyPath pull-request -Repository "example/repository" -PullRequest 7
    }

    git -C $repositoryPath worktree remove $createdPath
    git -C $repositoryPath switch "issue/123-test-policy" | Out-Null
    Assert-Fail "primary checkout rejection" {
        Push-Location $repositoryPath
        try {
            & $workItemPath verify
        }
        finally {
            Pop-Location
        }
    }
    git -C $repositoryPath switch main | Out-Null
    git -C $repositoryPath branch -d "issue/123-test-policy" | Out-Null

    Assert-Fail "uppercase slug start rejection" {
        Push-Location $repositoryPath
        try {
            & $workItemPath start -Issue 123 -Slug "Uppercase" -Base main -WorktreeRoot $worktreeRoot
        }
        finally {
            Pop-Location
        }
    }
    Assert-Fail "uppercase active branch rejection" {
        & $policyPath active -Repository "example/repository" -Branch "issue/123-Uppercase"
    }

    $env:WORK_ITEM_TEST_BRANCH_PAGES = '[[{"name":"issue/123-Uppercase"}]]'
    $env:WORK_ITEM_TEST_PULL_PAGES = "[[]]"
    Assert-Fail "uppercase remote branch reserves Issue" {
        & $policyPath available -Repository "example/repository" -Issue 123
    }

    $env:WORK_ITEM_TEST_BRANCH_PAGES = '[[{"name":"issue/123-conflict"}]]'
    $env:WORK_ITEM_TEST_PULL_PAGES = "[[]]"
    Assert-Fail "active branch conflict rejection" {
        & $policyPath active -Repository "example/repository" -Branch "issue/123-test-policy"
    }

    $env:WORK_ITEM_TEST_BRANCH_PAGES = '[[{"name":"issue/123-test-policy"}]]'
    $env:WORK_ITEM_TEST_PULL_PAGES = "[[$duplicatePullRequest]]"
    Assert-Fail "active PR conflict rejection" {
        & $policyPath active -Repository "example/repository" -Branch "issue/123-test-policy"
    }

    $forkPullRequest = [ordered]@{
        number = 8
        body = $validPullRequestBody
        head = [ordered]@{
            ref = "issue/123-fork"
            repo = [ordered]@{ full_name = "outside/repository" }
        }
    } | ConvertTo-Json -Depth 4 -Compress
    $env:WORK_ITEM_TEST_BRANCH_PAGES = "[[]]"
    $env:WORK_ITEM_TEST_PULL_PAGES = "[[$forkPullRequest]]"
    Assert-Pass "fork PR does not reserve Issue" {
        & $policyPath available -Repository "example/repository" -Issue 123
    }

    $wrongBasePullRequest = [ordered]@{
        number = 9
        state = "open"
        body = $validPullRequestBody
        base = [ordered]@{ ref = "release" }
        head = [ordered]@{
            ref = "issue/123-test-policy"
            repo = [ordered]@{ full_name = "example/repository" }
        }
    } | ConvertTo-Json -Depth 4 -Compress
    $env:WORK_ITEM_TEST_PULL_JSON = $wrongBasePullRequest
    Assert-Fail "wrong base PR rejection" {
        & $policyPath pull-request -Repository "example/repository" -PullRequest 9
    }

    $forkPullRequestRecord = [ordered]@{
        number = 10
        state = "open"
        body = $validPullRequestBody
        base = [ordered]@{ ref = "main" }
        head = [ordered]@{
            ref = "issue/123-test-policy"
            repo = [ordered]@{ full_name = "outside/repository" }
        }
    } | ConvertTo-Json -Depth 4 -Compress
    $env:WORK_ITEM_TEST_PULL_JSON = $forkPullRequestRecord
    Assert-Fail "fork PR policy rejection" {
        & $policyPath pull-request -Repository "example/repository" -PullRequest 10
    }

    $env:WORK_ITEM_TEST_ISSUE_JSON = [ordered]@{
        number = 124
        state = "open"
        body = ($validIssueBody -replace "### Validation", "### Verification")
    } | ConvertTo-Json -Compress
    $invalidArguments = @{
        Issue = 124
        Slug = "invalid-issue"
        Base = "main"
        WorktreeRoot = $worktreeRoot
    }
    Assert-Fail "invalid Issue start rejection" {
        Push-Location $repositoryPath
        try {
            & $workItemPath start @invalidArguments
        }
        finally {
            Pop-Location
        }
    }
}
finally {
    $env:PATH = $oldPath
    Remove-Item Env:WORK_ITEM_TEST_ISSUE_JSON -ErrorAction SilentlyContinue
    Remove-Item Env:WORK_ITEM_TEST_BRANCH_PAGES -ErrorAction SilentlyContinue
    Remove-Item Env:WORK_ITEM_TEST_PULL_PAGES -ErrorAction SilentlyContinue
    Remove-Item Env:WORK_ITEM_TEST_PULL_JSON -ErrorAction SilentlyContinue
    Remove-Item Env:WORK_ITEM_TEST_REPOSITORY_JSON -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}

Write-Output "work_item_policy: $passed cases passed"
