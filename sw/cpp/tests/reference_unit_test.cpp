#include <array>
#include <cstdint>
#include <exception>
#include <iostream>
#include <stdexcept>
#include <string_view>

#include "reference/bits.hpp"
#include "reference/crc32c.hpp"
#include "reference/fec.hpp"
#include "reference/hex.hpp"
#include "reference/protocol.hpp"

namespace {

void require(const bool condition, const std::string_view message) {
    if (!condition) {
        throw std::runtime_error(std::string(message));
    }
}

void test_bits_and_hex() {
    const reference::Bits bits{1, 0, 1, 0, 0, 1, 0, 1};
    const reference::Bytes a5{0xA5U};
    require(reference::pack_bits(bits) == a5, "LSB-first pack failed");
    require(reference::unpack_bits(a5, 8) == bits, "LSB-first unpack failed");
    require(reference::hex_decode("a5") == a5, "hex decode failed");
    require(reference::hex_encode(a5) == "a5", "hex encode failed");
}

void test_crc32c() {
    const reference::Bytes check{'1', '2', '3', '4', '5', '6', '7', '8', '9'};
    require(reference::crc32c({}) == 0U, "empty CRC-32C failed");
    require(reference::crc32c(check) == 0xE3069283U, "CRC-32C check failed");
}

void test_fec() {
    const reference::Bytes a5{0xA5U};
    require(reference::even_parity_bit(a5, 8) == 0U, "parity failed");

    const auto repetition = reference::repetition_encode(a5, 8, 3);
    require(reference::hex_encode(repetition.data) == "c781e3", "repetition encode failed");
    const auto repetition_decoded = reference::repetition_decode(
        repetition.data,
        repetition.bit_length,
        3
    );
    require(repetition_decoded.data == a5, "repetition decode failed");

    for (std::uint8_t nibble = 0; nibble < 16U; ++nibble) {
        const reference::Bytes data{nibble};
        const auto encoded = reference::hamming74_encode(data, 4);
        for (std::size_t error_position = 0; error_position < 7U; ++error_position) {
            auto received = encoded.data;
            received[error_position / 8U] ^= static_cast<std::uint8_t>(
                1U << (error_position % 8U)
            );
            const auto decoded = reference::hamming74_decode(received, 7, 4);
            require(decoded.data == data, "Hamming single-error correction failed");
            require(decoded.corrected_codewords == 1U, "Hamming correction count failed");
        }
    }
}

void test_protocol() {
    const reference::Frame ping{static_cast<std::uint8_t>(reference::MessageType::ping)};
    const auto encoded = reference::serialize_frame(ping);
    require(
        reference::hex_encode(encoded) == "a55a00010000000026133b6f",
        "Frame V0 known answer failed"
    );
    require(reference::parse_frame(encoded) == ping, "Frame V0 round trip failed");

    auto invalid = encoded;
    invalid.back() ^= 1U;
    const reference::Frame pong{static_cast<std::uint8_t>(reference::MessageType::pong)};
    auto stream = invalid;
    const auto pong_bytes = reference::serialize_frame(pong);
    stream.insert(stream.end(), pong_bytes.begin(), pong_bytes.end());
    reference::FrameParser parser;
    const auto frames = parser.feed(stream);
    require(frames == std::vector<reference::Frame>{pong}, "Frame resynchronization failed");
    require(parser.errors().size() == 1U, "Frame parser error count failed");
}

}

int main() {
    try {
        test_bits_and_hex();
        test_crc32c();
        test_fec();
        test_protocol();
        std::cout << "reference_unit_test: passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "reference_unit_test: " << error.what() << '\n';
        return 1;
    }
}
