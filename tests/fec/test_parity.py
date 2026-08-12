import pytest

from sw.fec.parity import even_parity_bit, has_even_parity


@pytest.mark.parametrize(
    ("data", "bit_length", "expected"),
    [(b"", 0, 0), (b"\xA5", 8, 0), (b"\x01", 1, 1)],
)
def test_even_parity(data: bytes, bit_length: int, expected: int) -> None:
    parity = even_parity_bit(data, bit_length)
    assert parity == expected
    assert has_even_parity(data, bit_length, parity)
