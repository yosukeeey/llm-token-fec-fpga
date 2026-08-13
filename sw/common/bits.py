"""LSB-first bit packing shared by the Python golden models."""


def validate_bit_length(data: bytes, bit_length: int) -> None:
    """Validate the canonical byte representation of an LSB-first bit string.

    Parameters
    ----------
    data : bytes
        Packed bytes containing the bit string.
    bit_length : int
        Number of valid bits in ``data``.

    Raises
    ------
    ValueError
        If the length is invalid, storage is not minimal, or padding is nonzero.
    """
    if bit_length < 0 or bit_length > len(data) * 8:
        raise ValueError("bit_length must describe bits present in data")
    expected_bytes = (bit_length + 7) // 8
    if len(data) != expected_bytes:
        raise ValueError("data must use the minimal byte length for bit_length")
    if bit_length % 8 and data:
        unused_mask = (0xFF << (bit_length % 8)) & 0xFF
        if data[-1] & unused_mask:
            raise ValueError("unused high bits in the final byte must be zero")


def unpack_bits(data: bytes, bit_length: int) -> list[int]:
    """Unpack bytes in byte-zero, least-significant-bit-first order.

    Parameters
    ----------
    data : bytes
        Canonically packed bytes.
    bit_length : int
        Number of valid bits to unpack.

    Returns
    -------
    list[int]
        Bits represented as integers containing only zero or one.
    """
    validate_bit_length(data, bit_length)
    return [(data[index // 8] >> (index % 8)) & 1 for index in range(bit_length)]


def pack_bits(bits: list[int]) -> bytes:
    """Pack bits in byte-zero, least-significant-bit-first order.

    Parameters
    ----------
    bits : list[int]
        Bit values containing only zero or one.

    Returns
    -------
    bytes
        Minimally sized packed representation with zero-valued padding.

    Raises
    ------
    ValueError
        If a value is not zero or one.
    """
    output = bytearray((len(bits) + 7) // 8)
    for index, bit in enumerate(bits):
        if bit not in (0, 1):
            raise ValueError("bits must contain only 0 or 1")
        output[index // 8] |= bit << (index % 8)
    return bytes(output)


def flip_bits(data: bytes, bit_length: int, positions: list[int]) -> bytes:
    """Flip selected positions in an LSB-first packed bit string.

    Parameters
    ----------
    data : bytes
        Canonically packed bytes.
    bit_length : int
        Number of valid bits in ``data``.
    positions : list[int]
        Zero-based bit positions to invert.

    Returns
    -------
    bytes
        A copy with the requested positions inverted.

    Raises
    ------
    ValueError
        If the input or a bit position is invalid.
    """
    validate_bit_length(data, bit_length)
    output = bytearray(data)
    for position in positions:
        if position < 0 or position >= bit_length:
            raise ValueError("bit position is outside bit_length")
        output[position // 8] ^= 1 << (position % 8)
    return bytes(output)
