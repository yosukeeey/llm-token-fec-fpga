"""R=1/R=3 repetition-code reference implementation."""

from dataclasses import dataclass

from sw.common.bits import pack_bits, unpack_bits


@dataclass(frozen=True, slots=True)
class RepetitionDecodeResult:
    """Hold decoded bits and the number of non-uniform input groups.

    Attributes
    ----------
    data : bytes
        LSB-first packed decoded data.
    bit_length : int
        Number of valid decoded bits.
    corrected_groups : int
        Number of received groups containing disagreement.
    """

    data: bytes
    bit_length: int
    corrected_groups: int


def _validate_repetition_count(repetition_count: int) -> None:
    if repetition_count not in (1, 3):
        raise ValueError("repetition_count must be 1 or 3")


def repetition_encode(
    data: bytes,
    bit_length: int,
    repetition_count: int,
) -> tuple[bytes, int]:
    """Repeat each input bit consecutively one or three times.

    Parameters
    ----------
    data : bytes
        LSB-first packed input bits.
    bit_length : int
        Number of valid input bits.
    repetition_count : int
        Number of adjacent encoded copies, either one or three.

    Returns
    -------
    tuple[bytes, int]
        Packed encoded data and its valid bit length.

    Raises
    ------
    ValueError
        If the input representation or repetition count is invalid.
    """
    _validate_repetition_count(repetition_count)
    encoded_bits = [
        bit
        for input_bit in unpack_bits(data, bit_length)
        for bit in [input_bit] * repetition_count
    ]
    return pack_bits(encoded_bits), len(encoded_bits)


def repetition_decode(
    encoded: bytes,
    encoded_bit_length: int,
    repetition_count: int,
) -> RepetitionDecodeResult:
    """Decode complete repetition groups using majority voting.

    Parameters
    ----------
    encoded : bytes
        LSB-first packed repetition groups.
    encoded_bit_length : int
        Number of valid encoded bits.
    repetition_count : int
        Group size, either one or three.

    Returns
    -------
    RepetitionDecodeResult
        Decoded bits and count of groups that contained disagreement.

    Raises
    ------
    ValueError
        If the input does not contain complete supported groups.

    Notes
    -----
    Group disagreement does not distinguish one-bit from two-bit corruption.
    """
    _validate_repetition_count(repetition_count)
    if encoded_bit_length % repetition_count:
        raise ValueError("encoded bit length must contain complete repetition groups")

    encoded_bits = unpack_bits(encoded, encoded_bit_length)
    decoded_bits: list[int] = []
    corrected_groups = 0
    for offset in range(0, encoded_bit_length, repetition_count):
        group = encoded_bits[offset : offset + repetition_count]
        decoded_bit = int(sum(group) > repetition_count // 2)
        decoded_bits.append(decoded_bit)
        corrected_groups += int(any(bit != decoded_bit for bit in group))

    return RepetitionDecodeResult(
        data=pack_bits(decoded_bits),
        bit_length=len(decoded_bits),
        corrected_groups=corrected_groups,
    )
