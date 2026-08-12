import pytest

from sw.common.bits import flip_bits
from sw.fec.repetition import repetition_decode, repetition_encode


@pytest.mark.parametrize("repetition_count", [1, 3])
def test_repetition_round_trip(repetition_count: int) -> None:
    encoded, bit_length = repetition_encode(b"\xA5", 8, repetition_count)
    decoded = repetition_decode(encoded, bit_length, repetition_count)
    assert decoded.data == b"\xA5"
    assert decoded.bit_length == 8
    assert decoded.corrected_groups == 0


@pytest.mark.parametrize("error_position", range(3))
def test_repetition_r3_corrects_each_single_error(error_position: int) -> None:
    encoded, bit_length = repetition_encode(b"\x01", 1, 3)
    received = flip_bits(encoded, bit_length, [error_position])
    decoded = repetition_decode(received, bit_length, 3)
    assert decoded.data == b"\x01"
    assert decoded.corrected_groups == 1


def test_repetition_rejects_invalid_count() -> None:
    with pytest.raises(ValueError, match="1 or 3"):
        repetition_encode(b"\x01", 1, 2)


def test_repetition_does_not_claim_double_error_detection() -> None:
    encoded, bit_length = repetition_encode(b"\x01", 1, 3)
    received = flip_bits(encoded, bit_length, [0, 1])
    decoded = repetition_decode(received, bit_length, 3)

    assert decoded.data == b"\x00"
    assert decoded.corrected_groups == 1
