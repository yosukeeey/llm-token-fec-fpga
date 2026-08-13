# Work Item Status Refresh Validation

## Scope

Validate that mutable Issue and branch state refreshes `work-item-policy` on the current PR head through trusted default-branch workflows.

## Procedure

1. Confirm the initial PR status is successful.
2. Make the linked Issue body invalid, then restore it.
3. Close and reopen the linked Issue.
4. Create a temporary conflicting Issue branch and request a full scan.
5. Delete the conflicting branch and confirm automatic recovery.
6. Request a final full scan.

For every transition, record the PR head SHA, status state, status creator, Actions event, run URL, and merge state.

## Results

Pending live validation.
