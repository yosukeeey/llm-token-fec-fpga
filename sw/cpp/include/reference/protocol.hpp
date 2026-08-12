#pragma once

#include <cstddef>
#include <cstdint>
#include <span>
#include <stdexcept>
#include <string>
#include <vector>

#include "reference/bits.hpp"
#include "reference/protocol_constants.hpp"

namespace reference {

inline constexpr auto frame_version = static_cast<std::uint8_t>(
    protocol_constants::frame_version
);
inline constexpr auto max_payload_bytes = static_cast<std::size_t>(
    protocol_constants::frame_max_payload_bytes
);

enum class MessageType : std::uint8_t {
    ping = protocol_constants::message_type_ping,
    pong = protocol_constants::message_type_pong,
    token_request = protocol_constants::message_type_token_request,
    token_result = protocol_constants::message_type_token_result,
    /** @note Frame V0 used test names before the Token payload contract was fixed. */
    test_request = token_request,
    test_result = token_result,
    error_response = protocol_constants::message_type_error_response,
};

class ProtocolError : public std::runtime_error {
public:
    using std::runtime_error::runtime_error;
};

class FrameLengthError : public ProtocolError {
public:
    using ProtocolError::ProtocolError;
};

class FrameCrcError : public ProtocolError {
public:
    using ProtocolError::ProtocolError;
};

class FrameVersionError : public ProtocolError {
public:
    using ProtocolError::ProtocolError;
};

struct Frame {
    std::uint8_t message_type;
    Bytes payload;
    std::uint16_t flags{0};
    std::uint8_t version{frame_version};

    [[nodiscard]] bool operator==(const Frame&) const = default;
};

/** @note Frame V0 wire fields are little-endian and protected by CRC-32C. */
[[nodiscard]] Bytes serialize_frame(const Frame& frame);

[[nodiscard]] Frame parse_frame(std::span<const std::uint8_t> data);

class FrameParser {
public:
    [[nodiscard]] std::vector<Frame> feed(std::span<const std::uint8_t> data);

    [[nodiscard]] std::size_t buffered_bytes() const noexcept;

    [[nodiscard]] const std::vector<std::string>& errors() const noexcept;

private:
    Bytes buffer_;
    std::vector<std::string> errors_;
};

}
