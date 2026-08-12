"""FEC golden models."""

from .hamming74 import HammingDecodeResult, hamming74_decode, hamming74_encode
from .parity import even_parity_bit, has_even_parity
from .repetition import RepetitionDecodeResult, repetition_decode, repetition_encode

__all__ = [
    "HammingDecodeResult",
    "RepetitionDecodeResult",
    "even_parity_bit",
    "hamming74_decode",
    "hamming74_encode",
    "has_even_parity",
    "repetition_decode",
    "repetition_encode",
]
