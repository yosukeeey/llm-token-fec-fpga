"""Seeded binary symmetric channel over LSB-first packed bit strings."""

from dataclasses import dataclass
from random import Random

from sw.common.bits import flip_bits, validate_bit_length


@dataclass(frozen=True)
class ChannelResult:
    """One transmission through the channel.

    Attributes
    ----------
    data : bytes
        Received bytes after the flips were applied.
    bit_length : int
        Number of valid bits in ``data``.
    flipped_positions : tuple[int, ...]
        Zero-based positions inverted by the channel, in ascending order.
    """

    data: bytes
    bit_length: int
    flipped_positions: tuple[int, ...]

    @property
    def bit_errors(self) -> int:
        """Return the number of inverted positions."""
        return len(self.flipped_positions)


def transmit(
    data: bytes,
    bit_length: int,
    *,
    flip_probability: float,
    seed: int,
) -> ChannelResult:
    """Send one bit string through a binary symmetric channel.

    Each bit is inverted independently with the same probability. The same seed
    and the same inputs always invert the same positions.

    Parameters
    ----------
    data : bytes
        Canonically packed bytes to transmit.
    bit_length : int
        Number of valid bits in ``data``.
    flip_probability : float
        Probability of inverting one bit, between zero and one inclusive.
    seed : int
        Seed selecting the error pattern.

    Returns
    -------
    ChannelResult
        Received bits and the positions the channel inverted.

    Raises
    ------
    ValueError
        If the packed representation or the probability is invalid.
    """
    validate_bit_length(data, bit_length)
    if not 0.0 <= flip_probability <= 1.0:
        raise ValueError("flip_probability must be between 0 and 1")

    generator = Random(seed)
    positions = [
        position
        for position in range(bit_length)
        if generator.random() < flip_probability
    ]
    return ChannelResult(
        data=flip_bits(data, bit_length, positions),
        bit_length=bit_length,
        flipped_positions=tuple(positions),
    )
