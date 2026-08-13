"""Compare C++/RTL/FPGA JSONL results with fixed reference vectors."""

import argparse
from pathlib import Path

from sw.evaluation import CaseResult, TestVector, evaluate_results, read_jsonl


def main() -> int:
    """Compare one implementation result file with reference vectors.

    Returns
    -------
    int
        Zero when all cases match, otherwise one.
    """
    parser = argparse.ArgumentParser()
    parser.add_argument("--vectors", type=Path, required=True)
    parser.add_argument("--results", type=Path, required=True)
    arguments = parser.parse_args()

    vectors = read_jsonl(arguments.vectors, TestVector)
    results = read_jsonl(arguments.results, CaseResult)
    summary = evaluate_results(vectors, results)

    print(f"total={summary.total} passed={summary.passed} failed={summary.failed}")
    for failure in summary.failures:
        print(f"FAIL {failure.case_id}: {failure.reason}")
    return int(summary.failed > 0)


if __name__ == "__main__":
    raise SystemExit(main())
