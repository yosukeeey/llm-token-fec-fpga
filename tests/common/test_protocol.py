import pytest

from sw.common.protocol import (
    Frame,
    FrameCrcError,
    FrameLengthError,
    FrameParser,
    FrameVersionError,
    MessageType,
    parse_frame,
    serialize_frame,
)


def test_frame_v0_known_answer() -> None:
    encoded = serialize_frame(Frame(MessageType.PING))
    assert encoded.hex() == "a55a00010000000026133b6f"
    assert parse_frame(encoded) == Frame(MessageType.PING)


def test_frame_v0_round_trip_with_opaque_payload() -> None:
    frame = Frame(MessageType.TOKEN_REQUEST, b"\x00\xA5\x5A\xFF", flags=0x1234)
    assert parse_frame(serialize_frame(frame)) == frame


def test_incremental_parser_handles_garbage_chunks_and_consecutive_frames() -> None:
    first = Frame(MessageType.PING)
    second = Frame(MessageType.TOKEN_REQUEST, b"abc")
    stream = b"garbage" + serialize_frame(first) + serialize_frame(second)
    parser = FrameParser()
    parsed: list[Frame] = []
    for byte in stream:
        parsed.extend(parser.feed(bytes([byte])))
    assert parsed == [first, second]
    assert parser.buffered_bytes == 0


def test_incremental_parser_recovers_after_crc_error() -> None:
    invalid = bytearray(serialize_frame(Frame(MessageType.PING)))
    invalid[-1] ^= 1
    valid = Frame(MessageType.PONG)
    parser = FrameParser()
    assert parser.feed(bytes(invalid) + serialize_frame(valid)) == [valid]
    assert len(parser.errors) == 1
    assert isinstance(parser.errors[0], FrameCrcError)


@pytest.mark.parametrize(
    ("mutation", "error_type"),
    [
        (lambda frame: frame[:-1], FrameLengthError),
        (lambda frame: frame[:2] + b"\x01" + frame[3:], FrameVersionError),
        (lambda frame: frame[:-1] + bytes([frame[-1] ^ 1]), FrameCrcError),
    ],
)
def test_parse_frame_rejects_invalid_input(mutation, error_type) -> None:  # type: ignore[no-untyped-def]
    encoded = serialize_frame(Frame(MessageType.PING))
    with pytest.raises(error_type):
        parse_frame(mutation(encoded))
