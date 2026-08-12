# Contributing

## Commits

Run `./scripts/configure_git.ps1` once after cloning. This enables the tracked
commit template and commit-message hook.

Use `<type>(<scope>): <summary>` and keep each commit focused on one purpose.
The hook enforces the allowed types, required lowercase scope, 72-character
limit, and blank line before a body.

## Code comments

Comments must explain contracts and decisions that code alone does not show:

* bit and byte ordering, field layout, and units;
* supported parameter values and correction limits;
* non-obvious algorithm choices and hardware constraints;
* public behavior that another implementation must reproduce.

Do not restate obvious assignments or let comments duplicate stale code.

Python public modules, classes, functions, and methods use NumPy-style
docstrings. Parameter and attribute entries include types, for example
`data : bytes`. Include only the sections that add information, such as
`Parameters`, `Attributes`, `Returns`, `Raises`, and `Notes`.

C and C++ public declarations use Doxygen comments with `@brief`, `@param`,
`@return`, and `@throws` where applicable. SystemVerilog modules use Doxygen
module headers that document parameters, ports, bit ordering, latency, and
correction limits.
