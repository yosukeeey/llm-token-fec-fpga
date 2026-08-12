"""Reference vector generation and offline result evaluation."""

from .results import EvaluationSummary, evaluate_results
from .schema import CaseResult, TestVector, encode_jsonl, read_jsonl, write_jsonl

__all__ = [
    "CaseResult",
    "EvaluationSummary",
    "TestVector",
    "encode_jsonl",
    "evaluate_results",
    "read_jsonl",
    "write_jsonl",
]
