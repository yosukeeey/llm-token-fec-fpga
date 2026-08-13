"""Generate or verify deterministic reference JSONL test vectors."""

import argparse
from pathlib import Path

from sw.evaluation import check_vector_files, write_vector_files

DEFAULT_OUTPUT = Path("datasets/test_vectors/protocol_v0")


def main() -> int:
    """Generate reference JSONL files or verify their reproducibility.

    Returns
    -------
    int
        Zero on success, otherwise one when ``--check`` finds differences.
    """
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--check", action="store_true")
    arguments = parser.parse_args()

    if arguments.check:
        if not check_vector_files(arguments.output_dir):
            print(f"Reference vectors differ from generated output: {arguments.output_dir}")
            return 1
        print(f"Reference vectors are reproducible: {arguments.output_dir}")
        return 0

    write_vector_files(arguments.output_dir)
    print(f"Generated reference vectors: {arguments.output_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
