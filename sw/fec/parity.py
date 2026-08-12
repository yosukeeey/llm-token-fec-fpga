"""Even parity reference functions."""

from sw.common.bits import unpack_bits


def even_parity_bit(data: bytes, bit_length: int) -> int:
    """Calculate the bit that makes the protected input have even parity.

    Parameters
    ----------
    data : bytes
        LSB-first packed input bits.
    bit_length : int
        Number of valid input bits.

    Returns
    -------
    int
        Zero or one even-parity bit.
    """
    return sum(unpack_bits(data, bit_length)) & 1


def has_even_parity(data: bytes, bit_length: int, parity_bit: int) -> bool:
    """Check whether input bits and their parity bit have even parity.

    Parameters
    ----------
    data : bytes
        LSB-first packed input bits.
    bit_length : int
        Number of valid input bits.
    parity_bit : int
        Received parity bit, either zero or one.

    Returns
    -------
    bool
        True when the total number of ones is even.

    Raises
    ------
    ValueError
        If ``parity_bit`` is not zero or one.
    """
    if parity_bit not in (0, 1):
        raise ValueError("parity_bit must be 0 or 1")
    return (sum(unpack_bits(data, bit_length)) + parity_bit) % 2 == 0
