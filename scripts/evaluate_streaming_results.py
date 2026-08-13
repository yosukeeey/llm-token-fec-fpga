"""Validate self-checking streaming RTL result records."""

import argparse
from pathlib import Path

from sw.evaluation import CaseResult, read_jsonl


def main() -> int:
    """Validate pass records emitted by one streaming testbench.

    Returns
    -------
    int
        Zero when the expected unique pass records are present.
    """
    parser = argparse.ArgumentParser()
    parser.add_argument("--results", type=Path, required=True)
    parser.add_argument("--expected-cases", type=int, required=True)
    arguments = parser.parse_args()

    results = read_jsonl(arguments.results, CaseResult)
    case_ids = {result.case_id for result in results}
    valid = (
        len(results) == arguments.expected_cases
        and len(case_ids) == len(results)
        and all(
            result.implementation == "rtl"
            and result.output_hex == "01"
            and result.output_bit_length == 1
            and not result.status
            for result in results
        )
    )
    print(f"total={len(results)} passed={len(results) if valid else 0}")
    return int(not valid)


if __name__ == "__main__":
    raise SystemExit(main())
