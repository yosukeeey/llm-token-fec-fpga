#include "reference/bits.hpp"

#include <stdexcept>

namespace reference {

void validate_bit_length(
    const std::span<const std::uint8_t> data,
    const std::size_t bit_length
) {
    if (bit_length > data.size() * 8U) {
        throw std::invalid_argument("bit_length exceeds data size");
    }
    const auto expected_bytes = (bit_length + 7U) / 8U;
    if (data.size() != expected_bytes) {
        throw std::invalid_argument("data does not use minimal byte length");
    }
    if (bit_length % 8U != 0U && !data.empty()) {
        const auto used_bits = static_cast<unsigned>(bit_length % 8U);
        const auto unused_mask = static_cast<std::uint8_t>(0xFFU << used_bits);
        if ((data.back() & unused_mask) != 0U) {
            throw std::invalid_argument("unused high bits must be zero");
        }
    }
}

Bits unpack_bits(
    const std::span<const std::uint8_t> data,
    const std::size_t bit_length
) {
    validate_bit_length(data, bit_length);
    Bits bits;
    bits.reserve(bit_length);
    for (std::size_t index = 0; index < bit_length; ++index) {
        bits.push_back(static_cast<std::uint8_t>(
            (data[index / 8U] >> (index % 8U)) & 1U
        ));
    }
    return bits;
}

Bytes pack_bits(const std::span<const std::uint8_t> bits) {
    Bytes output((bits.size() + 7U) / 8U, 0U);
    for (std::size_t index = 0; index < bits.size(); ++index) {
        const auto bit = bits[index];
        if (bit > 1U) {
            throw std::invalid_argument("bits must contain only 0 or 1");
        }
        output[index / 8U] |= static_cast<std::uint8_t>(bit << (index % 8U));
    }
    return output;
}

}
