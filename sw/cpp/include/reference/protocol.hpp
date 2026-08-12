#pragma once

#include <cstddef>
#include <cstdint>
#include <span>
#include <stdexcept>
#include <string>
#include <vector>

#include "reference/bits.hpp"

namespace reference {

inline constexpr std::uint8_t frame_version = 0;
inline constexpr std::size_t max_payload_bytes = 1024;

enum class MessageType : std::uint8_t {
    ping = 0x01,
    pong = 0x02,
    test_request = 0x10,
    test_result = 0x11,
    error_response = 0x7F,
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
