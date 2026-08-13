#pragma once

#include <memory>
#include <string_view>

#include "host/uart_transaction.hpp"

namespace host {

class Win32Serial final : public ByteTransport {
public:
    explicit Win32Serial(std::string_view port_name);
    ~Win32Serial() override;

    Win32Serial(const Win32Serial&) = delete;
    Win32Serial& operator=(const Win32Serial&) = delete;
    Win32Serial(Win32Serial&&) = delete;
    Win32Serial& operator=(Win32Serial&&) = delete;

    std::size_t write_some(
        std::span<const std::uint8_t> data,
        UartClock::time_point deadline
    ) override;

    std::size_t read_some(
        std::span<std::uint8_t> data,
        UartClock::time_point deadline
    ) override;

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};

}
