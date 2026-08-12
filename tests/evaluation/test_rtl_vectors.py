from pathlib import Path

from sw.evaluation import write_rtl_vector_files


def test_rtl_vectors_are_derived_from_fixed_jsonl() -> None:
    output_dir = Path("build/test/rtl_vectors")
    write_rtl_vector_files(Path("datasets/test_vectors/protocol_v0"), output_dir)

    assert (output_dir / "parity.txt").read_text(encoding="ascii").splitlines()[0] == "3"
    assert (
        output_dir / "repetition.txt"
    ).read_text(encoding="ascii").splitlines()[0] == "5"
    assert " a5 e381c7 e381c7 a5 0" in (
        output_dir / "repetition.txt"
    ).read_text(encoding="ascii")
    assert (
        output_dir / "hamming74.txt"
    ).read_text(encoding="ascii").splitlines()[0] == "128"
