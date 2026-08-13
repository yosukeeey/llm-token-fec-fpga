"""Dependency-free CRC-32C (Castagnoli) reference implementation."""

from .protocol_constants import (
    CRC32C_INITIAL,
    CRC32C_REFLECTED_POLYNOMIAL,
    CRC32C_XOR_OUT,
)


def crc32c_update(crc: int, data: bytes) -> int:
    """Update an unfinalized reflected CRC-32C state.

    Parameters
    ----------
    crc : int
        Current unsigned 32-bit CRC state.
    data : bytes
        Bytes to include in the state.

    Returns
    -------
    int
        Updated unfinalized CRC state.

    Raises
    ------
    ValueError
        If ``crc`` is outside the unsigned 32-bit range.
    """
    if not 0 <= crc <= 0xFFFFFFFF:
        raise ValueError("crc must be an unsigned 32-bit value")

    for byte in data:
        crc ^= byte
        for _ in range(8):
            crc = (crc >> 1) ^ (CRC32C_REFLECTED_POLYNOMIAL if crc & 1 else 0)
    return crc & 0xFFFFFFFF


def crc32c(data: bytes) -> int:
    """Calculate the finalized CRC-32C Castagnoli checksum.

    Parameters
    ----------
    data : bytes
        Bytes covered by the checksum.

    Returns
    -------
    int
        Finalized unsigned 32-bit checksum.
    """
    return crc32c_update(CRC32C_INITIAL, data) ^ CRC32C_XOR_OUT
