import ast
from pathlib import Path

SOURCE_ROOTS = (Path("sw"), Path("scripts"))


def _section_entries(docstring: str, section: str) -> set[str]:
    lines = docstring.splitlines()
    try:
        start = lines.index(section)
    except ValueError:
        return set()

    entries: set[str] = set()
    for index in range(start + 2, len(lines)):
        line = lines[index]
        if (
            index + 1 < len(lines)
            and line
            and set(lines[index + 1]) == {"-"}
        ):
            break
        stripped = line.strip()
        if line == stripped and " : " in stripped:
            entries.add(stripped.split(" : ", 1)[0])
    return entries


def _public_functions(tree: ast.AST) -> list[ast.FunctionDef]:
    return [
        node
        for node in ast.walk(tree)
        if isinstance(node, ast.FunctionDef)
        and not node.name.startswith("_")
    ]


def test_numpy_docstrings_type_every_public_parameter() -> None:
    failures: list[str] = []
    for root in SOURCE_ROOTS:
        for path in root.rglob("*.py"):
            tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
            for function in _public_functions(tree):
                parameters = [
                    argument.arg
                    for argument in [
                        *function.args.posonlyargs,
                        *function.args.args,
                        *function.args.kwonlyargs,
                    ]
                    if argument.arg not in {"self", "cls"}
                ]
                if function.args.vararg:
                    parameters.append(function.args.vararg.arg)
                if function.args.kwarg:
                    parameters.append(function.args.kwarg.arg)
                if not parameters:
                    continue

                docstring = ast.get_docstring(function) or ""
                documented = _section_entries(docstring, "Parameters")
                missing = sorted(set(parameters) - documented)
                if missing:
                    failures.append(
                        f"{path}:{function.lineno} {function.name}: "
                        f"missing typed parameters {', '.join(missing)}"
                    )

    assert not failures, "\n".join(failures)


def test_numpy_docstrings_type_public_class_attributes() -> None:
    failures: list[str] = []
    for root in SOURCE_ROOTS:
        for path in root.rglob("*.py"):
            tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
            for class_node in (
                node
                for node in ast.walk(tree)
                if isinstance(node, ast.ClassDef) and not node.name.startswith("_")
            ):
                attributes = {
                    statement.target.id
                    for statement in class_node.body
                    if isinstance(statement, ast.AnnAssign)
                    and isinstance(statement.target, ast.Name)
                    and not statement.target.id.startswith("_")
                }
                if not attributes:
                    continue

                docstring = ast.get_docstring(class_node) or ""
                documented = _section_entries(docstring, "Attributes")
                missing = sorted(attributes - documented)
                if missing:
                    failures.append(
                        f"{path}:{class_node.lineno} {class_node.name}: "
                        f"missing typed attributes {', '.join(missing)}"
                    )

    assert not failures, "\n".join(failures)
