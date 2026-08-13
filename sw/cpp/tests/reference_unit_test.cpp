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
#include "reference/protocol_constants.hpp"
#include "reference/types.hpp"

namespace {

static_assert(reference::protocol_constants::token_record_base_size == 40U);
static_assert(reference::protocol_constants::token_record_reserved_1_offset == 38U);
static_assert(reference::protocol_constants::protection_request_size == 16U);
static_assert(reference::protocol_constants::channel_state_size == 4U);
static_assert(reference::protocol_constants::result_status_size == 8U);

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

void test_protocol_types() {
    const reference::TokenRecord token{
        0x11223344U,
        0xFFFFFFFFU,
        0x55667788U,
        0U,
        1'000U,
        2'000U,
        static_cast<std::uint8_t>(
            reference::protocol_constants::token_flag_generated_time_valid
            | reference::protocol_constants::token_flag_deadline_valid
        ),
        {{0x80U, {0xAAU, 0x55U}}},
    };
    const auto token_bytes = reference::pack_token_record(token);
    require(
        reference::hex_encode(token_bytes)
            == "0103280044332211ffffffff8877665500000000"
               "e803000000000000d00700000000000004000000"
               "8002aa55",
        "TokenRecord known answer failed"
    );
    require(reference::unpack_token_record(token_bytes) == token, "TokenRecord round trip failed");

    const reference::ProtectionRequest protection{
        reference::ProtectionMode::hamming_7_4,
        static_cast<std::uint16_t>(token_bytes.size() * 8U),
        1U,
        4U,
        7U,
    };
    const reference::TokenRequest request{
        token,
        protection,
        {0x8000U, static_cast<std::uint8_t>(reference::ChannelFlag::quality_valid)},
    };
    const auto request_bytes = reference::pack_token_request(request);
    require(
        reference::unpack_token_request(request_bytes) == request,
        "TokenRequest round trip failed"
    );

    const reference::TokenResult result{
        token,
        {static_cast<std::uint32_t>(reference::ResultFlag::fec_corrected), 1U, 0U},
    };
    require(
        reference::unpack_token_result(reference::pack_token_result(result)) == result,
        "TokenResult round trip failed"
    );
    require(reference::next_sequence(0xFFFFFFFFU) == 0U, "sequence wrap failed");
}

}

int main() {
    try {
        test_bits_and_hex();
        test_crc32c();
        test_fec();
        test_protocol();
        test_protocol_types();
        std::cout << "reference_unit_test: passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "reference_unit_test: " << error.what() << '\n';
        return 1;
    }
}
