"""Versioned Token payload records shared by reference implementations."""

import struct
from dataclasses import dataclass
from enum import IntEnum, IntFlag

from . import protocol_constants as constants

_TOKEN_RECORD = struct.Struct("<BBHIIIB3xQQH2x")
_PROTECTION_REQUEST = struct.Struct("<BBHHBBHHI")
_CHANNEL_STATE = struct.Struct("<BBH")
_RESULT_STATUS = struct.Struct("<IHH")
_ERROR_RESPONSE = struct.Struct("<IB3x")


class PayloadFormatError(ValueError):
    """Report a malformed or unsupported Token payload record."""


class PayloadVersionError(PayloadFormatError):
    """Report an unsupported version of a Token payload record."""


class UnsupportedProtectionError(PayloadFormatError):
    """Report a protection mode not defined by the current protocol."""


class TokenFlag(IntFlag):
    """Identify valid optional TokenRecord fields."""

    NONE = 0
    GENERATED_TIME_VALID = constants.TOKEN_FLAG_GENERATED_TIME_VALID
    DEADLINE_VALID = constants.TOKEN_FLAG_DEADLINE_VALID


class ProtectionMode(IntEnum):
    """Select the protection codec for one TokenRecord."""

    NONE = constants.PROTECTION_MODE_NONE
    REPETITION = constants.PROTECTION_MODE_REPETITION
    HAMMING_7_4 = constants.PROTECTION_MODE_HAMMING_7_4


class ChannelFlag(IntFlag):
    """Identify valid ChannelState fields."""

    NONE = 0
    QUALITY_VALID = constants.CHANNEL_FLAG_QUALITY_VALID


class ResultFlag(IntFlag):
    """Identify independently observed processing outcomes."""

    NONE = 0
    PARITY_ERROR = constants.RESULT_FLAG_PARITY_ERROR
    FEC_CORRECTED = constants.RESULT_FLAG_FEC_CORRECTED
    CRC_ERROR = constants.RESULT_FLAG_CRC_ERROR
    MALFORMED_FRAME = constants.RESULT_FLAG_MALFORMED_FRAME
    MALFORMED_REQUEST = constants.RESULT_FLAG_MALFORMED_REQUEST
    UNSUPPORTED_VERSION = constants.RESULT_FLAG_UNSUPPORTED_VERSION
    UNSUPPORTED_PROTECTION = constants.RESULT_FLAG_UNSUPPORTED_PROTECTION
    SEQUENCE_GAP = constants.RESULT_FLAG_SEQUENCE_GAP
    UART_FRAMING_ERROR = constants.RESULT_FLAG_UART_FRAMING_ERROR
    INTERNAL_OVERFLOW = constants.RESULT_FLAG_INTERNAL_OVERFLOW


def _require_uint(name: str, value: int, bits: int) -> None:
    if not isinstance(value, int) or isinstance(value, bool) or not 0 <= value < 1 << bits:
        raise ValueError(f"{name} must be an unsigned {bits}-bit integer")


def _require_known_flags(name: str, value: IntFlag, allowed: int) -> None:
    if int(value) & ~allowed:
        raise ValueError(f"{name} contains unsupported flag bits")


@dataclass(frozen=True, slots=True)
class ExtensionTlv:
    """Represent one skippable TokenRecord extension.

    Attributes
    ----------
    type_id : int
        Unsigned extension type identifier.
    value : bytes
        Opaque extension value of at most 255 bytes.
    """

    type_id: int
    value: bytes = b""

    def __post_init__(self) -> None:
        _require_uint("type_id", self.type_id, 8)
        if len(self.value) > constants.EXTENSION_TLV_MAX_VALUE_BYTES:
            raise ValueError("extension value exceeds its 8-bit length field")

    def pack(self) -> bytes:
        """Pack the extension header and value.

        Returns
        -------
        bytes
            Complete TLV bytes.
        """
        return bytes((self.type_id, len(self.value))) + self.value


def _unpack_extensions(data: bytes) -> tuple[ExtensionTlv, ...]:
    extensions: list[ExtensionTlv] = []
    offset = 0
    while offset < len(data):
        if len(data) - offset < constants.EXTENSION_TLV_HEADER_SIZE:
            raise PayloadFormatError("extension header is truncated")
        type_id = data[offset]
        value_length = data[offset + 1]
        offset += constants.EXTENSION_TLV_HEADER_SIZE
        end = offset + value_length
        if end > len(data):
            raise PayloadFormatError("extension value is truncated")
        extensions.append(ExtensionTlv(type_id, data[offset:end]))
        offset = end
    return tuple(extensions)


@dataclass(frozen=True, slots=True)
class TokenRecord:
    """Represent a Version 1 TokenRecord and optional extensions.

    Attributes
    ----------
    stream_id : int
        Stream-local sequence namespace.
    sequence : int
        Unsigned sequence number wrapping modulo 2^32.
    token_id : int
        Unsigned tokenizer identifier.
    importance : int
        Reserved importance value; zero in the current test protocol.
    generated_time_us : int
        Run-relative generation timestamp in microseconds.
    deadline_us : int
        Run-relative absolute deadline in microseconds.
    flags : TokenFlag
        Validity flags for optional timestamp fields.
    extensions : tuple[ExtensionTlv, ...]
        Ordered skippable extension records.
    """

    stream_id: int
    sequence: int
    token_id: int
    importance: int = 0
    generated_time_us: int = 0
    deadline_us: int = 0
    flags: TokenFlag = TokenFlag.NONE
    extensions: tuple[ExtensionTlv, ...] = ()

    def __post_init__(self) -> None:
        _require_uint("stream_id", self.stream_id, 32)
        _require_uint("sequence", self.sequence, 32)
        _require_uint("token_id", self.token_id, 32)
        _require_uint("importance", self.importance, 8)
        _require_uint("generated_time_us", self.generated_time_us, 64)
        _require_uint("deadline_us", self.deadline_us, 64)
        _require_known_flags(
            "TokenRecord.flags",
            self.flags,
            constants.TOKEN_FLAG_GENERATED_TIME_VALID
            | constants.TOKEN_FLAG_DEADLINE_VALID,
        )
        if self.importance != 0:
            raise ValueError("importance must remain zero in the current protocol")
        if not self.flags & TokenFlag.GENERATED_TIME_VALID and self.generated_time_us != 0:
            raise ValueError("generated_time_us must be zero when invalid")
        if not self.flags & TokenFlag.DEADLINE_VALID and self.deadline_us != 0:
            raise ValueError("deadline_us must be zero when invalid")
        extension_length = sum(len(extension.pack()) for extension in self.extensions)
        _require_uint("extension_length", extension_length, 16)

    def pack(self) -> bytes:
        """Pack the record in its canonical little-endian form.

        Returns
        -------
        bytes
            Fixed base record followed by ordered extension TLVs.
        """
        extensions = b"".join(extension.pack() for extension in self.extensions)
        base = _TOKEN_RECORD.pack(
            constants.TOKEN_RECORD_VERSION,
            int(self.flags),
            constants.TOKEN_RECORD_BASE_SIZE,
            self.stream_id,
            self.sequence,
            self.token_id,
            self.importance,
            self.generated_time_us,
            self.deadline_us,
            len(extensions),
        )
        return base + extensions

    @classmethod
    def unpack(cls, data: bytes) -> "TokenRecord":
        """Validate and unpack exactly one TokenRecord.

        Parameters
        ----------
        data : bytes
            Complete base record and extension area.

        Returns
        -------
        TokenRecord
            Parsed record.
        """
        if len(data) < constants.TOKEN_RECORD_BASE_SIZE:
            raise PayloadFormatError("TokenRecord base is truncated")
        (
            version,
            flags,
            base_length,
            stream_id,
            sequence,
            token_id,
            importance,
            generated_time_us,
            deadline_us,
            extension_length,
        ) = _TOKEN_RECORD.unpack_from(data)
        if version != constants.TOKEN_RECORD_VERSION:
            raise PayloadVersionError("unsupported TokenRecord version")
        if base_length != constants.TOKEN_RECORD_BASE_SIZE:
            raise PayloadFormatError("unsupported TokenRecord base length")
        if len(data) != base_length + extension_length:
            raise PayloadFormatError("TokenRecord extension length mismatch")
        try:
            token_flags = TokenFlag(flags)
            return cls(
                stream_id=stream_id,
                sequence=sequence,
                token_id=token_id,
                importance=importance,
                generated_time_us=generated_time_us,
                deadline_us=deadline_us,
                flags=token_flags,
                extensions=_unpack_extensions(data[base_length:]),
            )
        except ValueError as error:
            raise PayloadFormatError(str(error)) from error


@dataclass(frozen=True, slots=True)
class ProtectionRequest:
    """Represent the Version 1 protection selection.

    Attributes
    ----------
    mode : ProtectionMode
        Selected protection codec.
    block_length_bits : int
        Exact number of TokenRecord bits covered by the codec.
    repetition_count : int
        Adjacent copies per bit for repetition mode.
    code_rate_num : int
        Code-rate numerator.
    code_rate_den : int
        Code-rate denominator.
    flags : int
        Reserved flags; zero in Version 1.
    """

    mode: ProtectionMode
    block_length_bits: int
    repetition_count: int = 1
    code_rate_num: int = 1
    code_rate_den: int = 1
    flags: int = 0

    def __post_init__(self) -> None:
        _require_uint("block_length_bits", self.block_length_bits, 16)
        _require_uint("repetition_count", self.repetition_count, 8)
        _require_uint("code_rate_num", self.code_rate_num, 16)
        _require_uint("code_rate_den", self.code_rate_den, 16)
        _require_uint("flags", self.flags, 16)
        if self.flags != 0:
            raise ValueError("ProtectionRequest flags must be zero")
        expected = {
            ProtectionMode.NONE: (1, 1, 1),
            ProtectionMode.REPETITION: (
                self.repetition_count,
                1,
                self.repetition_count,
            ),
            ProtectionMode.HAMMING_7_4: (1, 4, 7),
        }[self.mode]
        if self.mode is ProtectionMode.REPETITION and self.repetition_count not in (1, 3):
            raise ValueError("repetition mode supports only R=1 or R=3")
        if (self.repetition_count, self.code_rate_num, self.code_rate_den) != expected:
            raise ValueError("protection parameters do not match mode")

    def pack(self) -> bytes:
        """Pack the fixed-size request.

        Returns
        -------
        bytes
            Canonical 16-byte request.
        """
        return _PROTECTION_REQUEST.pack(
            constants.PROTECTION_REQUEST_VERSION,
            int(self.mode),
            self.flags,
            self.block_length_bits,
            self.repetition_count,
            0,
            self.code_rate_num,
            self.code_rate_den,
            0,
        )

    @classmethod
    def unpack(cls, data: bytes) -> "ProtectionRequest":
        """Validate and unpack one request.

        Parameters
        ----------
        data : bytes
            Complete fixed-size request.

        Returns
        -------
        ProtectionRequest
            Parsed request.
        """
        if len(data) != constants.PROTECTION_REQUEST_SIZE:
            raise PayloadFormatError("ProtectionRequest size mismatch")
        version, mode, flags, block_bits, repetition, _, rate_num, rate_den, _ = (
            _PROTECTION_REQUEST.unpack(data)
        )
        if version != constants.PROTECTION_REQUEST_VERSION:
            raise PayloadVersionError("unsupported ProtectionRequest version")
        try:
            protection_mode = ProtectionMode(mode)
        except ValueError as error:
            raise UnsupportedProtectionError("unsupported protection mode") from error
        try:
            return cls(
                protection_mode,
                block_bits,
                repetition,
                rate_num,
                rate_den,
                flags,
            )
        except ValueError as error:
            raise PayloadFormatError(str(error)) from error


@dataclass(frozen=True, slots=True)
class ChannelState:
    """Represent normalized channel quality without a physical-unit binding.

    Attributes
    ----------
    channel_quality : int
        Normalized quality from zero worst to 65535 best.
    flags : ChannelFlag
        Validity of the quality value.
    """

    channel_quality: int = 0
    flags: ChannelFlag = ChannelFlag.NONE

    def __post_init__(self) -> None:
        _require_uint("channel_quality", self.channel_quality, 16)
        _require_known_flags(
            "ChannelState.flags", self.flags, constants.CHANNEL_FLAG_QUALITY_VALID
        )
        if not self.flags & ChannelFlag.QUALITY_VALID and self.channel_quality != 0:
            raise ValueError("channel_quality must be zero when invalid")

    def pack(self) -> bytes:
        """Pack the fixed-size state.

        Returns
        -------
        bytes
            Canonical four-byte state.
        """
        return _CHANNEL_STATE.pack(
            constants.CHANNEL_STATE_VERSION,
            int(self.flags),
            self.channel_quality,
        )

    @classmethod
    def unpack(cls, data: bytes) -> "ChannelState":
        """Validate and unpack one state.

        Parameters
        ----------
        data : bytes
            Complete fixed-size state.

        Returns
        -------
        ChannelState
            Parsed state.
        """
        if len(data) != constants.CHANNEL_STATE_SIZE:
            raise PayloadFormatError("ChannelState size mismatch")
        version, flags, quality = _CHANNEL_STATE.unpack(data)
        if version != constants.CHANNEL_STATE_VERSION:
            raise PayloadVersionError("unsupported ChannelState version")
        try:
            return cls(quality, ChannelFlag(flags))
        except ValueError as error:
            raise PayloadFormatError(str(error)) from error


@dataclass(frozen=True, slots=True)
class ResultStatus:
    """Represent result flags and observed error counts.

    Attributes
    ----------
    flags : ResultFlag
        Independently observed processing outcomes.
    corrected_count : int
        Number of groups or codewords reported corrected.
    detected_error_count : int
        Number of separately detected errors.
    """

    flags: ResultFlag = ResultFlag.NONE
    corrected_count: int = 0
    detected_error_count: int = 0

    def __post_init__(self) -> None:
        allowed = sum(int(flag) for flag in ResultFlag)
        _require_known_flags("ResultStatus.flags", self.flags, allowed)
        _require_uint("corrected_count", self.corrected_count, 16)
        _require_uint("detected_error_count", self.detected_error_count, 16)

    def pack(self) -> bytes:
        """Pack the fixed-size result status.

        Returns
        -------
        bytes
            Canonical eight-byte status.
        """
        return _RESULT_STATUS.pack(
            int(self.flags), self.corrected_count, self.detected_error_count
        )

    @classmethod
    def unpack(cls, data: bytes) -> "ResultStatus":
        """Validate and unpack one result status.

        Parameters
        ----------
        data : bytes
            Complete fixed-size status.

        Returns
        -------
        ResultStatus
            Parsed result status.
        """
        if len(data) != constants.RESULT_STATUS_SIZE:
            raise PayloadFormatError("ResultStatus size mismatch")
        flags, corrected, detected = _RESULT_STATUS.unpack(data)
        try:
            return cls(ResultFlag(flags), corrected, detected)
        except ValueError as error:
            raise PayloadFormatError(str(error)) from error


@dataclass(frozen=True, slots=True)
class TokenRequest:
    """Represent the TOKEN_REQUEST payload.

    Attributes
    ----------
    token : TokenRecord
        Token metadata covered by the protection request.
    protection : ProtectionRequest
        Protection parameters for the serialized TokenRecord.
    channel : ChannelState
        Advisory channel state, unused for control in Version 1.
    """

    token: TokenRecord
    protection: ProtectionRequest
    channel: ChannelState = ChannelState()

    def __post_init__(self) -> None:
        if self.protection.block_length_bits != len(self.token.pack()) * 8:
            raise ValueError("block_length_bits must equal serialized TokenRecord length")

    def pack(self) -> bytes:
        """Pack the variable TokenRecord and fixed request suffix.

        Returns
        -------
        bytes
            Complete TOKEN_REQUEST payload.
        """
        return self.token.pack() + self.protection.pack() + self.channel.pack()

    @classmethod
    def unpack(cls, data: bytes) -> "TokenRequest":
        """Validate and unpack one TOKEN_REQUEST payload.

        Parameters
        ----------
        data : bytes
            Complete TOKEN_REQUEST payload.

        Returns
        -------
        TokenRequest
            Parsed payload.
        """
        minimum = (
            constants.TOKEN_RECORD_BASE_SIZE
            + constants.PROTECTION_REQUEST_SIZE
            + constants.CHANNEL_STATE_SIZE
        )
        if len(data) < minimum:
            raise PayloadFormatError("TOKEN_REQUEST payload is truncated")
        extension_offset = constants.TOKEN_RECORD_EXTENSION_LENGTH_OFFSET
        extension_length = int.from_bytes(data[extension_offset : extension_offset + 2], "little")
        token_end = constants.TOKEN_RECORD_BASE_SIZE + extension_length
        expected = token_end + constants.PROTECTION_REQUEST_SIZE + constants.CHANNEL_STATE_SIZE
        if len(data) != expected:
            raise PayloadFormatError("TOKEN_REQUEST payload length mismatch")
        protection_end = token_end + constants.PROTECTION_REQUEST_SIZE
        try:
            return cls(
                TokenRecord.unpack(data[:token_end]),
                ProtectionRequest.unpack(data[token_end:protection_end]),
                ChannelState.unpack(data[protection_end:]),
            )
        except ValueError as error:
            raise PayloadFormatError(str(error)) from error


@dataclass(frozen=True, slots=True)
class TokenResult:
    """Represent the TOKEN_RESULT payload.

    Attributes
    ----------
    token : TokenRecord
        Recovered TokenRecord.
    status : ResultStatus
        Processing status and counts.
    """

    token: TokenRecord
    status: ResultStatus = ResultStatus()

    def pack(self) -> bytes:
        """Pack the recovered record and status.

        Returns
        -------
        bytes
            Complete TOKEN_RESULT payload.
        """
        return self.token.pack() + self.status.pack()

    @classmethod
    def unpack(cls, data: bytes) -> "TokenResult":
        """Validate and unpack one TOKEN_RESULT payload.

        Parameters
        ----------
        data : bytes
            Complete TOKEN_RESULT payload.

        Returns
        -------
        TokenResult
            Parsed payload.
        """
        minimum = constants.TOKEN_RECORD_BASE_SIZE + constants.RESULT_STATUS_SIZE
        if len(data) < minimum:
            raise PayloadFormatError("TOKEN_RESULT payload is truncated")
        extension_offset = constants.TOKEN_RECORD_EXTENSION_LENGTH_OFFSET
        extension_length = int.from_bytes(data[extension_offset : extension_offset + 2], "little")
        token_end = constants.TOKEN_RECORD_BASE_SIZE + extension_length
        if len(data) != token_end + constants.RESULT_STATUS_SIZE:
            raise PayloadFormatError("TOKEN_RESULT payload length mismatch")
        return cls(
            TokenRecord.unpack(data[:token_end]),
            ResultStatus.unpack(data[token_end:]),
        )


@dataclass(frozen=True, slots=True)
class ErrorResponse:
    """Represent an ERROR_RESPONSE payload without echoing request data.

    Attributes
    ----------
    flags : ResultFlag
        Error conditions safe to report.
    request_message_type : int
        Trusted header message type associated with the error.
    """

    flags: ResultFlag
    request_message_type: int

    def __post_init__(self) -> None:
        allowed = sum(int(flag) for flag in ResultFlag)
        _require_known_flags("ErrorResponse.flags", self.flags, allowed)
        _require_uint("request_message_type", self.request_message_type, 8)

    def pack(self) -> bytes:
        """Pack the fixed-size error response.

        Returns
        -------
        bytes
            Canonical eight-byte response.
        """
        return _ERROR_RESPONSE.pack(int(self.flags), self.request_message_type)

    @classmethod
    def unpack(cls, data: bytes) -> "ErrorResponse":
        """Validate and unpack one error response.

        Parameters
        ----------
        data : bytes
            Complete fixed-size response.

        Returns
        -------
        ErrorResponse
            Parsed response.
        """
        if len(data) != constants.ERROR_RESPONSE_SIZE:
            raise PayloadFormatError("ErrorResponse size mismatch")
        flags, message_type = _ERROR_RESPONSE.unpack(data)
        try:
            return cls(ResultFlag(flags), message_type)
        except ValueError as error:
            raise PayloadFormatError(str(error)) from error


def next_sequence(sequence: int) -> int:
    """Advance a sequence number with the fixed unsigned wrap rule.

    Parameters
    ----------
    sequence : int
        Current unsigned 32-bit sequence number.

    Returns
    -------
    int
        Next sequence number modulo 2^32.
    """
    _require_uint("sequence", sequence, constants.SEQUENCE_BITS)
    return (sequence + 1) % constants.SEQUENCE_MODULUS
