"""Generate simulator input records from the fixed reference JSONL vectors."""

import argparse
from pathlib import Path

from sw.evaluation import write_rtl_vector_files

DEFAULT_VECTORS = Path("datasets/test_vectors/protocol_v0")
DEFAULT_OUTPUT = Path("build/rtl/vectors")


def main() -> int:
    """Generate RTL simulator inputs from the fixed JSONL vectors.

    Returns
    -------
    int
        Process exit status. Zero indicates successful generation.
    """
    parser = argparse.ArgumentParser()
    parser.add_argument("--vectors", type=Path, default=DEFAULT_VECTORS)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    arguments = parser.parse_args()

    write_rtl_vector_files(arguments.vectors, arguments.output_dir)
    print(f"Generated RTL simulator vectors: {arguments.output_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
