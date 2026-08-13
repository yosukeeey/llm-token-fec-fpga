import pytest

from sw.common import (
    ChannelFlag,
    ChannelState,
    ErrorResponse,
    ExtensionTlv,
    PayloadFormatError,
    PayloadVersionError,
    ProtectionMode,
    ProtectionRequest,
    ResultFlag,
    ResultStatus,
    TokenFlag,
    TokenRecord,
    TokenRequest,
    TokenResult,
    UnsupportedProtectionError,
    next_sequence,
)


def _token_with_extension() -> TokenRecord:
    return TokenRecord(
        stream_id=0x11223344,
        sequence=0xFFFFFFFF,
        token_id=0x55667788,
        generated_time_us=1_000,
        deadline_us=2_000,
        flags=TokenFlag.GENERATED_TIME_VALID | TokenFlag.DEADLINE_VALID,
        extensions=(ExtensionTlv(0x80, b"\xAA\x55"),),
    )


def test_token_record_known_answer_and_unknown_tlv_round_trip() -> None:
    record = _token_with_extension()
    encoded = record.pack()
    assert encoded.hex() == (
        "0103280044332211ffffffff8877665500000000"
        "e803000000000000d00700000000000004000000"
        "8002aa55"
    )
    assert TokenRecord.unpack(encoded) == record


def test_token_request_round_trip() -> None:
    token = _token_with_extension()
    request = TokenRequest(
        token,
        ProtectionRequest(
            ProtectionMode.HAMMING_7_4,
            block_length_bits=len(token.pack()) * 8,
            code_rate_num=4,
            code_rate_den=7,
        ),
        ChannelState(0x8000, ChannelFlag.QUALITY_VALID),
    )
    assert TokenRequest.unpack(request.pack()) == request


def test_token_result_and_error_response_round_trip() -> None:
    result = TokenResult(
        _token_with_extension(),
        ResultStatus(ResultFlag.FEC_CORRECTED, corrected_count=1),
    )
    error = ErrorResponse(ResultFlag.MALFORMED_REQUEST, 0x10)
    assert TokenResult.unpack(result.pack()) == result
    assert ErrorResponse.unpack(error.pack()) == error


def test_sequence_wraps_modulo_unsigned_32_bits() -> None:
    assert next_sequence(0xFFFFFFFF) == 0


def test_rejects_truncated_extension() -> None:
    encoded = bytearray(_token_with_extension().pack())
    encoded[-3] = 3
    with pytest.raises(PayloadFormatError, match="truncated"):
        TokenRecord.unpack(bytes(encoded))


def test_rejects_unknown_versions_and_protection() -> None:
    token = bytearray(_token_with_extension().pack())
    token[0] = 2
    with pytest.raises(PayloadVersionError):
        TokenRecord.unpack(bytes(token))

    request = bytearray(ProtectionRequest(ProtectionMode.NONE, 320).pack())
    request[1] = 0xFF
    with pytest.raises(UnsupportedProtectionError):
        ProtectionRequest.unpack(bytes(request))


def test_rejects_invalid_optional_values_and_block_length() -> None:
    with pytest.raises(ValueError, match="generated_time_us"):
        TokenRecord(1, 2, 3, generated_time_us=1)
    token = TokenRecord(1, 2, 3)
    with pytest.raises(ValueError, match="block_length_bits"):
        TokenRequest(token, ProtectionRequest(ProtectionMode.NONE, 0))
