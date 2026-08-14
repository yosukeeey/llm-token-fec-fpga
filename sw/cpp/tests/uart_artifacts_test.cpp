#include <algorithm>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <deque>
#include <exception>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <span>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#include "host/uart_artifacts.hpp"
#include "host/uart_transaction.hpp"
#include "host/uart_vector_cases.hpp"
#include "reference/protocol.hpp"
#include "reference/types.hpp"
#include "reference/vector.hpp"

namespace {

struct ReadStep {
    reference::Bytes data;
    bool timeout{false};
    bool failure{false};
};

class ArtifactTransport final : public host::ByteTransport {
public:
    std::size_t write_some(
        const std::span<const std::uint8_t> data,
        host::UartClock::time_point
    ) override {
        written.insert(written.end(), data.begin(), data.end());
        return data.size();
    }

    std::size_t read_some(
        const std::span<std::uint8_t> data,
        host::UartClock::time_point
    ) override {
        if (reads.empty()) {
            throw std::runtime_error("artifact test read exhausted");
        }
        auto step = std::move(reads.front());
        reads.pop_front();
        if (step.timeout) {
            throw host::TransportTimeout("artifact test timeout");
        }
        if (step.failure) {
            throw std::runtime_error("artifact test read failure");
        }
        const auto count = std::min(data.size(), step.data.size());
        std::copy_n(step.data.begin(), count, data.begin());
        if (count < step.data.size()) {
            step.data.erase(step.data.begin(), step.data.begin() + static_cast<std::ptrdiff_t>(count));
            reads.push_front(std::move(step));
        }
        return count;
    }

    std::deque<ReadStep> reads;
    reference::Bytes written;
};

void require(const bool condition, const std::string_view message) {
    if (!condition) {
        throw std::runtime_error(std::string(message));
    }
}

template <typename Function>
void require_failure(Function&& function, const std::string_view expected) {
    try {
        std::forward<Function>(function)();
    } catch (const std::exception& error) {
        require(
            std::string_view(error.what()).find(expected) != std::string_view::npos,
            "artifact failure message mismatch"
        );
        return;
    }
    throw std::runtime_error("expected artifact failure was not raised");
}

reference::Bytes concatenate_responses(const std::span<const host::UartCase> cases) {
    reference::Bytes output;
    for (const auto& uart_case : cases) {
        output.insert(
            output.end(),
            uart_case.expected_response.begin(),
            uart_case.expected_response.end()
        );
    }
    return output;
}

reference::Bytes read_binary(const std::filesystem::path& path) {
    std::ifstream input(path, std::ios::binary);
    if (!input) {
        throw std::runtime_error("cannot read artifact fixture");
    }
    return {
        std::istreambuf_iterator<char>(input),
        std::istreambuf_iterator<char>(),
    };
}

void write_text(const std::filesystem::path& path, const std::string_view content) {
    std::ofstream output(path, std::ios::binary);
    if (!output) {
        throw std::runtime_error("cannot write artifact fixture");
    }
    output << content;
}

void append_fragmented_response(
    ArtifactTransport& transport,
    const std::span<const std::uint8_t> response
) {
    const auto first = std::min<std::size_t>(3U, response.size());
    transport.reads.push_back({reference::Bytes(response.begin(), response.begin() + first)});
    if (first < response.size()) {
        transport.reads.push_back({
            reference::Bytes(response.begin() + static_cast<std::ptrdiff_t>(first), response.end())
        });
    }
}

void test_success_artifacts(
    const std::vector<host::UartCase>& cases,
    const std::filesystem::path& artifact_directory
) {
    ArtifactTransport transport;
    for (const auto& uart_case : cases) {
        append_fragmented_response(transport, uart_case.expected_response);
    }
    host::UartArtifactRecorder recorder;
    require(
        host::run_uart_cases(
            transport,
            cases,
            std::chrono::seconds(1),
            &recorder
        ) == cases.size(),
        "artifact fixed cases failed"
    );

    const auto expected_capture = concatenate_responses(cases);
    require(recorder.capture() == expected_capture, "raw capture changed UART bytes");
    require(recorder.results().size() == 2U, "artifact result count mismatch");
    require(recorder.results()[0].case_id == cases[0].case_id, "PING result order changed");
    require(recorder.results()[0].output == cases[0].expected_response, "PONG output changed");
    require(recorder.results()[0].status.empty(), "PONG status must be empty");
    require(recorder.results()[1].case_id == cases[1].case_id, "Token result order changed");
    require(
        recorder.results()[1].status == std::vector<std::string>{"FEC_CORRECTED"},
        "Token result status was not decoded"
    );

    const auto capture_path = artifact_directory / "uart-capture.bin";
    const auto result_path = artifact_directory / "results.jsonl";
    host::write_uart_artifacts(capture_path, result_path, recorder);
    require(read_binary(capture_path) == expected_capture, "written capture changed UART bytes");
    require(
        reference::read_case_results(result_path) == recorder.results(),
        "CaseResult JSONL round trip failed"
    );

    auto mismatched_results = recorder.results();
    mismatched_results.front().output.back() ^= 1U;
    write_text(
        artifact_directory / "mismatch-results.jsonl",
        reference::encode_case_results(mismatched_results)
    );

    const auto capture_before = read_binary(capture_path);
    const auto results_before = read_binary(result_path);
    require_failure(
        [&] { host::write_uart_artifacts(capture_path, result_path, recorder); },
        "already exists"
    );
    require(read_binary(capture_path) == capture_before, "existing capture was modified");
    require(read_binary(result_path) == results_before, "existing results were modified");
}

void test_failure_artifacts(
    const std::vector<host::UartCase>& cases,
    const std::filesystem::path& artifact_directory
) {
    auto mismatch_case = cases.front();
    mismatch_case.expected_response = cases.back().expected_response;
    ArtifactTransport mismatch_transport;
    mismatch_transport.reads.push_back({cases.front().expected_response});
    host::UartArtifactRecorder mismatch_recorder;
    require_failure(
        [&] {
            static_cast<void>(host::run_uart_cases(
                mismatch_transport,
                std::span(&mismatch_case, 1),
                std::chrono::seconds(1),
                &mismatch_recorder
            ));
        },
        "does not match"
    );
    require(
        mismatch_recorder.capture() == cases.front().expected_response,
        "mismatched response was not captured"
    );
    require(mismatch_recorder.results().size() == 1U, "mismatched response was not recorded");
    const auto mismatch_capture = artifact_directory / "failure-mismatch.bin";
    const auto mismatch_results = artifact_directory / "failure-mismatch.jsonl";
    host::write_uart_artifacts(mismatch_capture, mismatch_results, mismatch_recorder);
    require(
        read_binary(mismatch_capture) == cases.front().expected_response,
        "mismatched response was not persisted"
    );
    require(
        reference::read_case_results(mismatch_results).size() == 1U,
        "mismatched result was not persisted"
    );

    ArtifactTransport timeout_transport;
    const reference::Bytes partial{
        cases.front().expected_response.begin(),
        cases.front().expected_response.begin() + 4,
    };
    timeout_transport.reads.push_back({partial});
    timeout_transport.reads.push_back({{}, true});
    host::UartArtifactRecorder timeout_recorder;
    require_failure(
        [&] {
            static_cast<void>(host::run_uart_cases(
                timeout_transport,
                std::span(cases).first(1),
                std::chrono::milliseconds(10),
                &timeout_recorder
            ));
        },
        "timeout"
    );
    require(timeout_recorder.capture() == partial, "partial timeout capture was lost");
    require(timeout_recorder.results().empty(), "partial Frame produced a result");
    const auto timeout_capture = artifact_directory / "failure-timeout.bin";
    const auto timeout_results = artifact_directory / "failure-timeout.jsonl";
    host::write_uart_artifacts(timeout_capture, timeout_results, timeout_recorder);
    require(read_binary(timeout_capture) == partial, "timeout capture was not persisted");
    require(read_binary(timeout_results).empty(), "timeout produced a persisted result");

    auto malformed = cases.front().expected_response;
    malformed.back() ^= 1U;
    ArtifactTransport malformed_transport;
    malformed_transport.reads.push_back({malformed});
    malformed_transport.reads.push_back({{}, true});
    host::UartArtifactRecorder malformed_recorder;
    require_failure(
        [&] {
            static_cast<void>(host::run_uart_cases(
                malformed_transport,
                std::span(cases).first(1),
                std::chrono::milliseconds(10),
                &malformed_recorder
            ));
        },
        "timeout"
    );
    require(malformed_recorder.capture() == malformed, "malformed capture was changed");
    require(malformed_recorder.results().empty(), "malformed Frame produced a result");
    const auto malformed_capture = artifact_directory / "failure-malformed.bin";
    const auto malformed_results = artifact_directory / "failure-malformed.jsonl";
    host::write_uart_artifacts(malformed_capture, malformed_results, malformed_recorder);
    require(read_binary(malformed_capture) == malformed, "malformed capture was not persisted");
    require(read_binary(malformed_results).empty(), "malformed Frame produced a persisted result");

    ArtifactTransport failure_transport;
    failure_transport.reads.push_back({partial});
    failure_transport.reads.push_back({{}, false, true});
    host::UartArtifactRecorder failure_recorder;
    require_failure(
        [&] {
            static_cast<void>(host::run_uart_cases(
                failure_transport,
                std::span(cases).first(1),
                std::chrono::seconds(1),
                &failure_recorder
            ));
        },
        "read failure"
    );
    const auto read_failure_capture = artifact_directory / "failure-read.bin";
    const auto read_failure_results = artifact_directory / "failure-read.jsonl";
    host::write_uart_artifacts(
        read_failure_capture,
        read_failure_results,
        failure_recorder
    );
    require(
        read_binary(read_failure_capture) == partial,
        "read failure capture was not persisted"
    );
    require(
        read_binary(read_failure_results).empty(),
        "read failure produced a persisted result"
    );

    const reference::Frame invalid_payload_frame{
        static_cast<std::uint8_t>(reference::MessageType::token_result),
        {},
    };
    const auto invalid_payload = reference::serialize_frame(invalid_payload_frame);
    ArtifactTransport invalid_payload_transport;
    invalid_payload_transport.reads.push_back({invalid_payload});
    host::UartArtifactRecorder invalid_payload_recorder;
    require_failure(
        [&] {
            static_cast<void>(host::run_uart_cases(
                invalid_payload_transport,
                std::span(cases).first(1),
                std::chrono::seconds(1),
                &invalid_payload_recorder
            ));
        },
        "truncated"
    );
    require(
        invalid_payload_recorder.results().size() == 1U,
        "complete invalid payload was not recorded"
    );
    require(
        invalid_payload_recorder.results().front().output == invalid_payload,
        "complete invalid payload bytes changed"
    );
    require(
        invalid_payload_recorder.results().front().status.empty(),
        "invalid payload produced decoded status"
    );
    const auto invalid_payload_capture = artifact_directory / "failure-payload.bin";
    const auto invalid_payload_results = artifact_directory / "failure-payload.jsonl";
    host::write_uart_artifacts(
        invalid_payload_capture,
        invalid_payload_results,
        invalid_payload_recorder
    );
    require(
        read_binary(invalid_payload_capture) == invalid_payload,
        "complete invalid payload capture was not persisted"
    );
    require(
        reference::read_case_results(invalid_payload_results).size() == 1U,
        "complete invalid payload result was not persisted"
    );
}

void test_error_status() {
    const auto flags = static_cast<std::uint32_t>(reference::ResultFlag::crc_error)
        | static_cast<std::uint32_t>(reference::ResultFlag::uart_framing_error);
    const reference::ErrorResponse error{
        flags,
        static_cast<std::uint8_t>(reference::MessageType::token_request),
    };
    const reference::Frame frame{
        static_cast<std::uint8_t>(reference::MessageType::error_response),
        reference::pack_error_response(error),
    };
    const auto response = reference::serialize_frame(frame);
    host::UartArtifactRecorder recorder;
    recorder.completed("error-response", response);
    require(
        recorder.results().front().status
            == std::vector<std::string>{"CRC_ERROR", "UART_FRAMING_ERROR"},
        "ERROR_RESPONSE status order mismatch"
    );
}

void test_path_validation(const std::filesystem::path& artifact_directory) {
    const auto same = artifact_directory / "same.bin";
    require_failure(
        [&] { host::validate_uart_artifact_paths(same, same); },
        "must be different"
    );
    require_failure(
        [&] {
            host::validate_uart_artifact_paths(
                artifact_directory / "capture.bin",
                artifact_directory / "missing" / "results.jsonl"
            );
        },
        "does not exist"
    );
}

void test_exclusive_reservation(const std::filesystem::path& artifact_directory) {
    const auto reservation_directory = artifact_directory / "reservation";
    std::filesystem::create_directories(reservation_directory);
    const auto capture_path = reservation_directory / "capture.bin";
    const auto result_path = reservation_directory / "results.jsonl";
    host::UartArtifactFiles reservation(capture_path, result_path);
    require(std::filesystem::exists(capture_path), "capture was not reserved");
    require(std::filesystem::exists(result_path), "results were not reserved");

    host::UartArtifactRecorder recorder;
    require_failure(
        [&] { host::write_uart_artifacts(capture_path, result_path, recorder); },
        "already exists"
    );
    reservation.write(recorder);
    require(read_binary(capture_path).empty(), "reserved capture changed");
    require(read_binary(result_path).empty(), "reserved results changed");

    const auto partial_capture = reservation_directory / "partial-capture.bin";
    const auto existing_result = reservation_directory / "existing-results.jsonl";
    write_text(existing_result, "existing\n");
    require_failure(
        [&] {
            host::UartArtifactFiles partial(partial_capture, existing_result);
        },
        "already exists"
    );
    require(
        std::filesystem::exists(partial_capture) && read_binary(partial_capture).empty(),
        "partial reservation was not retained safely"
    );
    require(read_binary(existing_result) == reference::Bytes{
        'e', 'x', 'i', 's', 't', 'i', 'n', 'g', '\n'
    }, "existing result changed during reservation");
}

}

int main(const int argument_count, const char* const arguments[]) {
    try {
        if (argument_count != 3) {
            throw std::invalid_argument("expected vector path and artifact directory");
        }
        const auto cases = host::load_uart_cases(arguments[1]);
        const std::filesystem::path artifact_directory(arguments[2]);
        std::filesystem::remove_all(artifact_directory);
        std::filesystem::create_directories(artifact_directory);
        test_success_artifacts(cases, artifact_directory);
        test_failure_artifacts(cases, artifact_directory);
        test_error_status();
        test_path_validation(artifact_directory);
        test_exclusive_reservation(artifact_directory);
        std::cout << "uart_artifacts_test: 5 cases passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "uart_artifacts_test: " << error.what() << '\n';
        return 1;
    }
}
