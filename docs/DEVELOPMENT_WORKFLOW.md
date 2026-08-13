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

## Pull Request

Push the Issue branch and create one Draft PR. Include exactly one matching closing reference.

```text
Closes #123
```

## Cleanup

After merging the PR, remove its worktree and delete the local branch.

```powershell
git worktree remove ..\llm-token-fec-fpga-worktrees\issue-123-uart-host
git branch -d issue/123-uart-host
```
