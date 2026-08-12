#include "reference/types.hpp"

#include <limits>
#include <string>

#include "reference/protocol_constants.hpp"

namespace reference {
namespace {

using namespace protocol_constants;

void append_u16(Bytes& output, const std::uint16_t value) {
    output.push_back(static_cast<std::uint8_t>(value & 0xFFU));
    output.push_back(static_cast<std::uint8_t>((value >> 8U) & 0xFFU));
}

void append_u32(Bytes& output, const std::uint32_t value) {
    for (unsigned shift = 0; shift < 32U; shift += 8U) {
        output.push_back(static_cast<std::uint8_t>((value >> shift) & 0xFFU));
    }
}

void append_u64(Bytes& output, const std::uint64_t value) {
    for (unsigned shift = 0; shift < 64U; shift += 8U) {
        output.push_back(static_cast<std::uint8_t>((value >> shift) & 0xFFU));
    }
}

std::uint16_t read_u16(const std::span<const std::uint8_t> data, const std::size_t offset) {
    return static_cast<std::uint16_t>(
        data[offset] | (static_cast<std::uint16_t>(data[offset + 1U]) << 8U)
    );
}

std::uint32_t read_u32(const std::span<const std::uint8_t> data, const std::size_t offset) {
    std::uint32_t value = 0U;
    for (unsigned index = 0; index < 4U; ++index) {
        value |= static_cast<std::uint32_t>(data[offset + index]) << (index * 8U);
    }
    return value;
}

std::uint64_t read_u64(const std::span<const std::uint8_t> data, const std::size_t offset) {
    std::uint64_t value = 0U;
    for (unsigned index = 0; index < 8U; ++index) {
        value |= static_cast<std::uint64_t>(data[offset + index]) << (index * 8U);
    }
    return value;
}

void require_size(
    const std::span<const std::uint8_t> data,
    const std::size_t expected,
    const char* name
) {
    if (data.size() != expected) {
        throw PayloadFormatError(std::string(name) + " size mismatch");
    }
}

void require_flags(const std::uint64_t flags, const std::uint64_t allowed, const char* name) {
    if ((flags & ~allowed) != 0U) {
        throw PayloadFormatError(std::string(name) + " contains unsupported flag bits");
    }
}

std::size_t extension_size(const std::vector<ExtensionTlv>& extensions) {
    std::size_t size = 0U;
    for (const auto& extension : extensions) {
        if (extension.value.size() > extension_tlv_max_value_bytes) {
            throw std::invalid_argument("extension value exceeds its 8-bit length field");
        }
        size += static_cast<std::size_t>(extension_tlv_header_size) + extension.value.size();
    }
    if (size > std::numeric_limits<std::uint16_t>::max()) {
        throw std::invalid_argument("extension area exceeds its 16-bit length field");
    }
    return size;
}

void validate_token_record(const TokenRecord& value) {
    require_flags(
        value.flags,
        token_flag_generated_time_valid | token_flag_deadline_valid,
        "TokenRecord.flags"
    );
    if (value.importance != 0U) {
        throw std::invalid_argument("importance must remain zero in the current protocol");
    }
    if ((value.flags & token_flag_generated_time_valid) == 0U
        && value.generated_time_us != 0U) {
        throw std::invalid_argument("generated_time_us must be zero when invalid");
    }
    if ((value.flags & token_flag_deadline_valid) == 0U && value.deadline_us != 0U) {
        throw std::invalid_argument("deadline_us must be zero when invalid");
    }
    static_cast<void>(extension_size(value.extensions));
}

void validate_protection_request(const ProtectionRequest& value) {
    if (value.flags != 0U) {
        throw std::invalid_argument("ProtectionRequest flags must be zero");
    }
    switch (value.mode) {
    case ProtectionMode::none:
        if (value.repetition_count != 1U || value.code_rate_num != 1U
            || value.code_rate_den != 1U) {
            throw std::invalid_argument("NONE parameters do not match mode");
        }
        break;
    case ProtectionMode::repetition:
        if ((value.repetition_count != 1U && value.repetition_count != 3U)
            || value.code_rate_num != 1U
            || value.code_rate_den != value.repetition_count) {
            throw std::invalid_argument("repetition parameters do not match mode");
        }
        break;
    case ProtectionMode::hamming_7_4:
        if (value.repetition_count != 1U || value.code_rate_num != 4U
            || value.code_rate_den != 7U) {
            throw std::invalid_argument("Hamming parameters do not match mode");
        }
        break;
    default:
        throw UnsupportedProtectionError("unsupported protection mode");
    }
}

void validate_channel_state(const ChannelState& value) {
    require_flags(value.flags, channel_flag_quality_valid, "ChannelState.flags");
    if ((value.flags & channel_flag_quality_valid) == 0U && value.channel_quality != 0U) {
        throw std::invalid_argument("channel_quality must be zero when invalid");
    }
}

constexpr std::uint32_t result_flag_mask =
    static_cast<std::uint32_t>(result_flag_parity_error)
    | static_cast<std::uint32_t>(result_flag_fec_corrected)
    | static_cast<std::uint32_t>(result_flag_crc_error)
    | static_cast<std::uint32_t>(result_flag_malformed_frame)
    | static_cast<std::uint32_t>(result_flag_malformed_request)
    | static_cast<std::uint32_t>(result_flag_unsupported_version)
    | static_cast<std::uint32_t>(result_flag_unsupported_protection)
    | static_cast<std::uint32_t>(result_flag_sequence_gap)
    | static_cast<std::uint32_t>(result_flag_uart_framing_error)
    | static_cast<std::uint32_t>(result_flag_internal_overflow);

void validate_result_flags(const std::uint32_t flags, const char* name) {
    require_flags(flags, result_flag_mask, name);
}

}

Bytes pack_token_record(const TokenRecord& value) {
    validate_token_record(value);
    const auto extensions_length = extension_size(value.extensions);
    Bytes output;
    output.reserve(static_cast<std::size_t>(token_record_base_size) + extensions_length);
    output.push_back(static_cast<std::uint8_t>(token_record_version));
    output.push_back(value.flags);
    append_u16(output, static_cast<std::uint16_t>(token_record_base_size));
    append_u32(output, value.stream_id);
    append_u32(output, value.sequence);
    append_u32(output, value.token_id);
    output.push_back(value.importance);
    output.insert(output.end(), 3U, 0U);
    append_u64(output, value.generated_time_us);
    append_u64(output, value.deadline_us);
    append_u16(output, static_cast<std::uint16_t>(extensions_length));
    output.insert(output.end(), 2U, 0U);
    for (const auto& extension : value.extensions) {
        output.push_back(extension.type_id);
        output.push_back(static_cast<std::uint8_t>(extension.value.size()));
        output.insert(output.end(), extension.value.begin(), extension.value.end());
    }
    return output;
}

TokenRecord unpack_token_record(const std::span<const std::uint8_t> data) {
    if (data.size() < token_record_base_size) {
        throw PayloadFormatError("TokenRecord base is truncated");
    }
    if (data[token_record_record_version_offset] != token_record_version) {
        throw PayloadVersionError("unsupported TokenRecord version");
    }
    const auto base_length = read_u16(data, token_record_base_length_offset);
    if (base_length != token_record_base_size) {
        throw PayloadFormatError("unsupported TokenRecord base length");
    }
    const auto extensions_length = read_u16(data, token_record_extension_length_offset);
    if (data.size() != base_length + extensions_length) {
        throw PayloadFormatError("TokenRecord extension length mismatch");
    }

    TokenRecord value{
        read_u32(data, token_record_stream_id_offset),
        read_u32(data, token_record_sequence_offset),
        read_u32(data, token_record_token_id_offset),
        data[token_record_importance_offset],
        read_u64(data, token_record_generated_time_us_offset),
        read_u64(data, token_record_deadline_us_offset),
        data[token_record_flags_offset],
        {},
    };
    auto offset = static_cast<std::size_t>(base_length);
    while (offset < data.size()) {
        if (data.size() - offset < extension_tlv_header_size) {
            throw PayloadFormatError("extension header is truncated");
        }
        const auto type_id = data[offset];
        const auto value_length = data[offset + 1U];
        offset += extension_tlv_header_size;
        if (offset + value_length > data.size()) {
            throw PayloadFormatError("extension value is truncated");
        }
        value.extensions.push_back(
            {type_id, Bytes(data.begin() + static_cast<std::ptrdiff_t>(offset),
                            data.begin() + static_cast<std::ptrdiff_t>(offset + value_length))}
        );
        offset += value_length;
    }
    try {
        validate_token_record(value);
    } catch (const PayloadFormatError&) {
        throw;
    } catch (const std::invalid_argument& error) {
        throw PayloadFormatError(error.what());
    }
    return value;
}

Bytes pack_protection_request(const ProtectionRequest& value) {
    validate_protection_request(value);
    Bytes output;
    output.reserve(protection_request_size);
    output.push_back(static_cast<std::uint8_t>(protection_request_version));
    output.push_back(static_cast<std::uint8_t>(value.mode));
    append_u16(output, value.flags);
    append_u16(output, value.block_length_bits);
    output.push_back(value.repetition_count);
    output.push_back(0U);
    append_u16(output, value.code_rate_num);
    append_u16(output, value.code_rate_den);
    append_u32(output, 0U);
    return output;
}

ProtectionRequest unpack_protection_request(const std::span<const std::uint8_t> data) {
    require_size(data, protection_request_size, "ProtectionRequest");
    if (data[protection_request_request_version_offset] != protection_request_version) {
        throw PayloadVersionError("unsupported ProtectionRequest version");
    }
    const auto raw_mode = data[protection_request_mode_offset];
    if (raw_mode > protection_mode_hamming_7_4) {
        throw UnsupportedProtectionError("unsupported protection mode");
    }
    ProtectionRequest value{
        static_cast<ProtectionMode>(raw_mode),
        read_u16(data, protection_request_block_length_bits_offset),
        data[protection_request_repetition_count_offset],
        read_u16(data, protection_request_code_rate_num_offset),
        read_u16(data, protection_request_code_rate_den_offset),
        read_u16(data, protection_request_flags_offset),
    };
    try {
        validate_protection_request(value);
    } catch (const UnsupportedProtectionError&) {
        throw;
    } catch (const std::invalid_argument& error) {
        throw PayloadFormatError(error.what());
    }
    return value;
}

Bytes pack_channel_state(const ChannelState& value) {
    validate_channel_state(value);
    Bytes output{
        static_cast<std::uint8_t>(channel_state_version),
        value.flags,
    };
    append_u16(output, value.channel_quality);
    return output;
}

ChannelState unpack_channel_state(const std::span<const std::uint8_t> data) {
    require_size(data, channel_state_size, "ChannelState");
    if (data[channel_state_state_version_offset] != channel_state_version) {
        throw PayloadVersionError("unsupported ChannelState version");
    }
    const ChannelState value{
        read_u16(data, channel_state_channel_quality_offset),
        data[channel_state_flags_offset],
    };
    try {
        validate_channel_state(value);
    } catch (const PayloadFormatError&) {
        throw;
    } catch (const std::invalid_argument& error) {
        throw PayloadFormatError(error.what());
    }
    return value;
}

Bytes pack_result_status(const ResultStatus& value) {
    validate_result_flags(value.flags, "ResultStatus.flags");
    Bytes output;
    output.reserve(result_status_size);
    append_u32(output, value.flags);
    append_u16(output, value.corrected_count);
    append_u16(output, value.detected_error_count);
    return output;
}

ResultStatus unpack_result_status(const std::span<const std::uint8_t> data) {
    require_size(data, result_status_size, "ResultStatus");
    const ResultStatus value{
        read_u32(data, result_status_flags_offset),
        read_u16(data, result_status_corrected_count_offset),
        read_u16(data, result_status_detected_error_count_offset),
    };
    validate_result_flags(value.flags, "ResultStatus.flags");
    return value;
}

Bytes pack_token_request(const TokenRequest& value) {
    auto token = pack_token_record(value.token);
    if (value.protection.block_length_bits != token.size() * 8U) {
        throw std::invalid_argument(
            "block_length_bits must equal serialized TokenRecord length"
        );
    }
    const auto protection = pack_protection_request(value.protection);
    const auto channel = pack_channel_state(value.channel);
    token.insert(token.end(), protection.begin(), protection.end());
    token.insert(token.end(), channel.begin(), channel.end());
    return token;
}

TokenRequest unpack_token_request(const std::span<const std::uint8_t> data) {
    const auto minimum = token_record_base_size + protection_request_size + channel_state_size;
    if (data.size() < minimum) {
        throw PayloadFormatError("TOKEN_REQUEST payload is truncated");
    }
    const auto extension_length = read_u16(data, token_record_extension_length_offset);
    const auto token_end = token_record_base_size + extension_length;
    const auto protection_end = token_end + protection_request_size;
    if (data.size() != protection_end + channel_state_size) {
        throw PayloadFormatError("TOKEN_REQUEST payload length mismatch");
    }
    TokenRequest value{
        unpack_token_record(data.first(token_end)),
        unpack_protection_request(data.subspan(token_end, protection_request_size)),
        unpack_channel_state(data.subspan(protection_end, channel_state_size)),
    };
    if (value.protection.block_length_bits != token_end * 8U) {
        throw PayloadFormatError(
            "block_length_bits must equal serialized TokenRecord length"
        );
    }
    return value;
}

Bytes pack_token_result(const TokenResult& value) {
    auto token = pack_token_record(value.token);
    const auto status = pack_result_status(value.status);
    token.insert(token.end(), status.begin(), status.end());
    return token;
}

TokenResult unpack_token_result(const std::span<const std::uint8_t> data) {
    if (data.size() < token_record_base_size + result_status_size) {
        throw PayloadFormatError("TOKEN_RESULT payload is truncated");
    }
    const auto extension_length = read_u16(data, token_record_extension_length_offset);
    const auto token_end = token_record_base_size + extension_length;
    if (data.size() != token_end + result_status_size) {
        throw PayloadFormatError("TOKEN_RESULT payload length mismatch");
    }
    return {
        unpack_token_record(data.first(token_end)),
        unpack_result_status(data.subspan(token_end)),
    };
}

Bytes pack_error_response(const ErrorResponse& value) {
    validate_result_flags(value.flags, "ErrorResponse.flags");
    Bytes output;
    output.reserve(error_response_size);
    append_u32(output, value.flags);
    output.push_back(value.request_message_type);
    output.insert(output.end(), 3U, 0U);
    return output;
}

ErrorResponse unpack_error_response(const std::span<const std::uint8_t> data) {
    require_size(data, error_response_size, "ErrorResponse");
    const ErrorResponse value{
        read_u32(data, error_response_flags_offset),
        data[error_response_request_message_type_offset],
    };
    validate_result_flags(value.flags, "ErrorResponse.flags");
    return value;
}

std::uint32_t next_sequence(const std::uint32_t sequence) noexcept {
    return sequence + 1U;
}

}
