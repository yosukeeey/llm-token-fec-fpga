# Development Workflow

## Rules

- One Issue = one branch = one worktree = one PR.
- Branch names use `issue/<number>-<slug>`.
- Do not modify tracked files on `main`.
- Keep commits small within the Issue.
- Split work into another Issue when the scope changes.

## Start

Create the Issue first, then create its branch and worktree.

```powershell
git fetch origin main
.\scripts\work_item.ps1 start -Issue 123 -Slug uart-host
Set-Location ..\llm-token-fec-fpga-worktrees\issue-123-uart-host
.\scripts\work_item.ps1 verify
```

`start` rejects Issues with missing template fields, closed Issues, and Issues that already have a branch or PR. `verify` repeats the remote Issue check and confirms the local branch and worktree.

## Pull Request

Push the Issue branch and create one Draft PR. Include exactly one matching closing reference.

```text
Closes #123
```

Keep the template headings unchanged so the work record remains machine-readable. Record exact validation commands and their results separately. Use `None` for empty fields. Do not add authorship or generator metadata.

The `validate` GitHub check runs the same `scripts/work_item_policy.ps1` used locally. The `main protection` Ruleset requires this check, a PR, the latest base branch, merge commits, resolved review threads, and blocks deletion and force push.

## Cleanup

After merging the PR, remove its worktree and delete the local branch.

```powershell
git worktree remove ..\llm-token-fec-fpga-worktrees\issue-123-uart-host
git branch -d issue/123-uart-host
```
