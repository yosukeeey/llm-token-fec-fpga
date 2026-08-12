"""Deterministic golden-vector construction."""

from collections.abc import Callable
from pathlib import Path

from sw.common.bits import flip_bits, pack_bits
from sw.common.crc32c import crc32c
from sw.common.protocol import Frame, MessageType, parse_frame, serialize_frame
from sw.common.types import (
    ChannelFlag,
    ChannelState,
    ExtensionTlv,
    ProtectionMode,
    ProtectionRequest,
    ResultFlag,
    ResultStatus,
    TokenFlag,
    TokenRecord,
    TokenRequest,
    TokenResult,
)
from sw.fec.hamming74 import hamming74_decode, hamming74_encode
from sw.fec.parity import even_parity_bit
from sw.fec.repetition import repetition_decode, repetition_encode

from .schema import TestVector, encode_jsonl, write_jsonl


def _crc_vectors() -> list[TestVector]:
    vectors: list[TestVector] = []
    for case_id, data in (("crc32c-empty", b""), ("crc32c-check", b"123456789")):
        checksum = crc32c(data).to_bytes(4, "little")
        vectors.append(
            TestVector(
                case_id=case_id,
                algorithm="crc32c",
                input_hex=data.hex(),
                input_bit_length=len(data) * 8,
                encoded_hex=checksum.hex(),
                encoded_bit_length=32,
                received_hex=checksum.hex(),
                decoded_hex=checksum.hex(),
                decoded_bit_length=32,
            )
        )
    return vectors


def _parity_vectors() -> list[TestVector]:
    vectors: list[TestVector] = []
    for case_id, data, bit_length in (
        ("parity-empty", b"", 0),
        ("parity-a5", b"\xA5", 8),
        ("parity-one", b"\x01", 1),
    ):
        parity = even_parity_bit(data, bit_length)
        parity_data = pack_bits([parity])
        vectors.append(
            TestVector(
                case_id=case_id,
                algorithm="even_parity",
                input_hex=data.hex(),
                input_bit_length=bit_length,
                encoded_hex=parity_data.hex(),
                encoded_bit_length=1,
                received_hex=parity_data.hex(),
                decoded_hex=parity_data.hex(),
                decoded_bit_length=1,
            )
        )
    return vectors


def _repetition_vectors() -> list[TestVector]:
    vectors: list[TestVector] = []
    data = b"\xA5"
    for repetition_count, errors in (
        (1, []),
        (3, []),
        (3, [2]),
        (3, [2, 5]),
        (3, [0, 1]),
    ):
        encoded, encoded_bit_length = repetition_encode(data, 8, repetition_count)
        received = flip_bits(encoded, encoded_bit_length, errors)
        decoded = repetition_decode(received, encoded_bit_length, repetition_count)
        suffix = "none" if not errors else "-".join(str(error) for error in errors)
        vectors.append(
            TestVector(
                case_id=f"repetition-r{repetition_count}-errors-{suffix}",
                algorithm="repetition",
                parameters={"repetition_count": repetition_count},
                input_hex=data.hex(),
                input_bit_length=8,
                encoded_hex=encoded.hex(),
                encoded_bit_length=encoded_bit_length,
                error_bit_positions=errors,
                received_hex=received.hex(),
                decoded_hex=decoded.data.hex(),
                decoded_bit_length=decoded.bit_length,
                expected_status=["FEC_CORRECTED"] if decoded.corrected_groups else [],
            )
        )
    return vectors


def _hamming_vectors() -> list[TestVector]:
    vectors: list[TestVector] = []
    for nibble in range(16):
        data = bytes([nibble])
        encoded, encoded_bit_length = hamming74_encode(data, 4)
        for error_position in [None, *range(7)]:
            errors = [] if error_position is None else [error_position]
            received = flip_bits(encoded, encoded_bit_length, errors)
            decoded = hamming74_decode(received, encoded_bit_length, 4)
            suffix = "none" if error_position is None else str(error_position)
            vectors.append(
                TestVector(
                    case_id=f"hamming74-{nibble:x}-error-{suffix}",
                    algorithm="hamming74",
                    input_hex=data.hex(),
                    input_bit_length=4,
                    encoded_hex=encoded.hex(),
                    encoded_bit_length=encoded_bit_length,
                    error_bit_positions=errors,
                    received_hex=received.hex(),
                    decoded_hex=decoded.data.hex(),
                    decoded_bit_length=decoded.bit_length,
                    expected_status=["FEC_CORRECTED"] if errors else [],
                )
            )
    return vectors


def _protocol_vectors() -> list[TestVector]:
    token = TokenRecord(
        stream_id=0x11223344,
        sequence=0xFFFFFFFF,
        token_id=0x55667788,
        generated_time_us=1_000,
        deadline_us=2_000,
        flags=TokenFlag.GENERATED_TIME_VALID | TokenFlag.DEADLINE_VALID,
        extensions=(ExtensionTlv(0x80, b"\xAA\x55"),),
    )
    request_payload = TokenRequest(
        token,
        ProtectionRequest(
            ProtectionMode.HAMMING_7_4,
            block_length_bits=len(token.pack()) * 8,
            code_rate_num=4,
            code_rate_den=7,
        ),
        ChannelState(0x8000, ChannelFlag.QUALITY_VALID),
    ).pack()
    result_payload = TokenResult(
        token,
        ResultStatus(ResultFlag.FEC_CORRECTED, corrected_count=1),
    ).pack()
    frames = (
        ("frame-v0-ping", Frame(MessageType.PING)),
        (
            "frame-v0-token-request-v1",
            Frame(MessageType.TOKEN_REQUEST, payload=request_payload),
        ),
        (
            "frame-v0-token-result-v1",
            Frame(MessageType.TOKEN_RESULT, payload=result_payload),
        ),
    )
    vectors: list[TestVector] = []
    for case_id, frame in frames:
        encoded = serialize_frame(frame)
        decoded = parse_frame(encoded)
        vectors.append(
            TestVector(
                case_id=case_id,
                algorithm="frame_v0",
                parameters={
                    "message_type": decoded.message_type,
                    "flags": decoded.flags,
                },
                input_hex=frame.payload.hex(),
                input_bit_length=len(frame.payload) * 8,
                encoded_hex=encoded.hex(),
                encoded_bit_length=len(encoded) * 8,
                received_hex=encoded.hex(),
                decoded_hex=decoded.payload.hex(),
                decoded_bit_length=len(decoded.payload) * 8,
            )
        )
    return vectors


def generate_vector_sets() -> dict[str, list[TestVector]]:
    """Build every deterministic reference vector set.

    Returns
    -------
    dict[str, list[TestVector]]
        Vector lists keyed by output filename stem.
    """
    generators: dict[str, Callable[[], list[TestVector]]] = {
        "crc32c": _crc_vectors,
        "parity": _parity_vectors,
        "repetition": _repetition_vectors,
        "hamming74": _hamming_vectors,
        "protocol": _protocol_vectors,
    }
    return {name: generator() for name, generator in generators.items()}


def write_vector_files(output_dir: Path) -> None:
    """Write all deterministic reference vector sets.

    Parameters
    ----------
    output_dir : Path
        Directory that receives one JSONL file per algorithm.
    """
    for name, vectors in generate_vector_sets().items():
        write_jsonl(output_dir / f"{name}.jsonl", vectors)


def check_vector_files(output_dir: Path) -> bool:
    """Check whether stored JSONL files equal freshly generated vectors.

    Parameters
    ----------
    output_dir : Path
        Directory containing the tracked reference JSONL files.

    Returns
    -------
    bool
        True only when filenames and contents match exactly.
    """
    vector_sets = generate_vector_sets()
    expected_names = {f"{name}.jsonl" for name in vector_sets}
    actual_names = {path.name for path in output_dir.glob("*.jsonl")}
    if actual_names != expected_names:
        return False
    return all(
        (output_dir / f"{name}.jsonl").read_bytes() == encode_jsonl(vectors)
        for name, vectors in vector_sets.items()
    )
