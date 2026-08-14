#include "reference/vector.hpp"

#include <fstream>
#include <limits>
#include <set>
#include <sstream>
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

CaseResult parse_result(const Json& value) {
    if (!value.is_object()) {
        throw std::invalid_argument("result must be a JSON object");
    }
    CaseResult result{
        value.at("case_id").get<std::string>(),
        value.at("implementation").get<std::string>(),
        hex_decode(value.at("output_hex").get<std::string>()),
        read_size(value, "output_bit_length"),
        value.at("status").get<std::vector<std::string>>(),
        value.at("schema_version").get<std::uint32_t>(),
    };
    if (result.schema_version != 0U) {
        throw std::invalid_argument("unsupported result schema");
    }
    if (result.case_id.empty() || result.implementation.empty()) {
        throw std::invalid_argument("case_id and implementation must be non-empty");
    }
    validate_bit_length(result.output, result.output_bit_length);
    return result;
}

template <typename Record, typename Parser>
std::vector<Record> read_records(
    const std::filesystem::path& path,
    Parser parser,
    const char* duplicate_message
) {
    std::ifstream input(path);
    if (!input) {
        throw std::runtime_error("cannot open JSONL file: " + path.string());
    }
    std::vector<Record> records;
    std::set<std::string> case_ids;
    std::string line;
    std::size_t line_number = 0;
    while (std::getline(input, line)) {
        ++line_number;
        try {
            auto record = parser(Json::parse(line));
            if (!case_ids.insert(record.case_id).second) {
                throw std::invalid_argument(duplicate_message);
            }
            records.push_back(std::move(record));
        } catch (const std::exception& error) {
            throw std::runtime_error(
                path.string() + ":" + std::to_string(line_number) + ": " + error.what()
            );
        }
    }
    return records;
}

}

std::vector<TestVector> read_test_vectors(const std::filesystem::path& path) {
    return read_records<TestVector>(path, parse_vector, "duplicate case_id");
}

std::vector<CaseResult> read_case_results(const std::filesystem::path& path) {
    return read_records<CaseResult>(path, parse_result, "duplicate case_id");
}

std::string encode_case_results(const std::span<const CaseResult> results) {
    std::ostringstream output;
    for (const auto& result : results) {
        if (result.schema_version != 0U) {
            throw std::invalid_argument("unsupported result schema");
        }
        if (result.case_id.empty() || result.implementation.empty()) {
            throw std::invalid_argument("case_id and implementation must be non-empty");
        }
        validate_bit_length(result.output, result.output_bit_length);
        nlohmann::ordered_json value;
        value["case_id"] = result.case_id;
        value["implementation"] = result.implementation;
        value["output_hex"] = hex_encode(result.output);
        value["output_bit_length"] = result.output_bit_length;
        value["status"] = result.status;
        value["schema_version"] = result.schema_version;
        output << value.dump() << '\n';
    }
    return output.str();
}

}
