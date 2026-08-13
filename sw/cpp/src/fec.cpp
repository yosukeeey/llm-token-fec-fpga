#include "reference/fec.hpp"

#include <algorithm>
#include <array>
#include <numeric>
#include <stdexcept>

namespace reference {
namespace {

void validate_repetition_count(const std::size_t repetition_count) {
    if (repetition_count != 1U && repetition_count != 3U) {
        throw std::invalid_argument("repetition_count must be 1 or 3");
    }
}

std::array<std::uint8_t, 7> encode_nibble(
    const std::array<std::uint8_t, 4>& data
) {
    const auto [d0, d1, d2, d3] = data;
    const auto p1 = static_cast<std::uint8_t>(d0 ^ d1 ^ d3);
    const auto p2 = static_cast<std::uint8_t>(d0 ^ d2 ^ d3);
    const auto p4 = static_cast<std::uint8_t>(d1 ^ d2 ^ d3);
    return {p1, p2, d0, p4, d1, d2, d3};
}

}

std::uint8_t even_parity_bit(
    const std::span<const std::uint8_t> data,
    const std::size_t bit_length
) {
    const auto bits = unpack_bits(data, bit_length);
    return static_cast<std::uint8_t>(
        std::accumulate(bits.begin(), bits.end(), 0U) & 1U
    );
}

bool has_even_parity(
    const std::span<const std::uint8_t> data,
    const std::size_t bit_length,
    const std::uint8_t parity_bit
) {
    if (parity_bit > 1U) {
        throw std::invalid_argument("parity_bit must be 0 or 1");
    }
    return even_parity_bit(data, bit_length) == parity_bit;
}

EncodedBits repetition_encode(
    const std::span<const std::uint8_t> data,
    const std::size_t bit_length,
    const std::size_t repetition_count
) {
    validate_repetition_count(repetition_count);
    const auto input_bits = unpack_bits(data, bit_length);
    Bits encoded_bits;
    encoded_bits.reserve(bit_length * repetition_count);
    for (const auto bit : input_bits) {
        encoded_bits.insert(encoded_bits.end(), repetition_count, bit);
    }
    return {pack_bits(encoded_bits), encoded_bits.size()};
}

RepetitionDecodeResult repetition_decode(
    const std::span<const std::uint8_t> encoded,
    const std::size_t encoded_bit_length,
    const std::size_t repetition_count
) {
    validate_repetition_count(repetition_count);
    if (encoded_bit_length % repetition_count != 0U) {
        throw std::invalid_argument("incomplete repetition group");
    }
    const auto encoded_bits = unpack_bits(encoded, encoded_bit_length);
    Bits decoded_bits;
    decoded_bits.reserve(encoded_bit_length / repetition_count);
    std::size_t corrected_groups = 0;
    for (std::size_t offset = 0; offset < encoded_bits.size(); offset += repetition_count) {
        const auto begin = encoded_bits.begin() + static_cast<std::ptrdiff_t>(offset);
        const auto ones = std::accumulate(begin, begin + repetition_count, 0U);
        const auto decoded_bit = static_cast<std::uint8_t>(ones > repetition_count / 2U);
        decoded_bits.push_back(decoded_bit);
        corrected_groups += static_cast<std::size_t>(
            std::any_of(begin, begin + repetition_count, [decoded_bit](const auto bit) {
                return bit != decoded_bit;
            })
        );
    }
    return {pack_bits(decoded_bits), decoded_bits.size(), corrected_groups};
}

EncodedBits hamming74_encode(
    const std::span<const std::uint8_t> data,
    const std::size_t bit_length
) {
    const auto input_bits = unpack_bits(data, bit_length);
    Bits encoded_bits;
    encoded_bits.reserve(((bit_length + 3U) / 4U) * 7U);
    for (std::size_t offset = 0; offset < bit_length; offset += 4U) {
        std::array<std::uint8_t, 4> nibble{};
        const auto count = std::min<std::size_t>(4U, bit_length - offset);
        std::copy_n(input_bits.begin() + static_cast<std::ptrdiff_t>(offset), count, nibble.begin());
        const auto codeword = encode_nibble(nibble);
        encoded_bits.insert(encoded_bits.end(), codeword.begin(), codeword.end());
    }
    return {pack_bits(encoded_bits), encoded_bits.size()};
}

HammingDecodeResult hamming74_decode(
    const std::span<const std::uint8_t> encoded,
    const std::size_t encoded_bit_length,
    const std::size_t output_bit_length
) {
    if (encoded_bit_length % 7U != 0U) {
        throw std::invalid_argument("incomplete Hamming codeword");
    }
    if (output_bit_length > encoded_bit_length / 7U * 4U) {
        throw std::invalid_argument("output_bit_length exceeds codeword capacity");
    }
    const auto encoded_bits = unpack_bits(encoded, encoded_bit_length);
    Bits decoded_bits;
    decoded_bits.reserve(encoded_bit_length / 7U * 4U);
    std::size_t corrected_codewords = 0;
    for (std::size_t offset = 0; offset < encoded_bit_length; offset += 7U) {
        std::array<std::uint8_t, 7> codeword{};
        std::copy_n(
            encoded_bits.begin() + static_cast<std::ptrdiff_t>(offset),
            codeword.size(),
            codeword.begin()
        );
        const auto s1 = static_cast<std::uint8_t>(
            codeword[0] ^ codeword[2] ^ codeword[4] ^ codeword[6]
        );
        const auto s2 = static_cast<std::uint8_t>(
            codeword[1] ^ codeword[2] ^ codeword[5] ^ codeword[6]
        );
        const auto s4 = static_cast<std::uint8_t>(
            codeword[3] ^ codeword[4] ^ codeword[5] ^ codeword[6]
        );
        const auto syndrome = static_cast<std::size_t>(s1 | (s2 << 1U) | (s4 << 2U));
        if (syndrome != 0U) {
            codeword[syndrome - 1U] ^= 1U;
            ++corrected_codewords;
        }
        decoded_bits.insert(
            decoded_bits.end(),
            {codeword[2], codeword[4], codeword[5], codeword[6]}
        );
    }
    decoded_bits.resize(output_bit_length);
    return {pack_bits(decoded_bits), output_bit_length, corrected_codewords};
}

}
