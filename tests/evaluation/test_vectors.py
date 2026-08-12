from pathlib import Path

from sw.evaluation import check_vector_files, generate_vector_sets, write_vector_files


def test_vector_case_ids_are_unique() -> None:
    vectors = [
        vector
        for vector_set in generate_vector_sets().values()
        for vector in vector_set
    ]
    case_ids = [vector.case_id for vector in vectors]
    assert len(case_ids) == len(set(case_ids))


def test_vector_generation_is_reproducible() -> None:
    output_dir = Path("build/test/generated_vectors")
    write_vector_files(output_dir)
    assert check_vector_files(output_dir)
