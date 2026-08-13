from dataclasses import replace
from pathlib import Path

import pytest

from sw.evaluation import (
    TestVector as ReferenceTestVector,
)
from sw.evaluation import read_jsonl, write_jsonl, write_rtl_vector_files


def test_rtl_vectors_are_derived_from_fixed_jsonl() -> None:
    output_dir = Path("build/test/rtl_vectors")
    write_rtl_vector_files(Path("datasets/test_vectors/protocol_v0"), output_dir)

    assert (output_dir / "parity.txt").read_text(encoding="ascii").splitlines()[
        0
    ] == "3"
    assert (output_dir / "repetition.txt").read_text(encoding="ascii").splitlines()[
        0
    ] == "5"
    assert " a5 e381c7 e381c7 a5 0" in (output_dir / "repetition.txt").read_text(
        encoding="ascii"
    )
    assert (output_dir / "hamming74.txt").read_text(encoding="ascii").splitlines()[
        0
    ] == "128"

    protocol_lines = (
        (output_dir / "protocol.txt").read_text(encoding="ascii").splitlines()
    )
    assert protocol_lines[0] == "3"
    assert protocol_lines[1] == "frame-v0-ping 12 6f3b13260000000001005aa5 1 0 0 0"

    token_fields = protocol_lines[2].split()
    assert token_fields[0:2] == ["frame-v0-token-request-v1", "76"]
    assert token_fields[3:6] == ["16", "0", "64"]
    assert bytes.fromhex(token_fields[2])[::-1][:8] == bytes.fromhex("a55a001000004000")
    assert bytes.fromhex(token_fields[6])[::-1][:4] == bytes.fromhex("01032800")

    pipeline_lines = (
        (output_dir / "protocol_pipeline.txt")
        .read_text(encoding="ascii")
        .splitlines()
    )
    assert pipeline_lines[0] == "2"
    assert pipeline_lines[1] == (
        "pipeline-v0-ping-pong 12 6f3b13260000000001005aa5 "
        "12 2708a3d20000000002005aa5"
    )

    pipeline = read_jsonl(
        Path("datasets/test_vectors/protocol_v0/protocol_pipeline.jsonl"),
        ReferenceTestVector,
    )[1]
    pipeline_fields = pipeline_lines[2].split()
    assert pipeline_fields[0] == pipeline.case_id
    assert int(pipeline_fields[1]) == pipeline.encoded_bit_length // 8
    assert bytes.fromhex(pipeline_fields[2])[::-1].hex() == pipeline.encoded_hex
    assert int(pipeline_fields[3]) == pipeline.decoded_bit_length // 8
    assert bytes.fromhex(pipeline_fields[4])[::-1].hex() == pipeline.decoded_hex


@pytest.mark.parametrize(
    ("length_field", "expected_name"),
    [("encoded_bit_length", "frame"), ("input_bit_length", "payload")],
)
def test_protocol_vectors_require_byte_alignment(
    length_field: str,
    expected_name: str,
) -> None:
    vector_dir = Path("build/test") / f"rtl_vectors_{expected_name}" / "vectors"
    output_dir = Path("build/test") / f"rtl_vectors_{expected_name}" / "rtl"
    for name in ("parity", "repetition", "hamming74"):
        write_jsonl(vector_dir / f"{name}.jsonl", [])
    write_jsonl(
        vector_dir / "protocol_pipeline.jsonl",
        read_jsonl(
            Path("datasets/test_vectors/protocol_v0/protocol_pipeline.jsonl"),
            ReferenceTestVector,
        ),
    )

    source = read_jsonl(
        Path("datasets/test_vectors/protocol_v0/protocol.jsonl"), ReferenceTestVector
    )[0]
    if length_field == "encoded_bit_length":
        invalid = replace(source, encoded_bit_length=source.encoded_bit_length - 1)
    else:
        invalid = replace(source, input_hex="00", input_bit_length=7)
    write_jsonl(vector_dir / "protocol.jsonl", [invalid])

    with pytest.raises(
        ValueError, match=rf"{expected_name} bit length must be byte-aligned"
    ):
        write_rtl_vector_files(vector_dir, output_dir)


@pytest.mark.parametrize(
    ("length_field", "expected_name"),
    [("encoded_bit_length", "request"), ("decoded_bit_length", "response")],
)
def test_protocol_pipeline_vectors_require_byte_alignment(
    length_field: str,
    expected_name: str,
) -> None:
    vector_dir = Path("build/test") / f"rtl_pipeline_{expected_name}" / "vectors"
    output_dir = Path("build/test") / f"rtl_pipeline_{expected_name}" / "rtl"
    fixed_dir = Path("datasets/test_vectors/protocol_v0")
    for name in ("parity", "repetition", "hamming74", "protocol"):
        write_jsonl(
            vector_dir / f"{name}.jsonl",
            read_jsonl(fixed_dir / f"{name}.jsonl", ReferenceTestVector),
        )

    source = read_jsonl(
        fixed_dir / "protocol_pipeline.jsonl", ReferenceTestVector
    )[0]
    if length_field == "encoded_bit_length":
        invalid = replace(
            source,
            encoded_hex="00",
            encoded_bit_length=7,
            received_hex="00",
        )
    else:
        invalid = replace(source, decoded_hex="00", decoded_bit_length=7)
    write_jsonl(vector_dir / "protocol_pipeline.jsonl", [invalid])

    with pytest.raises(
        ValueError, match=rf"{expected_name} bit length must be byte-aligned"
    ):
        write_rtl_vector_files(vector_dir, output_dir)
