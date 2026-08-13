#pragma once

#include <cstdint>
#include <span>
#include <stdexcept>
#include <vector>

#include "reference/bits.hpp"
#include "reference/protocol_constants.hpp"

namespace reference {

class PayloadFormatError : public std::invalid_argument {
public:
    using std::invalid_argument::invalid_argument;
};

class PayloadVersionError : public PayloadFormatError {
public:
    using PayloadFormatError::PayloadFormatError;
};

class UnsupportedProtectionError : public PayloadFormatError {
public:
    using PayloadFormatError::PayloadFormatError;
};

enum class TokenFlag : std::uint8_t {
    generated_time_valid = protocol_constants::token_flag_generated_time_valid,
    deadline_valid = protocol_constants::token_flag_deadline_valid,
};

enum class ProtectionMode : std::uint8_t {
    none = protocol_constants::protection_mode_none,
    repetition = protocol_constants::protection_mode_repetition,
    hamming_7_4 = protocol_constants::protection_mode_hamming_7_4,
};

enum class ChannelFlag : std::uint8_t {
    quality_valid = protocol_constants::channel_flag_quality_valid,
};

enum class ResultFlag : std::uint32_t {
    parity_error = protocol_constants::result_flag_parity_error,
    fec_corrected = protocol_constants::result_flag_fec_corrected,
    crc_error = protocol_constants::result_flag_crc_error,
    malformed_frame = protocol_constants::result_flag_malformed_frame,
    malformed_request = protocol_constants::result_flag_malformed_request,
    unsupported_version = protocol_constants::result_flag_unsupported_version,
    unsupported_protection = protocol_constants::result_flag_unsupported_protection,
    sequence_gap = protocol_constants::result_flag_sequence_gap,
    uart_framing_error = protocol_constants::result_flag_uart_framing_error,
    internal_overflow = protocol_constants::result_flag_internal_overflow,
};

struct ExtensionTlv {
    std::uint8_t type_id;
    Bytes value;

    [[nodiscard]] bool operator==(const ExtensionTlv&) const = default;
};

struct TokenRecord {
    std::uint32_t stream_id;
    std::uint32_t sequence;
    std::uint32_t token_id;
    std::uint8_t importance{0U};
    std::uint64_t generated_time_us{0U};
    std::uint64_t deadline_us{0U};
    std::uint8_t flags{0U};
    std::vector<ExtensionTlv> extensions;

    [[nodiscard]] bool operator==(const TokenRecord&) const = default;
};

struct ProtectionRequest {
    ProtectionMode mode;
    std::uint16_t block_length_bits;
    std::uint8_t repetition_count{1U};
    std::uint16_t code_rate_num{1U};
    std::uint16_t code_rate_den{1U};
    std::uint16_t flags{0U};

    [[nodiscard]] bool operator==(const ProtectionRequest&) const = default;
};

struct ChannelState {
    std::uint16_t channel_quality{0U};
    std::uint8_t flags{0U};

    [[nodiscard]] bool operator==(const ChannelState&) const = default;
};

struct ResultStatus {
    std::uint32_t flags{0U};
    std::uint16_t corrected_count{0U};
    std::uint16_t detected_error_count{0U};

    [[nodiscard]] bool operator==(const ResultStatus&) const = default;
};

struct TokenRequest {
    TokenRecord token;
    ProtectionRequest protection;
    ChannelState channel;

    [[nodiscard]] bool operator==(const TokenRequest&) const = default;
};

struct TokenResult {
    TokenRecord token;
    ResultStatus status;

    [[nodiscard]] bool operator==(const TokenResult&) const = default;
};

struct ErrorResponse {
    std::uint32_t flags;
    std::uint8_t request_message_type;

    [[nodiscard]] bool operator==(const ErrorResponse&) const = default;
};

[[nodiscard]] Bytes pack_token_record(const TokenRecord& value);
[[nodiscard]] TokenRecord unpack_token_record(std::span<const std::uint8_t> data);
[[nodiscard]] Bytes pack_protection_request(const ProtectionRequest& value);
[[nodiscard]] ProtectionRequest unpack_protection_request(
    std::span<const std::uint8_t> data
);
[[nodiscard]] Bytes pack_channel_state(const ChannelState& value);
[[nodiscard]] ChannelState unpack_channel_state(std::span<const std::uint8_t> data);
[[nodiscard]] Bytes pack_result_status(const ResultStatus& value);
[[nodiscard]] ResultStatus unpack_result_status(std::span<const std::uint8_t> data);
[[nodiscard]] Bytes pack_token_request(const TokenRequest& value);
[[nodiscard]] TokenRequest unpack_token_request(std::span<const std::uint8_t> data);
[[nodiscard]] Bytes pack_token_result(const TokenResult& value);
[[nodiscard]] TokenResult unpack_token_result(std::span<const std::uint8_t> data);
[[nodiscard]] Bytes pack_error_response(const ErrorResponse& value);
[[nodiscard]] ErrorResponse unpack_error_response(std::span<const std::uint8_t> data);
[[nodiscard]] std::uint32_t next_sequence(std::uint32_t sequence) noexcept;

}
