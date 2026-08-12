#pragma once

#include <cstddef>
#include <cstdint>
#include <span>
#include <vector>

namespace reference {

using Bytes = std::vector<std::uint8_t>;
using Bits = std::vector<std::uint8_t>;

/** @note Frame data is packed byte-zero first and LSB-first within each byte. */
void validate_bit_length(std::span<const std::uint8_t> data, std::size_t bit_length);

[[nodiscard]] Bits unpack_bits(
    std::span<const std::uint8_t> data,
    std::size_t bit_length
);

[[nodiscard]] Bytes pack_bits(std::span<const std::uint8_t> bits);

}
