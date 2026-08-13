#include "reference/hex.hpp"

#include <array>
#include <stdexcept>

namespace reference {
namespace {

std::uint8_t decode_nibble(const char character) {
    if (character >= '0' && character <= '9') {
        return static_cast<std::uint8_t>(character - '0');
    }
    if (character >= 'a' && character <= 'f') {
        return static_cast<std::uint8_t>(character - 'a' + 10);
    }
    throw std::invalid_argument("hex must be lowercase and prefix-free");
}

}

Bytes hex_decode(const std::string_view value) {
    if (value.size() % 2U != 0U) {
        throw std::invalid_argument("hex must contain an even number of characters");
    }
    Bytes output;
    output.reserve(value.size() / 2U);
    for (std::size_t offset = 0; offset < value.size(); offset += 2U) {
        output.push_back(static_cast<std::uint8_t>(
            (decode_nibble(value[offset]) << 4U) | decode_nibble(value[offset + 1U])
        ));
    }
    return output;
}

std::string hex_encode(const std::span<const std::uint8_t> data) {
    constexpr std::array<char, 16> digits{
        '0', '1', '2', '3', '4', '5', '6', '7',
        '8', '9', 'a', 'b', 'c', 'd', 'e', 'f',
    };
    std::string output;
    output.reserve(data.size() * 2U);
    for (const auto byte : data) {
        output.push_back(digits[byte >> 4U]);
        output.push_back(digits[byte & 0x0FU]);
    }
    return output;
}

}
