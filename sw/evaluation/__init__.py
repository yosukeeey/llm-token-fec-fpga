"""Reference vector generation and offline result evaluation."""

from .results import EvaluationSummary, evaluate_results
from .rtl_vectors import write_rtl_vector_files
from .schema import CaseResult, TestVector, encode_jsonl, read_jsonl, write_jsonl
from .vectors import check_vector_files, generate_vector_sets, write_vector_files

__all__ = [
    "CaseResult",
    "EvaluationSummary",
    "TestVector",
    "check_vector_files",
    "encode_jsonl",
    "evaluate_results",
    "generate_vector_sets",
    "read_jsonl",
    "write_jsonl",
    "write_rtl_vector_files",
    "write_vector_files",
]
