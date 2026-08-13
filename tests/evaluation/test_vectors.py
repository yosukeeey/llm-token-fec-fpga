from pathlib import Path

from sw.evaluation import TestVector as ReferenceTestVector
from sw.evaluation import (
    check_vector_files,
    generate_vector_sets,
    read_jsonl,
    write_vector_files,
)


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


def test_protocol_pipeline_vectors_contain_complete_frames() -> None:
    pipeline = {
        vector.case_id: vector
        for vector in generate_vector_sets()["protocol_pipeline"]
    }
    protocol = {
        vector.case_id: vector
        for vector in read_jsonl(
            Path("datasets/test_vectors/protocol_v0/protocol.jsonl"),
            ReferenceTestVector,
        )
    }

    ping = pipeline["pipeline-v0-ping-pong"]
    ping_request = protocol["frame-v0-ping"].encoded_hex
    assert ping.input_hex == ping.encoded_hex == ping.received_hex == ping_request
    assert ping.decoded_hex == "a55a000200000000d2a30827"
    assert ping.input_bit_length == ping.encoded_bit_length == len(ping_request) * 4
    assert ping.decoded_bit_length == len(ping.decoded_hex) * 4
    assert ping.parameters == {"corrected_count": 0}
    assert ping.expected_status == []

    token = pipeline["pipeline-v0-hamming-token"]
    token_request = protocol["frame-v0-token-request-v1"].encoded_hex
    token_response = protocol["frame-v0-token-result-v1"].encoded_hex
    assert token.input_hex == token.encoded_hex == token.received_hex == token_request
    assert token.decoded_hex == token_response
    assert token.input_bit_length == token.encoded_bit_length == len(token_request) * 4
    assert token.decoded_bit_length == len(token_response) * 4
    assert token.parameters == {"corrected_count": 1}
    assert token.expected_status == ["FEC_CORRECTED"]


def test_protocol_vectors_cover_the_maximum_opaque_payload() -> None:
    vectors = {
        vector.case_id: vector for vector in generate_vector_sets()["protocol"]
    }
    maximum = vectors["frame-v0-max-payload"]

    assert maximum.input_hex == (bytes(range(256)) * 4).hex()
    assert maximum.input_bit_length == 1024 * 8
    assert maximum.encoded_bit_length == (1024 + 12) * 8
    assert maximum.parameters == {"message_type": 0x7E, "flags": 0xA55A}
