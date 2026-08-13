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

Validated on PR #16 at head `267df3ff9df6ec0533c6eaae801a98b4433e55d1`.

| Transition | Status | Event | PR state | Run |
| --- | --- | --- | --- | --- |
| Initial valid state | success | `pull_request_target` | clean | [31714373709](https://github.com/yosukeeey/llm-token-fec-fpga/actions/runs/31714373709) |
| Invalid Issue body | failure | `issues` | blocked | [31714441174](https://github.com/yosukeeey/llm-token-fec-fpga/actions/runs/31714441174) |
| Restored Issue body | success | `issues` | clean | [31714481127](https://github.com/yosukeeey/llm-token-fec-fpga/actions/runs/31714481127) |
| Closed Issue | failure | `issues` | blocked | [31714543003](https://github.com/yosukeeey/llm-token-fec-fpga/actions/runs/31714543003) |
| Reopened Issue | success | `issues` | clean | [31714575209](https://github.com/yosukeeey/llm-token-fec-fpga/actions/runs/31714575209) |
| Conflicting branch plus full scan | failure | `repository_dispatch` | blocked | [31714664801](https://github.com/yosukeeey/llm-token-fec-fpga/actions/runs/31714664801) |
| Conflicting branch deleted | success | `delete` | clean | [31715408027](https://github.com/yosukeeey/llm-token-fec-fpga/actions/runs/31715408027) |
| Final full scan | success | `repository_dispatch` | clean | [31715473355](https://github.com/yosukeeey/llm-token-fec-fpga/actions/runs/31715473355) |

Every status was created by `github-actions[bot]` on the current PR head. The active Ruleset required `work-item-policy` from GitHub Actions App ID `15368` throughout the validation.

## Final State

- Issue #14 is open with its original `### Validation` heading restored.
- `issue/14-conflict` is deleted.
- `issue/14-validate-status-refresh` is the only matching remote branch.
- The final required status is successful and PR #16 is clean.
