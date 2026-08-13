#pragma once

#include <cstddef>
#include <cstdint>
#include <span>

#include "reference/bits.hpp"

namespace reference {

struct EncodedBits {
    Bytes data;
    std::size_t bit_length;

    [[nodiscard]] bool operator==(const EncodedBits&) const = default;
};

struct RepetitionDecodeResult {
    Bytes data;
    std::size_t bit_length;
    std::size_t corrected_groups;
};

struct HammingDecodeResult {
    Bytes data;
    std::size_t bit_length;
    std::size_t corrected_codewords;
};

[[nodiscard]] std::uint8_t even_parity_bit(
    std::span<const std::uint8_t> data,
    std::size_t bit_length
);

[[nodiscard]] bool has_even_parity(
    std::span<const std::uint8_t> data,
    std::size_t bit_length,
    std::uint8_t parity_bit
);

[[nodiscard]] EncodedBits repetition_encode(
    std::span<const std::uint8_t> data,
    std::size_t bit_length,
    std::size_t repetition_count
);

/** @note Group disagreement cannot distinguish one-bit from two-bit corruption. */
[[nodiscard]] RepetitionDecodeResult repetition_decode(
    std::span<const std::uint8_t> encoded,
    std::size_t encoded_bit_length,
    std::size_t repetition_count
);

/** @note The wire mapping from bit zero is p1,p2,d0,p4,d1,d2,d3. */
[[nodiscard]] EncodedBits hamming74_encode(
    std::span<const std::uint8_t> data,
    std::size_t bit_length
);

/** @note Hamming(7,4) is SEC, not DED; double errors are not reliably detected. */
[[nodiscard]] HammingDecodeResult hamming74_decode(
    std::span<const std::uint8_t> encoded,
    std::size_t encoded_bit_length,
    std::size_t output_bit_length
);

}
