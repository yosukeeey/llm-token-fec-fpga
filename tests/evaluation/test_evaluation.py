from pathlib import Path

import pytest

from sw.evaluation import (
    CaseResult,
    evaluate_results,
    read_jsonl,
    write_jsonl,
)
from sw.evaluation import TestVector as ReferenceTestVector


def _vector(case_id: str = "case-1") -> ReferenceTestVector:
    return ReferenceTestVector(
        case_id=case_id,
        algorithm="test",
        input_hex="a5",
        input_bit_length=8,
        encoded_hex="a5",
        encoded_bit_length=8,
        received_hex="a5",
        decoded_hex="a5",
        decoded_bit_length=8,
    )


def test_jsonl_round_trip() -> None:
    path = Path("build/test/evaluation/vectors.jsonl")
    write_jsonl(path, [_vector()])
    assert read_jsonl(path, ReferenceTestVector) == [_vector()]


def test_schema_rejects_nonzero_padding() -> None:
    with pytest.raises(ValueError, match="unused high bits"):
        ReferenceTestVector(
            case_id="invalid",
            algorithm="test",
            input_hex="ff",
            input_bit_length=1,
            encoded_hex="00",
            encoded_bit_length=1,
            received_hex="00",
            decoded_hex="00",
            decoded_bit_length=1,
        )


def test_evaluate_results_reports_pass_and_failure() -> None:
    vectors = [_vector("pass"), _vector("fail")]
    results = [
        CaseResult("pass", "cpp", "a5", 8),
        CaseResult("fail", "rtl", "00", 8),
    ]
    summary = evaluate_results(vectors, results)
    assert summary.total == 2
    assert summary.passed == 1
    assert summary.failed == 1
    assert summary.failures[0].reason == "output_hex mismatch"
