#include <charconv>
#include <chrono>
#include <cstddef>
#include <exception>
#include <filesystem>
#include <iostream>
#include <limits>
#include <memory>
#include <optional>
#include <stdexcept>
#include <string>
#include <string_view>

#include "host/uart_artifacts.hpp"
#include "host/uart_transaction.hpp"
#include "host/uart_vector_cases.hpp"
#include "host/win32_serial.hpp"

namespace {

struct Arguments {
    std::string port;
    std::filesystem::path vector_path;
    std::filesystem::path capture_path;
    std::filesystem::path result_path;
    std::chrono::milliseconds timeout{2'000};
};

std::chrono::milliseconds parse_timeout(const std::string_view value) {
    long long milliseconds = 0;
    const auto [position, error] = std::from_chars(
        value.data(),
        value.data() + value.size(),
        milliseconds
    );
    constexpr auto maximum_wait = static_cast<long long>(
        std::numeric_limits<std::uint32_t>::max() - 1U
    );
    if (error != std::errc{} || position != value.data() + value.size()
        || milliseconds <= 0 || milliseconds > maximum_wait) {
        throw std::invalid_argument("--timeout-ms is outside the Win32 wait range");
    }
    return std::chrono::milliseconds(milliseconds);
}

Arguments parse_arguments(const int argument_count, const char* const arguments[]) {
    Arguments parsed;
    bool has_port = false;
    bool has_vectors = false;
    bool has_capture = false;
    bool has_results = false;
    bool has_timeout = false;
    for (int index = 1; index < argument_count; index += 2) {
        if (index + 1 >= argument_count) {
            throw std::invalid_argument("each option requires a value");
        }
        const std::string_view option(arguments[index]);
        const std::string_view value(arguments[index + 1]);
        if (option == "--port" && !has_port) {
            parsed.port = value;
            has_port = true;
        } else if (option == "--vectors" && !has_vectors) {
            parsed.vector_path = value;
            has_vectors = true;
        } else if (option == "--capture" && !has_capture) {
            parsed.capture_path = value;
            has_capture = true;
        } else if (option == "--results" && !has_results) {
            parsed.result_path = value;
            has_results = true;
        } else if (option == "--timeout-ms" && !has_timeout) {
            parsed.timeout = parse_timeout(value);
            has_timeout = true;
        } else {
            throw std::invalid_argument("unknown or duplicate option: " + std::string(option));
        }
    }
    if (!has_port || !has_vectors || !has_capture || !has_results) {
        throw std::invalid_argument(
            "usage: uart_vector_runner --port COM3 --vectors PATH "
            "--capture PATH --results PATH [--timeout-ms N]"
        );
    }
    return parsed;
}

}

int main(const int argument_count, const char* const arguments[]) {
    std::optional<Arguments> options;
    std::optional<host::UartArtifactRecorder> recorder;
    std::optional<host::UartArtifactFiles> artifacts;
    bool artifact_write_attempted = false;
    try {
        options = parse_arguments(argument_count, arguments);
        /** Invalid vectors must not open or modify the serial device. */
        const auto cases = host::load_uart_cases(options->vector_path);
        artifacts.emplace(options->capture_path, options->result_path);
        recorder.emplace();
        const auto passed = host::run_uart_session(
            std::make_unique<host::Win32Serial>(options->port),
            cases,
            options->timeout,
            &*recorder
        );
        artifact_write_attempted = true;
        artifacts->write(*recorder);
        std::cout << "uart_vector_runner: " << passed << " cases passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::string artifact_error;
        if (artifacts && recorder && !artifact_write_attempted) {
            artifact_write_attempted = true;
            try {
                artifacts->write(*recorder);
            } catch (const std::exception& write_error) {
                artifact_error = "; artifact write failed: " + std::string(write_error.what());
            }
        }
        std::cerr << "uart_vector_runner: " << error.what() << artifact_error << '\n';
        return 1;
    }
}
