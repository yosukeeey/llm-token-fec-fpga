#include "reference/protocol.hpp"

#include <algorithm>
#include <array>
#include <limits>

#include "reference/crc32c.hpp"

namespace reference {
namespace {

constexpr std::array<std::uint8_t, 2> sof{0xA5U, 0x5AU};
constexpr std::size_t header_bytes = 6U;
constexpr std::size_t crc_bytes = 4U;
constexpr std::size_t minimum_frame_bytes = sof.size() + header_bytes + crc_bytes;

void append_u16(Bytes& output, const std::uint16_t value) {
    output.push_back(static_cast<std::uint8_t>(value & 0xFFU));
    output.push_back(static_cast<std::uint8_t>((value >> 8U) & 0xFFU));
}

void append_u32(Bytes& output, const std::uint32_t value) {
    for (unsigned shift = 0; shift < 32U; shift += 8U) {
        output.push_back(static_cast<std::uint8_t>((value >> shift) & 0xFFU));
    }
}

std::uint16_t read_u16(const std::span<const std::uint8_t> data, const std::size_t offset) {
    return static_cast<std::uint16_t>(
        data[offset] | (static_cast<std::uint16_t>(data[offset + 1U]) << 8U)
    );
}

std::uint32_t read_u32(const std::span<const std::uint8_t> data, const std::size_t offset) {
    std::uint32_t value = 0;
    for (unsigned index = 0; index < 4U; ++index) {
        value |= static_cast<std::uint32_t>(data[offset + index]) << (index * 8U);
    }
    return value;
}

}

Bytes serialize_frame(const Frame& frame) {
    if (frame.payload.size() > max_payload_bytes) {
        throw FrameLengthError("payload exceeds Frame V0 maximum");
    }
    if (frame.payload.size() > std::numeric_limits<std::uint16_t>::max()) {
        throw FrameLengthError("payload cannot be represented by length field");
    }
    Bytes output{sof.begin(), sof.end()};
    output.push_back(frame.version);
    output.push_back(frame.message_type);
    append_u16(output, frame.flags);
    append_u16(output, static_cast<std::uint16_t>(frame.payload.size()));
    output.insert(output.end(), frame.payload.begin(), frame.payload.end());
    const auto crc_input = std::span<const std::uint8_t>(output).subspan(sof.size());
    append_u32(output, crc32c(crc_input));
    return output;
}

Frame parse_frame(const std::span<const std::uint8_t> data) {
    if (data.size() < minimum_frame_bytes) {
        throw FrameLengthError("frame is shorter than minimum size");
    }
    if (!std::equal(sof.begin(), sof.end(), data.begin())) {
        throw ProtocolError("frame does not start with SOF");
    }
    const auto version = data[2];
    const auto message_type = data[3];
    const auto flags = read_u16(data, 4);
    const auto payload_length = read_u16(data, 6);
    if (payload_length > max_payload_bytes) {
        throw FrameLengthError("payload length exceeds Frame V0 maximum");
    }
    const auto expected_size = minimum_frame_bytes + payload_length;
    if (data.size() != expected_size) {
        throw FrameLengthError("frame length does not match payload length");
    }
    if (version != frame_version) {
        throw FrameVersionError("unsupported Frame version");
    }
    const auto crc_offset = sof.size() + header_bytes + payload_length;
    const auto crc_input = data.subspan(sof.size(), header_bytes + payload_length);
    if (crc32c(crc_input) != read_u32(data, crc_offset)) {
        throw FrameCrcError("CRC mismatch");
    }
    const auto payload_begin = data.begin() + static_cast<std::ptrdiff_t>(sof.size() + header_bytes);
    const auto payload_end = payload_begin + payload_length;
    return {message_type, Bytes(payload_begin, payload_end), flags, version};
}

std::vector<Frame> FrameParser::feed(const std::span<const std::uint8_t> data) {
    buffer_.insert(buffer_.end(), data.begin(), data.end());
    std::vector<Frame> frames;
    while (true) {
        const auto sof_position = std::search(buffer_.begin(), buffer_.end(), sof.begin(), sof.end());
        if (sof_position == buffer_.end()) {
            const auto keep_first_sof_byte = !buffer_.empty() && buffer_.back() == sof.front();
            buffer_ = keep_first_sof_byte ? Bytes{sof.front()} : Bytes{};
            break;
        }
        buffer_.erase(buffer_.begin(), sof_position);
        if (buffer_.size() < sof.size() + header_bytes) {
            break;
        }
        const auto payload_length = read_u16(buffer_, 6);
        if (payload_length > max_payload_bytes) {
            errors_.emplace_back("payload length exceeds maximum");
            buffer_.erase(buffer_.begin());
            continue;
        }
        const auto frame_length = minimum_frame_bytes + payload_length;
        if (buffer_.size() < frame_length) {
            break;
        }
        try {
            frames.push_back(parse_frame(std::span<const std::uint8_t>(buffer_).first(frame_length)));
            buffer_.erase(buffer_.begin(), buffer_.begin() + static_cast<std::ptrdiff_t>(frame_length));
        } catch (const ProtocolError& error) {
            errors_.push_back(error.what());
            buffer_.erase(buffer_.begin());
        }
    }
    return frames;
}

std::size_t FrameParser::buffered_bytes() const noexcept {
    return buffer_.size();
}

const std::vector<std::string>& FrameParser::errors() const noexcept {
    return errors_;
}

}
