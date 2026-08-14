#pragma once

#include <chrono>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <span>
#include <stdexcept>
#include <string>
#include <string_view>

#include "reference/bits.hpp"

namespace host {

using UartClock = std::chrono::steady_clock;

class TransportTimeout : public std::runtime_error {
public:
    using std::runtime_error::runtime_error;
};

class ByteTransport {
public:
    virtual ~ByteTransport() = default;

    virtual std::size_t write_some(
        std::span<const std::uint8_t> data,
        UartClock::time_point deadline
    ) = 0;

    virtual std::size_t read_some(
        std::span<std::uint8_t> data,
        UartClock::time_point deadline
    ) = 0;
};

class UartObserver {
public:
    virtual ~UartObserver() = default;

    virtual void received(std::span<const std::uint8_t> data) = 0;

    virtual void completed(
        std::string_view case_id,
        std::span<const std::uint8_t> response
    ) = 0;
};

struct UartCase {
    std::string case_id;
    reference::Bytes request;
    reference::Bytes expected_response;
};

[[nodiscard]] std::size_t run_uart_cases(
    ByteTransport& transport,
    std::span<const UartCase> cases,
    std::chrono::milliseconds case_timeout,
    UartObserver* observer = nullptr
);

[[nodiscard]] std::size_t run_uart_session(
    std::unique_ptr<ByteTransport> transport,
    std::span<const UartCase> cases,
    std::chrono::milliseconds case_timeout,
    UartObserver* observer = nullptr
);

}
