"""Convert versioned JSONL vectors to simple simulator input records."""

from pathlib import Path

from .schema import TestVector, read_jsonl


def _hex_value(value: str) -> str:
    # The simulator uses whitespace-delimited tokens, so an empty hex field
    # needs an explicit zero placeholder. Its separate bit length remains zero.
    return value or "0"


def _packed_vector_value(value: str) -> str:
    # JSONL hex preserves byte order, while SystemVerilog %h scans a packed
    # vector as one big-endian integer. Reversing bytes preserves bit index 0.
    return bytes.fromhex(value)[::-1].hex() if value else "0"


def _corrected(vector: TestVector) -> int:
    # Testbenches use an integer because their input format intentionally has
    # no JSON parsing or implementation-specific string handling.
    return int("FEC_CORRECTED" in vector.expected_status)


def _byte_length(field_name: str, bit_length: int) -> int:
    if bit_length % 8:
        raise ValueError(f"{field_name} bit length must be byte-aligned")
    return bit_length // 8


def write_rtl_vector_files(vector_dir: Path, output_dir: Path) -> None:
    """Write whitespace-delimited records for the RTL testbenches.

    Parameters
    ----------
    vector_dir : Path
        Directory containing the fixed reference JSONL files.
    output_dir : Path
        Directory that receives simulator-specific text files.

    Notes
    -----
    JSONL remains the language-neutral source of truth. These derived files
    deliberately avoid requiring a JSON parser inside a testbench.
    """
    output_dir.mkdir(parents=True, exist_ok=True)

    parity = read_jsonl(vector_dir / "parity.jsonl", TestVector)
    parity_lines = [str(len(parity))]
    parity_lines.extend(
        f"{vector.case_id} {vector.input_bit_length} "
        f"{_hex_value(vector.input_hex)} {_hex_value(vector.decoded_hex)}"
        for vector in parity
    )
    (output_dir / "parity.txt").write_text(
        "\n".join(parity_lines) + "\n", encoding="ascii"
    )

    repetition = read_jsonl(vector_dir / "repetition.jsonl", TestVector)
    repetition_lines = [str(len(repetition))]
    repetition_lines.extend(
        f"{vector.case_id} {vector.parameters['repetition_count']} "
        f"{_packed_vector_value(vector.input_hex)} "
        f"{_packed_vector_value(vector.encoded_hex)} "
        f"{_packed_vector_value(vector.received_hex)} "
        f"{_packed_vector_value(vector.decoded_hex)} "
        f"{_corrected(vector)}"
        for vector in repetition
    )
    (output_dir / "repetition.txt").write_text(
        "\n".join(repetition_lines) + "\n", encoding="ascii"
    )

    hamming = read_jsonl(vector_dir / "hamming74.jsonl", TestVector)
    hamming_lines = [str(len(hamming))]
    for vector in hamming:
        syndrome = (
            vector.error_bit_positions[0] + 1 if vector.error_bit_positions else 0
        )
        hamming_lines.append(
            f"{vector.case_id} {_hex_value(vector.input_hex)} "
            f"{_hex_value(vector.encoded_hex)} {_hex_value(vector.received_hex)} "
            f"{_hex_value(vector.decoded_hex)} {syndrome:x} {_corrected(vector)}"
        )
    (output_dir / "hamming74.txt").write_text(
        "\n".join(hamming_lines) + "\n", encoding="ascii"
    )

    protocol = read_jsonl(vector_dir / "protocol.jsonl", TestVector)
    protocol_lines = [str(len(protocol))]
    for vector in protocol:
        frame_length = _byte_length("frame", vector.encoded_bit_length)
        payload_length = _byte_length("payload", vector.input_bit_length)
        protocol_lines.append(
            f"{vector.case_id} {frame_length} "
            f"{_packed_vector_value(vector.encoded_hex)} "
            f"{vector.parameters['message_type']} {vector.parameters['flags']} "
            f"{payload_length} {_packed_vector_value(vector.input_hex)}"
        )
    (output_dir / "protocol.txt").write_text(
        "\n".join(protocol_lines) + "\n", encoding="ascii"
    )

    protocol_pipeline = read_jsonl(
        vector_dir / "protocol_pipeline.jsonl", TestVector
    )
    protocol_pipeline_lines = [str(len(protocol_pipeline))]
    for vector in protocol_pipeline:
        request_length = _byte_length("request", vector.encoded_bit_length)
        response_length = _byte_length("response", vector.decoded_bit_length)
        protocol_pipeline_lines.append(
            f"{vector.case_id} {request_length} "
            f"{_packed_vector_value(vector.encoded_hex)} {response_length} "
            f"{_packed_vector_value(vector.decoded_hex)}"
        )
    (output_dir / "protocol_pipeline.txt").write_text(
        "\n".join(protocol_pipeline_lines) + "\n", encoding="ascii"
    )
