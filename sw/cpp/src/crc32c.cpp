#include "reference/crc32c.hpp"

namespace reference {

std::uint32_t crc32c_update(
    std::uint32_t crc,
    const std::span<const std::uint8_t> data
) {
    for (const auto byte : data) {
        crc ^= byte;
        for (int bit = 0; bit < 8; ++bit) {
            const auto polynomial = (crc & 1U) != 0U
                ? crc32c_reflected_polynomial
                : 0U;
            crc = (crc >> 1U) ^ polynomial;
        }
    }
    return crc;
}

std::uint32_t crc32c(const std::span<const std::uint8_t> data) {
    return crc32c_update(crc32c_initial, data) ^ crc32c_xor_out;
}

}
