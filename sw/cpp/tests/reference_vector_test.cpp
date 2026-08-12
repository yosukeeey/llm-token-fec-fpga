#include <cstdint>
#include <exception>
#include <filesystem>
#include <iostream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

#include "reference/bits.hpp"
#include "reference/crc32c.hpp"
#include "reference/fec.hpp"
#include "reference/protocol.hpp"
#include "reference/vector.hpp"

namespace {

struct ActualResult {
    reference::Bytes encoded;
    std::size_t encoded_bit_length;
    reference::Bytes decoded;
    std::size_t decoded_bit_length;
    std::vector<std::string> status;
};

std::int64_t integer_parameter(
    const reference::TestVector& vector,
    const std::string& name
) {
    const auto found = vector.parameters.find(name);
    if (found == vector.parameters.end()) {
        throw std::invalid_argument("missing parameter: " + name);
    }
    return std::get<std::int64_t>(found->second);
}

ActualResult evaluate(const reference::TestVector& vector) {
    if (vector.algorithm == "crc32c") {
        const auto checksum = reference::crc32c(vector.input);
        reference::Bytes checksum_bytes;
        for (unsigned shift = 0; shift < 32U; shift += 8U) {
            checksum_bytes.push_back(static_cast<std::uint8_t>((checksum >> shift) & 0xFFU));
        }
        return {checksum_bytes, 32, checksum_bytes, 32, {}};
    }
    if (vector.algorithm == "even_parity") {
        const reference::Bits parity{reference::even_parity_bit(
            vector.input,
            vector.input_bit_length
        )};
        const auto parity_data = reference::pack_bits(parity);
        return {parity_data, 1, parity_data, 1, {}};
    }
    if (vector.algorithm == "repetition") {
        const auto repetition_count = static_cast<std::size_t>(
            integer_parameter(vector, "repetition_count")
        );
        const auto encoded = reference::repetition_encode(
            vector.input,
            vector.input_bit_length,
            repetition_count
        );
        const auto decoded = reference::repetition_decode(
            vector.received,
            vector.encoded_bit_length,
            repetition_count
        );
        return {
            encoded.data,
            encoded.bit_length,
            decoded.data,
            decoded.bit_length,
            decoded.corrected_groups == 0U
                ? std::vector<std::string>{}
                : std::vector<std::string>{"FEC_CORRECTED"},
        };
    }
    if (vector.algorithm == "hamming74") {
        const auto encoded = reference::hamming74_encode(
            vector.input,
            vector.input_bit_length
        );
        const auto decoded = reference::hamming74_decode(
            vector.received,
            vector.encoded_bit_length,
            vector.decoded_bit_length
        );
        return {
            encoded.data,
            encoded.bit_length,
            decoded.data,
            decoded.bit_length,
            decoded.corrected_codewords == 0U
                ? std::vector<std::string>{}
                : std::vector<std::string>{"FEC_CORRECTED"},
        };
    }
    if (vector.algorithm == "frame_v0") {
        const auto message_type = static_cast<std::uint8_t>(
            integer_parameter(vector, "message_type")
        );
        const auto flags = static_cast<std::uint16_t>(integer_parameter(vector, "flags"));
        const reference::Frame frame{message_type, vector.input, flags};
        const auto encoded = reference::serialize_frame(frame);
        const auto decoded = reference::parse_frame(vector.received);
        return {
            encoded,
            encoded.size() * 8U,
            decoded.payload,
            decoded.payload.size() * 8U,
            {},
        };
    }
    throw std::invalid_argument("unknown algorithm: " + vector.algorithm);
}

void check_vector(const reference::TestVector& vector) {
    const auto actual = evaluate(vector);
    if (actual.encoded != vector.encoded) {
        throw std::runtime_error(vector.case_id + ": encoded bytes mismatch");
    }
    if (actual.encoded_bit_length != vector.encoded_bit_length) {
        throw std::runtime_error(vector.case_id + ": encoded bit length mismatch");
    }
    if (actual.decoded != vector.decoded) {
        throw std::runtime_error(vector.case_id + ": decoded bytes mismatch");
    }
    if (actual.decoded_bit_length != vector.decoded_bit_length) {
        throw std::runtime_error(vector.case_id + ": decoded bit length mismatch");
    }
    if (actual.status != vector.expected_status) {
        throw std::runtime_error(vector.case_id + ": status mismatch");
    }
}

}

int main(const int argument_count, const char* const arguments[]) {
    try {
        if (argument_count != 2) {
            throw std::invalid_argument("expected vector directory argument");
        }
        const std::filesystem::path vector_directory(arguments[1]);
        const std::vector<std::string_view> files{
            "crc32c.jsonl",
            "parity.jsonl",
            "repetition.jsonl",
            "hamming74.jsonl",
            "protocol.jsonl",
        };
        std::size_t checked = 0;
        for (const auto file : files) {
            for (const auto& vector : reference::read_test_vectors(vector_directory / file)) {
                check_vector(vector);
                ++checked;
            }
        }
        std::cout << "reference_vector_test: " << checked << " vectors passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "reference_vector_test: " << error.what() << '\n';
        return 1;
    }
}
