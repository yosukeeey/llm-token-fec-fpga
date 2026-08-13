#pragma once

#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <map>
#include <string>
#include <variant>
#include <vector>

#include "reference/bits.hpp"

namespace reference {

using Parameter = std::variant<std::int64_t, std::string>;

struct TestVector {
    std::string case_id;
    std::string algorithm;
    Bytes input;
    std::size_t input_bit_length;
    Bytes encoded;
    std::size_t encoded_bit_length;
    Bytes received;
    Bytes decoded;
    std::size_t decoded_bit_length;
    std::map<std::string, Parameter> parameters;
    std::vector<std::size_t> error_bit_positions;
    std::vector<std::string> expected_status;
    std::uint32_t schema_version;
};

/** @note JSONL records are the versioned boundary shared by all implementations. */
[[nodiscard]] std::vector<TestVector> read_test_vectors(
    const std::filesystem::path& path
);

}
