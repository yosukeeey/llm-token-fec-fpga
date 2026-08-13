#include "reference/vector.hpp"

#include <fstream>
#include <limits>
#include <set>
#include <stdexcept>

#include <nlohmann/json.hpp>

#include "reference/hex.hpp"

namespace reference {
namespace {

using Json = nlohmann::json;

std::size_t read_size(const Json& value, const char* field) {
    const auto number = value.at(field).get<std::uint64_t>();
    if (number > std::numeric_limits<std::size_t>::max()) {
        throw std::out_of_range(std::string(field) + " exceeds size_t");
    }
    return static_cast<std::size_t>(number);
}

std::map<std::string, Parameter> read_parameters(const Json& value) {
    std::map<std::string, Parameter> parameters;
    for (const auto& [name, parameter] : value.at("parameters").items()) {
        if (parameter.is_number_integer()) {
            parameters.emplace(name, parameter.get<std::int64_t>());
        } else if (parameter.is_string()) {
            parameters.emplace(name, parameter.get<std::string>());
        } else {
            throw std::invalid_argument("parameter must be an integer or string");
        }
    }
    return parameters;
}

TestVector parse_vector(const Json& value) {
    if (!value.is_object()) {
        throw std::invalid_argument("vector must be a JSON object");
    }
    TestVector vector{
        value.at("case_id").get<std::string>(),
        value.at("algorithm").get<std::string>(),
        hex_decode(value.at("input_hex").get<std::string>()),
        read_size(value, "input_bit_length"),
        hex_decode(value.at("encoded_hex").get<std::string>()),
        read_size(value, "encoded_bit_length"),
        hex_decode(value.at("received_hex").get<std::string>()),
        hex_decode(value.at("decoded_hex").get<std::string>()),
        read_size(value, "decoded_bit_length"),
        read_parameters(value),
        value.at("error_bit_positions").get<std::vector<std::size_t>>(),
        value.at("expected_status").get<std::vector<std::string>>(),
        value.at("schema_version").get<std::uint32_t>(),
    };
    if (vector.schema_version != 0U) {
        throw std::invalid_argument("unsupported vector schema");
    }
    if (vector.case_id.empty() || vector.algorithm.empty()) {
        throw std::invalid_argument("case_id and algorithm must be non-empty");
    }
    validate_bit_length(vector.input, vector.input_bit_length);
    validate_bit_length(vector.encoded, vector.encoded_bit_length);
    validate_bit_length(vector.received, vector.encoded_bit_length);
    validate_bit_length(vector.decoded, vector.decoded_bit_length);
    const std::set<std::size_t> unique_positions(
        vector.error_bit_positions.begin(),
        vector.error_bit_positions.end()
    );
    if (unique_positions.size() != vector.error_bit_positions.size()) {
        throw std::invalid_argument("error positions must be unique");
    }
    for (const auto position : vector.error_bit_positions) {
        if (position >= vector.encoded_bit_length) {
            throw std::invalid_argument("error position exceeds encoded data");
        }
    }
    return vector;
}

}

std::vector<TestVector> read_test_vectors(const std::filesystem::path& path) {
    std::ifstream input(path);
    if (!input) {
        throw std::runtime_error("cannot open vector file: " + path.string());
    }
    std::vector<TestVector> vectors;
    std::set<std::string> case_ids;
    std::string line;
    std::size_t line_number = 0;
    while (std::getline(input, line)) {
        ++line_number;
        try {
            auto vector = parse_vector(Json::parse(line));
            if (!case_ids.insert(vector.case_id).second) {
                throw std::invalid_argument("duplicate case_id");
            }
            vectors.push_back(std::move(vector));
        } catch (const std::exception& error) {
            throw std::runtime_error(
                path.string() + ":" + std::to_string(line_number) + ": " + error.what()
            );
        }
    }
    return vectors;
}

}
