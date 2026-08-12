#pragma once

#include <cstdint>
#include <span>

#include "reference/protocol_constants.hpp"

namespace reference {

inline constexpr auto crc32c_reflected_polynomial = static_cast<std::uint32_t>(
    protocol_constants::crc32c_reflected_polynomial
);
inline constexpr auto crc32c_initial = static_cast<std::uint32_t>(
    protocol_constants::crc32c_initial
);
inline constexpr auto crc32c_xor_out = static_cast<std::uint32_t>(
    protocol_constants::crc32c_xor_out
);

[[nodiscard]] std::uint32_t crc32c_update(
    std::uint32_t crc,
    std::span<const std::uint8_t> data
);

[[nodiscard]] std::uint32_t crc32c(std::span<const std::uint8_t> data);

}
