#include "host/win32_serial.hpp"

#define NOMINMAX
#include <windows.h>

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <limits>
#include <stdexcept>
#include <string>
#include <system_error>
#include <utility>

namespace host {
namespace {

class NativeHandle {
public:
    explicit NativeHandle(const HANDLE value = nullptr) noexcept : value_(value) {}

    ~NativeHandle() {
        if (valid()) {
            CloseHandle(value_);
        }
    }

    NativeHandle(const NativeHandle&) = delete;
    NativeHandle& operator=(const NativeHandle&) = delete;

    NativeHandle(NativeHandle&& other) noexcept : value_(std::exchange(other.value_, nullptr)) {}

    NativeHandle& operator=(NativeHandle&& other) noexcept {
        if (this != &other) {
            if (valid()) {
                CloseHandle(value_);
            }
            value_ = std::exchange(other.value_, nullptr);
        }
        return *this;
    }

    [[nodiscard]] HANDLE get() const noexcept {
        return value_;
    }

    [[nodiscard]] bool valid() const noexcept {
        return value_ != nullptr && value_ != INVALID_HANDLE_VALUE;
    }

private:
    HANDLE value_;
};

[[noreturn]] void throw_last_error(const char* operation, const DWORD error = GetLastError()) {
    throw std::system_error(static_cast<int>(error), std::system_category(), operation);
}

std::wstring device_path(const std::string_view port_name) {
    if (port_name.size() < 4U || port_name.substr(0, 3) != "COM"
        || port_name[3] < '1' || port_name[3] > '9'
        || !std::all_of(port_name.begin() + 4, port_name.end(), [](const char value) {
               return value >= '0' && value <= '9';
           })) {
        throw std::invalid_argument("port must match COM[1-9][0-9]*");
    }
    std::wstring path = L"\\\\.\\";
    path.append(port_name.begin(), port_name.end());
    return path;
}

DWORD wait_duration(const UartClock::time_point deadline) {
    const auto remaining = deadline - UartClock::now();
    if (remaining <= UartClock::duration::zero()) {
        throw TransportTimeout("serial transaction timed out");
    }
    const auto milliseconds = std::chrono::ceil<std::chrono::milliseconds>(remaining).count();
    constexpr auto maximum_wait = static_cast<long long>(INFINITE - 1U);
    return static_cast<DWORD>(std::min(milliseconds, maximum_wait));
}

void drain_cancelled_operation(const HANDLE port, OVERLAPPED& overlapped) {
    DWORD cancel_error = ERROR_SUCCESS;
    if (!CancelIoEx(port, &overlapped)) {
        cancel_error = GetLastError();
        if (cancel_error == ERROR_NOT_FOUND) {
            cancel_error = ERROR_SUCCESS;
        }
    }

    DWORD ignored = 0;
    if (!GetOverlappedResult(port, &overlapped, &ignored, TRUE)) {
        const auto completion_error = GetLastError();
        if (completion_error != ERROR_OPERATION_ABORTED && cancel_error == ERROR_SUCCESS) {
            throw_last_error("GetOverlappedResult", completion_error);
        }
    }
    if (cancel_error != ERROR_SUCCESS) {
        throw_last_error("CancelIoEx", cancel_error);
    }
}

enum class Operation {
    read,
    write,
};

std::size_t perform_operation(
    const HANDLE port,
    const Operation operation,
    void* const buffer,
    const DWORD requested,
    const UartClock::time_point deadline
) {
    static_cast<void>(wait_duration(deadline));
    NativeHandle event(CreateEventW(nullptr, TRUE, FALSE, nullptr));
    if (!event.valid()) {
        throw_last_error("CreateEventW");
    }

    OVERLAPPED overlapped{};
    overlapped.hEvent = event.get();
    DWORD transferred = 0;
    const auto started = operation == Operation::read
        ? ReadFile(port, buffer, requested, nullptr, &overlapped)
        : WriteFile(port, buffer, requested, nullptr, &overlapped);
    if (started) {
        if (!GetOverlappedResult(port, &overlapped, &transferred, FALSE)) {
            throw_last_error("GetOverlappedResult");
        }
        return transferred;
    }
    const auto start_error = GetLastError();
    if (start_error != ERROR_IO_PENDING) {
        throw_last_error(operation == Operation::read ? "ReadFile" : "WriteFile", start_error);
    }

    DWORD remaining = 0;
    try {
        remaining = wait_duration(deadline);
    } catch (const TransportTimeout&) {
        drain_cancelled_operation(port, overlapped);
        throw;
    }
    const auto wait_result = WaitForSingleObject(event.get(), remaining);
    if (wait_result == WAIT_OBJECT_0) {
        if (!GetOverlappedResult(port, &overlapped, &transferred, FALSE)) {
            throw_last_error("GetOverlappedResult");
        }
        return transferred;
    }
    if (wait_result == WAIT_TIMEOUT) {
        /** OVERLAPPED storage must remain alive until cancellation reaches a terminal state. */
        drain_cancelled_operation(port, overlapped);
        throw TransportTimeout("serial transaction timed out");
    }

    const auto wait_error = GetLastError();
    drain_cancelled_operation(port, overlapped);
    throw_last_error("WaitForSingleObject", wait_error);
}

void configure_port(const HANDLE port) {
    DCB state{};
    state.DCBlength = sizeof(state);
    if (!GetCommState(port, &state)) {
        throw_last_error("GetCommState");
    }
    state.BaudRate = CBR_115200;
    state.ByteSize = 8;
    state.Parity = NOPARITY;
    state.StopBits = ONESTOPBIT;
    state.fBinary = TRUE;
    state.fParity = FALSE;
    state.fOutxCtsFlow = FALSE;
    state.fOutxDsrFlow = FALSE;
    state.fDtrControl = DTR_CONTROL_DISABLE;
    state.fDsrSensitivity = FALSE;
    state.fTXContinueOnXoff = TRUE;
    state.fOutX = FALSE;
    state.fInX = FALSE;
    state.fErrorChar = FALSE;
    state.fNull = FALSE;
    state.fRtsControl = RTS_CONTROL_DISABLE;
    state.fAbortOnError = FALSE;
    if (!SetCommState(port, &state)) {
        throw_last_error("SetCommState");
    }

    COMMTIMEOUTS timeouts{};
    if (!SetCommTimeouts(port, &timeouts)) {
        throw_last_error("SetCommTimeouts");
    }
    if (!PurgeComm(port, PURGE_RXCLEAR | PURGE_TXCLEAR)) {
        throw_last_error("PurgeComm");
    }
}

}

struct Win32Serial::Impl {
    explicit Impl(const std::string_view port_name)
        : port(CreateFileW(
              device_path(port_name).c_str(),
              GENERIC_READ | GENERIC_WRITE,
              0,
              nullptr,
              OPEN_EXISTING,
              FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OVERLAPPED,
              nullptr
          )) {
        if (!port.valid()) {
            throw_last_error("CreateFileW");
        }
        configure_port(port.get());
    }

    NativeHandle port;
};

Win32Serial::Win32Serial(const std::string_view port_name)
    : impl_(std::make_unique<Impl>(port_name)) {}

Win32Serial::~Win32Serial() = default;

std::size_t Win32Serial::write_some(
    const std::span<const std::uint8_t> data,
    const UartClock::time_point deadline
) {
    if (data.empty()) {
        return 0U;
    }
    const auto requested = static_cast<DWORD>(std::min<std::size_t>(
        data.size(),
        std::numeric_limits<DWORD>::max()
    ));
    return perform_operation(
        impl_->port.get(),
        Operation::write,
        const_cast<std::uint8_t*>(data.data()),
        requested,
        deadline
    );
}

std::size_t Win32Serial::read_some(
    const std::span<std::uint8_t> data,
    const UartClock::time_point deadline
) {
    if (data.empty()) {
        return 0U;
    }
    /** A one-byte read makes all-zero COM timeouts complete on each received byte. */
    return perform_operation(
        impl_->port.get(),
        Operation::read,
        data.data(),
        1U,
        deadline
    );
}

}
