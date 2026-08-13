[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repositoryRoot = Split-Path -Parent $PSScriptRoot

# Keep the policy in tracked files while activating it only for this clone.
git -C $repositoryRoot config --local core.hooksPath .githooks
if ($LASTEXITCODE -ne 0) {
    throw "Failed to configure Git hooks"
}

git -C $repositoryRoot config --local commit.template .gitmessage
if ($LASTEXITCODE -ne 0) {
    throw "Failed to configure the commit template"
}

Write-Host "Configured Git commit policy"
