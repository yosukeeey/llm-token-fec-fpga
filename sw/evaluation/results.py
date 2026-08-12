"""Offline comparison of implementation results against fixed vectors."""

from dataclasses import dataclass

from .schema import CaseResult, TestVector


@dataclass(frozen=True, slots=True)
class EvaluationFailure:
    """Describe one implementation result mismatch.

    Attributes
    ----------
    case_id : str
        Identifier of the mismatched case.
    reason : str
        Short description of the mismatch.
    """

    case_id: str
    reason: str


@dataclass(frozen=True, slots=True)
class EvaluationSummary:
    """Summarize comparison of one result set with reference vectors.

    Attributes
    ----------
    total : int
        Number of expected reference cases.
    passed : int
        Number of matching implementation results.
    failures : tuple[EvaluationFailure, ...]
        Stable, case-sorted mismatch descriptions.
    """

    total: int
    passed: int
    failures: tuple[EvaluationFailure, ...]

    @property
    def failed(self) -> int:
        """Return the number of failed cases.

        Returns
        -------
        int
            Number of mismatch descriptions in ``failures``.
        """
        return len(self.failures)


def evaluate_results(
    vectors: list[TestVector],
    results: list[CaseResult],
) -> EvaluationSummary:
    """Compare implementation results with fixed reference vectors.

    Parameters
    ----------
    vectors : list[TestVector]
        Expected cases indexed by unique case identifiers.
    results : list[CaseResult]
        Actual implementation outputs using the same identifiers.

    Returns
    -------
    EvaluationSummary
        Counts and stable, case-sorted mismatch descriptions.

    Raises
    ------
    ValueError
        If either input contains duplicate case identifiers.
    """
    vectors_by_id = {vector.case_id: vector for vector in vectors}
    if len(vectors_by_id) != len(vectors):
        raise ValueError("vector case_id values must be unique")

    results_by_id = {result.case_id: result for result in results}
    if len(results_by_id) != len(results):
        raise ValueError("result case_id values must be unique")

    failures: list[EvaluationFailure] = []
    for case_id, vector in vectors_by_id.items():
        result = results_by_id.get(case_id)
        if result is None:
            failures.append(EvaluationFailure(case_id, "missing result"))
            continue
        if result.output_hex != vector.decoded_hex:
            failures.append(EvaluationFailure(case_id, "output_hex mismatch"))
            continue
        if result.output_bit_length != vector.decoded_bit_length:
            failures.append(EvaluationFailure(case_id, "output_bit_length mismatch"))
            continue
        if result.status != vector.expected_status:
            failures.append(EvaluationFailure(case_id, "status mismatch"))

    for case_id in results_by_id.keys() - vectors_by_id.keys():
        failures.append(EvaluationFailure(case_id, "unknown result case_id"))

    failures.sort(key=lambda failure: failure.case_id)
    return EvaluationSummary(
        total=len(vectors),
        passed=len(vectors) - sum(
            failure.case_id in vectors_by_id for failure in failures
        ),
        failures=tuple(failures),
    )
