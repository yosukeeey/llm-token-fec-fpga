#include "host/uart_vector_cases.hpp"

#include <stdexcept>
#include <utility>

#include "reference/protocol.hpp"
#include "reference/vector.hpp"

namespace host {

std::vector<UartCase> load_uart_cases(const std::filesystem::path& vector_path) {
    const auto vectors = reference::read_test_vectors(vector_path);
    if (vectors.empty()) {
        throw std::invalid_argument("UART vector file must not be empty");
    }

    std::vector<UartCase> cases;
    cases.reserve(vectors.size());
    for (const auto& vector : vectors) {
        if (vector.algorithm != "protocol_pipeline") {
            throw std::invalid_argument(
                vector.case_id + ": UART vector algorithm must be protocol_pipeline"
            );
        }
        if (vector.input_bit_length != vector.input.size() * 8U
            || vector.decoded_bit_length != vector.decoded.size() * 8U) {
            throw std::invalid_argument(
                vector.case_id + ": UART Frames must be byte-aligned"
            );
        }
        try {
            static_cast<void>(reference::parse_frame(vector.input));
            static_cast<void>(reference::parse_frame(vector.decoded));
        } catch (const reference::ProtocolError& error) {
            throw std::invalid_argument(
                vector.case_id + ": invalid UART Frame: " + error.what()
            );
        }
        cases.push_back({vector.case_id, vector.input, vector.decoded});
    }
    return cases;
}

}
