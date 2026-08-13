import pytest

from sw.common.bits import flip_bits
from sw.fec.hamming74 import hamming74_decode, hamming74_encode


@pytest.mark.parametrize("nibble", range(16))
def test_hamming74_all_data_words(nibble: int) -> None:
    encoded, bit_length = hamming74_encode(bytes([nibble]), 4)
    decoded = hamming74_decode(encoded, bit_length, 4)
    assert decoded.data == bytes([nibble])
    assert decoded.corrected_codewords == 0


@pytest.mark.parametrize("nibble", range(16))
@pytest.mark.parametrize("error_position", range(7))
def test_hamming74_corrects_each_single_bit_error(
    nibble: int,
    error_position: int,
) -> None:
    encoded, bit_length = hamming74_encode(bytes([nibble]), 4)
    received = flip_bits(encoded, bit_length, [error_position])
    decoded = hamming74_decode(received, bit_length, 4)
    assert decoded.data == bytes([nibble])
    assert decoded.corrected_codewords == 1


def test_hamming74_preserves_partial_final_nibble_length() -> None:
    encoded, bit_length = hamming74_encode(b"\x15", 5)
    decoded = hamming74_decode(encoded, bit_length, 5)
    assert decoded.data == b"\x15"
    assert decoded.bit_length == 5


def test_hamming74_does_not_claim_double_error_detection() -> None:
    encoded, bit_length = hamming74_encode(b"\x0A", 4)
    received = flip_bits(encoded, bit_length, [0, 1])
    decoded = hamming74_decode(received, bit_length, 4)
    assert decoded.corrected_codewords == 1
    assert decoded.data != b"\x0A"
