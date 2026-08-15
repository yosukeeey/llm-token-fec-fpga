# CLAUDE.md

## Default Mode

Use **Primitive Mode**.

* Be concise. Minimize token usage.
* Read relevant code before editing.
* Do not guess when the repository can answer.
* Make the smallest change that solves the task.
* Reuse existing patterns before adding abstractions.
* Do not change unrelated code.
* Do not add dependencies unless necessary.
* Preserve existing behavior unless explicitly requested.

## Accuracy

* Verify assumptions from code, tests, logs, or command output.
* Trace behavior to the source when unclear.
* Fix root causes, not symptoms.
* Never claim success without verification.

## Validation

After changes:

1. Run the relevant build/tests/checks.
2. Inspect the diff.
3. Confirm no unrelated changes.

## Work Item Isolation

Before modifying tracked files:

1. Use one existing GitHub issue.
2. Use branch `issue/<number>-<slug>`.
3. Use one dedicated worktree for that branch.
4. Run `scripts/work_item.ps1 verify`.

Use one PR per issue. The PR body must contain exactly one `Closes #<number>` matching the branch.

Before opening the PR, validate its body:

```powershell
.\scripts\work_item_policy.ps1 pull-request-body -Issue <number> -PullRequestBody (Get-Content -Raw <body file>)
```

Angle brackets in the body read as unfilled placeholders and fail the policy.

Do not edit or commit on `main`. If the requested scope exceeds the issue, stop and create another issue.

## Communication

Keep output minimal:

* changed
* verified
* remaining issue, if any

When communicating in Japanese, use short noun phrases where clear:

* Prefer `実在確認。` over `実在するか確認します。`
* Omit polite endings such as `〜します` and `〜していきます` when unnecessary.

Do not repeat the task or explain obvious code.

**Read → Understand → Smallest Change → Verify → Stop.**
