# Contributing

## Commits

Run `./scripts/configure_git.ps1` once after cloning. This enables the tracked
commit template and commit-message hook.

Use `<type>(<scope>): <summary>` and keep each commit focused on one purpose.
The hook enforces the allowed types, required lowercase scope, 72-character
limit, and blank line before a body.

## Code comments

Keep comments brief and use them only to record:

* why an approach was selected;
* why a seemingly unnecessary operation remains;
* external constraints from hardware, protocols, or legacy systems;
* non-obvious invariants involving concurrency, interrupts, or DMA;
* safety conditions that must not be changed;
* known defects and their workarounds.

Do not restate what the code already says.

Python public API documentation uses concise NumPy-style docstrings. Parameter
and attribute entries include types, for example `data : bytes`.

When one of the cases above needs a comment, use Doxygen syntax for C/C++ and
standard block or line comments for SystemVerilog.
