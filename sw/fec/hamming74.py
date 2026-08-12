"""LSB-first systematic Hamming(7,4) SEC reference implementation."""

from dataclasses import dataclass

from sw.common.bits import pack_bits, unpack_bits


@dataclass(frozen=True, slots=True)
class HammingDecodeResult:
    """Hold decoded data and the number of nonzero syndromes.

    Attributes
    ----------
    data : bytes
        LSB-first packed decoded data.
    bit_length : int
        Number of valid decoded bits.
    corrected_codewords : int
        Number of codewords whose syndrome was nonzero.
    """

    data: bytes
    bit_length: int
    corrected_codewords: int


def _encode_nibble(data_bits: list[int]) -> list[int]:
    d0, d1, d2, d3 = data_bits
    p1 = d0 ^ d1 ^ d3
    p2 = d0 ^ d2 ^ d3
    p4 = d1 ^ d2 ^ d3
    return [p1, p2, d0, p4, d1, d2, d3]


def hamming74_encode(data: bytes, bit_length: int) -> tuple[bytes, int]:
    """Encode LSB-first data nibbles as Hamming(7,4) codewords.

    Parameters
    ----------
    data : bytes
        LSB-first packed input bits.
    bit_length : int
        Number of valid input bits.

    Returns
    -------
    tuple[bytes, int]
        Packed codewords and their valid bit length.

    Notes
    -----
    The final nibble is zero padded. Codeword positions are
    ``p1, p2, d0, p4, d1, d2, d3`` from bit zero upward.
    """
    input_bits = unpack_bits(data, bit_length)
    encoded_bits: list[int] = []
    for offset in range(0, bit_length, 4):
        nibble = input_bits[offset : offset + 4]
        nibble.extend([0] * (4 - len(nibble)))
        encoded_bits.extend(_encode_nibble(nibble))
    return pack_bits(encoded_bits), len(encoded_bits)


def hamming74_decode(
    encoded: bytes,
    encoded_bit_length: int,
    output_bit_length: int,
) -> HammingDecodeResult:
    """Correct and decode complete Hamming(7,4) codewords.

    Parameters
    ----------
    encoded : bytes
        LSB-first packed codewords.
    encoded_bit_length : int
        Number of valid encoded bits and a multiple of seven.
    output_bit_length : int
        Original valid data length after removing nibble padding.

    Returns
    -------
    HammingDecodeResult
        Decoded data and count of codewords with nonzero syndromes.

    Raises
    ------
    ValueError
        If codewords are incomplete or the requested output is too long.

    Notes
    -----
    Hamming(7,4) is SEC, not DED. A nonzero syndrome does not prove that the
    received word contained exactly one corrupt bit.
    """
    if encoded_bit_length % 7:
        raise ValueError("encoded bit length must contain complete Hamming codewords")
    if output_bit_length < 0 or output_bit_length > (encoded_bit_length // 7) * 4:
        raise ValueError("output_bit_length does not fit the encoded codewords")

    encoded_bits = unpack_bits(encoded, encoded_bit_length)
    decoded_bits: list[int] = []
    corrected_codewords = 0
    for offset in range(0, encoded_bit_length, 7):
        codeword = encoded_bits[offset : offset + 7]
        s1 = codeword[0] ^ codeword[2] ^ codeword[4] ^ codeword[6]
        s2 = codeword[1] ^ codeword[2] ^ codeword[5] ^ codeword[6]
        s4 = codeword[3] ^ codeword[4] ^ codeword[5] ^ codeword[6]
        syndrome = s1 | (s2 << 1) | (s4 << 2)
        if syndrome:
            codeword[syndrome - 1] ^= 1
            corrected_codewords += 1
        decoded_bits.extend([codeword[2], codeword[4], codeword[5], codeword[6]])

    decoded_bits = decoded_bits[:output_bit_length]
    return HammingDecodeResult(
        data=pack_bits(decoded_bits),
        bit_length=output_bit_length,
        corrected_codewords=corrected_codewords,
    )
