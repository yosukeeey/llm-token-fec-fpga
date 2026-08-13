import importlib.util
import sys


def test_python_environment() -> None:
    assert sys.version_info[:2] == (3, 12)
    assert importlib.util.find_spec("serial") is None
