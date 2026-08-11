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

## Communication

Keep output minimal:

* changed
* verified
* remaining issue, if any

Do not repeat the task or explain obvious code.

**Read → Understand → Smallest Change → Verify → Stop.**
