import pytest

from sw.common.bits import flip_bits, pack_bits, unpack_bits


def test_lsb_first_pack_round_trip() -> None:
    bits = [1, 0, 1, 0, 0, 1, 0, 1]
    assert pack_bits(bits) == b"\xA5"
    assert unpack_bits(b"\xA5", 8) == bits


def test_rejects_nonzero_padding_bits() -> None:
    with pytest.raises(ValueError, match="unused high bits"):
        unpack_bits(b"\xFF", 4)


def test_flip_bits() -> None:
    assert flip_bits(b"\x00\x00", 9, [0, 8]) == b"\x01\x01"
