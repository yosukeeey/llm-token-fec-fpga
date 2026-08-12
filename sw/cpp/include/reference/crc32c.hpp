#pragma once

#include <cstdint>
#include <span>

namespace reference {

inline constexpr std::uint32_t crc32c_reflected_polynomial = 0x82F63B78U;
inline constexpr std::uint32_t crc32c_initial = 0xFFFFFFFFU;
inline constexpr std::uint32_t crc32c_xor_out = 0xFFFFFFFFU;

[[nodiscard]] std::uint32_t crc32c_update(
    std::uint32_t crc,
    std::span<const std::uint8_t> data
);

[[nodiscard]] std::uint32_t crc32c(std::span<const std::uint8_t> data);

}
