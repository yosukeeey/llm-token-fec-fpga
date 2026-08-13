"""Test-only Frame V0 serializer and incremental parser."""

import struct
from dataclasses import dataclass
from enum import IntEnum

from . import protocol_constants as constants
from .crc32c import crc32c

SOF = constants.FRAME_SOF
FRAME_VERSION = constants.FRAME_VERSION
MAX_PAYLOAD_BYTES = constants.FRAME_MAX_PAYLOAD_BYTES
_HEADER = struct.Struct("<BBHH")
_CRC = struct.Struct("<I")
MIN_FRAME_BYTES = len(SOF) + _HEADER.size + _CRC.size


class ProtocolError(ValueError):
    """Base class for invalid Frame V0 input."""


class FrameLengthError(ProtocolError):
    """Report a Frame V0 length violation."""


class FrameCrcError(ProtocolError):
    """Report a Frame V0 CRC mismatch."""


class FrameVersionError(ProtocolError):
    """Report an unsupported Frame V0 version."""


class MessageType(IntEnum):
    """Identify test-only Frame V0 message types."""

    PING = constants.MESSAGE_TYPE_PING
    PONG = constants.MESSAGE_TYPE_PONG
    TOKEN_REQUEST = constants.MESSAGE_TYPE_TOKEN_REQUEST
    TOKEN_RESULT = constants.MESSAGE_TYPE_TOKEN_RESULT
    # Frame V0 used TEST names before the Token payload contract was fixed.
    TEST_REQUEST = TOKEN_REQUEST
    TEST_RESULT = TOKEN_RESULT
    ERROR_RESPONSE = constants.MESSAGE_TYPE_ERROR_RESPONSE


@dataclass(frozen=True, slots=True)
class Frame:
    """Represent a validated test-only Frame V0 payload and header.

    Attributes
    ----------
    message_type : int
        Unsigned 8-bit test message type.
    payload : bytes
        Opaque payload of at most 1024 bytes.
    flags : int
        Unsigned 16-bit flags field.
    version : int
        Unsigned 8-bit protocol version.
    """

    message_type: int
    payload: bytes = b""
    flags: int = 0
    version: int = FRAME_VERSION

    def __post_init__(self) -> None:
        if not 0 <= self.version <= 0xFF:
            raise ValueError("version must be an unsigned 8-bit value")
        if not 0 <= self.message_type <= 0xFF:
            raise ValueError("message_type must be an unsigned 8-bit value")
        if not 0 <= self.flags <= 0xFFFF:
            raise ValueError("flags must be an unsigned 16-bit value")
        if len(self.payload) > MAX_PAYLOAD_BYTES:
            raise FrameLengthError("payload exceeds Frame V0 maximum")


def serialize_frame(frame: Frame) -> bytes:
    """Serialize a Frame V0 value with little-endian fields and CRC-32C.

    Parameters
    ----------
    frame : Frame
        Validated frame fields and opaque payload.

    Returns
    -------
    bytes
        Complete wire representation including SOF and CRC.
    """
    header = _HEADER.pack(
        frame.version,
        frame.message_type,
        frame.flags,
        len(frame.payload),
    )
    crc_input = header + frame.payload
    return SOF + crc_input + _CRC.pack(crc32c(crc_input))


def parse_frame(data: bytes) -> Frame:
    """Parse and validate exactly one complete Frame V0 value.

    Parameters
    ----------
    data : bytes
        Complete serialized frame.

    Returns
    -------
    Frame
        Parsed header fields and opaque payload.

    Raises
    ------
    ProtocolError
        If framing, version, length, or CRC validation fails.
    """
    if len(data) < MIN_FRAME_BYTES:
        raise FrameLengthError("frame is shorter than the minimum size")
    if not data.startswith(SOF):
        raise ProtocolError("frame does not start with SOF")

    version, message_type, flags, payload_length = _HEADER.unpack_from(data, len(SOF))
    if payload_length > MAX_PAYLOAD_BYTES:
        raise FrameLengthError("payload length exceeds Frame V0 maximum")

    expected_length = MIN_FRAME_BYTES + payload_length
    if len(data) != expected_length:
        raise FrameLengthError("frame length does not match payload length")
    if version != FRAME_VERSION:
        raise FrameVersionError(f"unsupported Frame version: {version}")

    crc_input_end = len(SOF) + _HEADER.size + payload_length
    crc_input = data[len(SOF) : crc_input_end]
    expected_crc = _CRC.unpack_from(data, crc_input_end)[0]
    actual_crc = crc32c(crc_input)
    if actual_crc != expected_crc:
        raise FrameCrcError(
            f"CRC mismatch: expected 0x{expected_crc:08x}, got 0x{actual_crc:08x}"
        )

    payload = data[len(SOF) + _HEADER.size : crc_input_end]
    return Frame(
        version=version,
        message_type=message_type,
        flags=flags,
        payload=payload,
    )


class FrameParser:
    """Incrementally extract valid frames and resynchronize after bad input.

    Attributes
    ----------
    errors : list[ProtocolError]
        Validation errors observed while searching for the next valid SOF.
    """

    def __init__(self) -> None:
        self._buffer = bytearray()
        self.errors: list[ProtocolError] = []

    @property
    def buffered_bytes(self) -> int:
        """Return the number of bytes waiting for a complete frame.

        Returns
        -------
        int
            Number of bytes retained by the incremental parser.
        """
        return len(self._buffer)

    def feed(self, data: bytes) -> list[Frame]:
        """Consume stream bytes and extract every newly complete valid frame.

        Parameters
        ----------
        data : bytes
            Next chunk from the byte stream.

        Returns
        -------
        list[Frame]
            Valid frames completed by this input chunk.
        """
        self._buffer.extend(data)
        frames: list[Frame] = []

        while True:
            sof_index = self._buffer.find(SOF)
            if sof_index < 0:
                self._buffer[:] = self._buffer[-1:] if self._buffer.endswith(SOF[:1]) else b""
                break
            if sof_index:
                del self._buffer[:sof_index]
            if len(self._buffer) < len(SOF) + _HEADER.size:
                break

            version, _, _, payload_length = _HEADER.unpack_from(self._buffer, len(SOF))
            if payload_length > MAX_PAYLOAD_BYTES:
                self.errors.append(FrameLengthError("payload length exceeds maximum"))
                del self._buffer[0]
                continue

            frame_length = MIN_FRAME_BYTES + payload_length
            if len(self._buffer) < frame_length:
                break

            candidate = bytes(self._buffer[:frame_length])
            try:
                frame = parse_frame(candidate)
            except ProtocolError as error:
                self.errors.append(error)
                del self._buffer[0]
                continue

            if version != FRAME_VERSION:
                raise AssertionError("parse_frame accepted an unsupported version")
            frames.append(frame)
            del self._buffer[:frame_length]

        return frames
