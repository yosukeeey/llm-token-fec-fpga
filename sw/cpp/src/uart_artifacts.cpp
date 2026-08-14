#include "host/uart_artifacts.hpp"

#include <algorithm>
#include <array>
#include <cstdint>
#include <cwctype>
#include <limits>
#include <stdexcept>
#include <string>
#include <system_error>
#include <utility>

#ifdef _WIN32
#define NOMINMAX
#include <windows.h>
#else
#include <cerrno>
#include <fcntl.h>
#include <unistd.h>
#endif

#include "reference/protocol.hpp"
#include "reference/types.hpp"

namespace host {
namespace {

constexpr std::array<std::pair<reference::ResultFlag, std::string_view>, 10> result_flags{{
    {reference::ResultFlag::parity_error, "PARITY_ERROR"},
    {reference::ResultFlag::fec_corrected, "FEC_CORRECTED"},
    {reference::ResultFlag::crc_error, "CRC_ERROR"},
    {reference::ResultFlag::malformed_frame, "MALFORMED_FRAME"},
    {reference::ResultFlag::malformed_request, "MALFORMED_REQUEST"},
    {reference::ResultFlag::unsupported_version, "UNSUPPORTED_VERSION"},
    {reference::ResultFlag::unsupported_protection, "UNSUPPORTED_PROTECTION"},
    {reference::ResultFlag::sequence_gap, "SEQUENCE_GAP"},
    {reference::ResultFlag::uart_framing_error, "UART_FRAMING_ERROR"},
    {reference::ResultFlag::internal_overflow, "INTERNAL_OVERFLOW"},
}};

std::vector<std::string> status_names(const reference::Frame& frame) {
    std::uint32_t flags = 0U;
    if (frame.message_type == static_cast<std::uint8_t>(reference::MessageType::token_result)) {
        flags = reference::unpack_token_result(frame.payload).status.flags;
    } else if (
        frame.message_type == static_cast<std::uint8_t>(reference::MessageType::error_response)
    ) {
        flags = reference::unpack_error_response(frame.payload).flags;
    }

    std::vector<std::string> names;
    for (const auto& [flag, name] : result_flags) {
        if ((flags & static_cast<std::uint32_t>(flag)) != 0U) {
            names.emplace_back(name);
        }
    }
    return names;
}

std::filesystem::path normalized_absolute(const std::filesystem::path& path) {
    auto normalized = std::filesystem::absolute(path).lexically_normal();
#ifdef _WIN32
    auto text = normalized.native();
    std::transform(text.begin(), text.end(), text.begin(), [](const wchar_t value) {
        return static_cast<wchar_t>(std::towlower(value));
    });
    normalized = std::move(text);
#endif
    return normalized;
}

void validate_new_file_path(const std::filesystem::path& path, const char* name) {
    if (path.empty() || path.filename().empty()) {
        throw std::invalid_argument(std::string(name) + " path must name a file");
    }
    const auto parent = path.has_parent_path() ? path.parent_path() : std::filesystem::path{"."};
    if (!std::filesystem::is_directory(parent)) {
        throw std::invalid_argument(std::string(name) + " parent directory does not exist");
    }
}

class ReservedArtifact final {
public:
    explicit ReservedArtifact(const std::filesystem::path& path) : path_(path) {
#ifdef _WIN32
        file_ = CreateFileW(
            path.c_str(),
            GENERIC_WRITE,
            0,
            nullptr,
            CREATE_NEW,
            FILE_ATTRIBUTE_NORMAL,
            nullptr
        );
        if (file_ == INVALID_HANDLE_VALUE) {
            const auto error = GetLastError();
            if (error == ERROR_FILE_EXISTS || error == ERROR_ALREADY_EXISTS) {
                throw std::runtime_error("artifact path already exists: " + path.string());
            }
            throw std::system_error(
                static_cast<int>(error),
                std::system_category(),
                "cannot create artifact: " + path.string()
            );
        }
#else
        file_ = open(path.c_str(), O_WRONLY | O_CREAT | O_EXCL, 0666);
        if (file_ < 0) {
            if (errno == EEXIST) {
                throw std::runtime_error("artifact path already exists: " + path.string());
            }
            throw std::system_error(
                errno,
                std::generic_category(),
                "cannot create artifact: " + path.string()
            );
        }
#endif
    }

    ~ReservedArtifact() {
        close_noexcept();
        if (remove_on_destroy_) {
            std::error_code ignored;
            std::filesystem::remove(path_, ignored);
        }
    }

    ReservedArtifact(const ReservedArtifact&) = delete;
    ReservedArtifact& operator=(const ReservedArtifact&) = delete;

    void keep() noexcept {
        remove_on_destroy_ = false;
    }

    void write_all(const std::span<const std::uint8_t> content) {
        if (closed_) {
            throw std::logic_error("artifact file is already closed");
        }
        std::size_t offset = 0U;
        while (offset < content.size()) {
#ifdef _WIN32
            const auto requested = static_cast<DWORD>(std::min<std::size_t>(
                content.size() - offset,
                std::numeric_limits<DWORD>::max()
            ));
            DWORD written = 0U;
            if (!WriteFile(file_, content.data() + offset, requested, &written, nullptr)
                || written == 0U) {
                throw std::system_error(
                    static_cast<int>(GetLastError()),
                    std::system_category(),
                    "cannot write artifact: " + path_.string()
                );
            }
#else
            const auto written = ::write(
                file_,
                content.data() + offset,
                content.size() - offset
            );
            if (written <= 0) {
                throw std::system_error(
                    errno,
                    std::generic_category(),
                    "cannot write artifact: " + path_.string()
                );
            }
#endif
            offset += static_cast<std::size_t>(written);
        }
        close();
    }

private:
    void close() {
#ifdef _WIN32
        if (!CloseHandle(file_)) {
            throw std::system_error(
                static_cast<int>(GetLastError()),
                std::system_category(),
                "cannot close artifact: " + path_.string()
            );
        }
        file_ = INVALID_HANDLE_VALUE;
#else
        if (::close(file_) != 0) {
            throw std::system_error(
                errno,
                std::generic_category(),
                "cannot close artifact: " + path_.string()
            );
        }
        file_ = -1;
#endif
        closed_ = true;
    }

    void close_noexcept() noexcept {
        if (closed_) {
            return;
        }
#ifdef _WIN32
        CloseHandle(file_);
        file_ = INVALID_HANDLE_VALUE;
#else
        ::close(file_);
        file_ = -1;
#endif
        closed_ = true;
    }

    std::filesystem::path path_;
    bool remove_on_destroy_{true};
    bool closed_{false};
#ifdef _WIN32
    HANDLE file_{INVALID_HANDLE_VALUE};
#else
    int file_{-1};
#endif
};

}

struct UartArtifactFiles::Impl {
    Impl(
        const std::filesystem::path& capture_path,
        const std::filesystem::path& result_path
    ) : capture(capture_path), result(result_path) {
        capture.keep();
        result.keep();
    }

    ReservedArtifact capture;
    ReservedArtifact result;
    bool written{false};
};

void UartArtifactRecorder::received(const std::span<const std::uint8_t> data) {
    capture_.insert(capture_.end(), data.begin(), data.end());
}

void UartArtifactRecorder::completed(
    const std::string_view case_id,
    const std::span<const std::uint8_t> response
) {
    const auto frame = reference::parse_frame(response);
    results_.push_back({
        std::string(case_id),
        "fpga-uart",
        reference::Bytes(response.begin(), response.end()),
        response.size() * 8U,
        {},
        0U,
    });
    results_.back().status = status_names(frame);
}

const reference::Bytes& UartArtifactRecorder::capture() const noexcept {
    return capture_;
}

const std::vector<reference::CaseResult>& UartArtifactRecorder::results() const noexcept {
    return results_;
}

void validate_uart_artifact_paths(
    const std::filesystem::path& capture_path,
    const std::filesystem::path& result_path
) {
    validate_new_file_path(capture_path, "capture");
    validate_new_file_path(result_path, "result");
    if (normalized_absolute(capture_path) == normalized_absolute(result_path)) {
        throw std::invalid_argument("capture and result paths must be different");
    }
}

UartArtifactFiles::UartArtifactFiles(
    const std::filesystem::path& capture_path,
    const std::filesystem::path& result_path
) {
    validate_uart_artifact_paths(capture_path, result_path);
    impl_ = std::make_unique<Impl>(capture_path, result_path);
}

UartArtifactFiles::~UartArtifactFiles() = default;

UartArtifactFiles::UartArtifactFiles(UartArtifactFiles&&) noexcept = default;

UartArtifactFiles& UartArtifactFiles::operator=(UartArtifactFiles&&) noexcept = default;

void UartArtifactFiles::write(const UartArtifactRecorder& recorder) {
    if (!impl_ || impl_->written) {
        throw std::logic_error("UART artifacts were already written");
    }
    const auto encoded_results = reference::encode_case_results(recorder.results());
    impl_->capture.write_all(recorder.capture());
    impl_->result.write_all(std::span(
        reinterpret_cast<const std::uint8_t*>(encoded_results.data()),
        encoded_results.size()
    ));
    impl_->written = true;
}

void write_uart_artifacts(
    const std::filesystem::path& capture_path,
    const std::filesystem::path& result_path,
    const UartArtifactRecorder& recorder
) {
    UartArtifactFiles files(capture_path, result_path);
    files.write(recorder);
}

}
