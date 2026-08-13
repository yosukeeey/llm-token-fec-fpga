#include "host/uart_transaction.hpp"

#include <array>
#include <exception>
#include <string>
#include <utility>
#include <vector>

#include "reference/protocol.hpp"

namespace host {
namespace {

void validate_case(const UartCase& uart_case) {
    if (uart_case.case_id.empty()) {
        throw std::invalid_argument("UART case ID must not be empty");
    }
    static_cast<void>(reference::parse_frame(uart_case.request));
    static_cast<void>(reference::parse_frame(uart_case.expected_response));
}

void write_all(
    ByteTransport& transport,
    const std::span<const std::uint8_t> data,
    const UartClock::time_point deadline
) {
    std::size_t offset = 0;
    while (offset < data.size()) {
        const auto count = transport.write_some(data.subspan(offset), deadline);
        if (count == 0U || count > data.size() - offset) {
            throw std::runtime_error("serial write made invalid progress");
        }
        offset += count;
    }
}

reference::Bytes read_frame(
    ByteTransport& transport,
    const UartClock::time_point deadline
) {
    reference::FrameParser parser;
    std::array<std::uint8_t, 256> buffer{};
    reference::Bytes received;
    while (true) {
        const auto count = transport.read_some(buffer, deadline);
        if (count == 0U || count > buffer.size()) {
            throw std::runtime_error("serial read made invalid progress");
        }
        received.insert(received.end(), buffer.begin(), buffer.begin() + static_cast<std::ptrdiff_t>(count));
        const auto frames = parser.feed(std::span(buffer).first(count));
        if (frames.empty()) {
            continue;
        }
        if (frames.size() != 1U || parser.buffered_bytes() != 0U) {
            throw std::runtime_error("serial response contains more than one Frame");
        }
        const auto response = reference::serialize_frame(frames.front());
        if (!parser.errors().empty() || received != response) {
            throw std::runtime_error("serial response required Frame resynchronization");
        }
        return response;
    }
}

}

std::size_t run_uart_cases(
    ByteTransport& transport,
    const std::span<const UartCase> cases,
    const std::chrono::milliseconds case_timeout
) {
    if (cases.empty()) {
        throw std::invalid_argument("UART case list must not be empty");
    }
    if (case_timeout.count() <= 0) {
        throw std::invalid_argument("UART case timeout must be positive");
    }
    const auto maximum_timeout = std::chrono::duration_cast<std::chrono::milliseconds>(
        UartClock::duration::max()
    );
    if (case_timeout > maximum_timeout) {
        throw std::invalid_argument("UART case timeout is outside the clock range");
    }
    const auto timeout_duration = std::chrono::duration_cast<UartClock::duration>(case_timeout);
    if (timeout_duration <= UartClock::duration::zero()) {
        throw std::invalid_argument("UART case timeout is outside the clock range");
    }
    for (const auto& uart_case : cases) {
        validate_case(uart_case);
    }

    std::size_t passed = 0;
    for (const auto& uart_case : cases) {
        try {
            /** Fragmented I/O must not extend a transaction beyond its fixed deadline. */
            const auto now = UartClock::now();
            if (timeout_duration > UartClock::time_point::max() - now) {
                throw std::invalid_argument("UART case timeout is outside the clock range");
            }
            const auto deadline = now + timeout_duration;
            write_all(transport, uart_case.request, deadline);
            const auto response = read_frame(transport, deadline);
            if (response != uart_case.expected_response) {
                throw std::runtime_error("serial response does not match expected Frame");
            }
            ++passed;
        } catch (const std::exception& error) {
            throw std::runtime_error(uart_case.case_id + ": " + error.what());
        }
    }
    return passed;
}

std::size_t run_uart_session(
    std::unique_ptr<ByteTransport> transport,
    const std::span<const UartCase> cases,
    const std::chrono::milliseconds case_timeout
) {
    if (!transport) {
        throw std::invalid_argument("UART transport must not be null");
    }
    return run_uart_cases(*transport, cases, case_timeout);
}

}
