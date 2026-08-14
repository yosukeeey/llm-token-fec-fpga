#pragma once

#include <filesystem>
#include <memory>
#include <span>
#include <string_view>
#include <vector>

#include "host/uart_transaction.hpp"
#include "reference/vector.hpp"

namespace host {

class UartArtifactRecorder final : public UartObserver {
public:
    void received(std::span<const std::uint8_t> data) override;

    void completed(
        std::string_view case_id,
        std::span<const std::uint8_t> response
    ) override;

    [[nodiscard]] const reference::Bytes& capture() const noexcept;

    [[nodiscard]] const std::vector<reference::CaseResult>& results() const noexcept;

private:
    reference::Bytes capture_;
    std::vector<reference::CaseResult> results_;
};

class UartArtifactFiles final {
public:
    UartArtifactFiles(
        const std::filesystem::path& capture_path,
        const std::filesystem::path& result_path
    );

    ~UartArtifactFiles();

    UartArtifactFiles(UartArtifactFiles&&) noexcept;
    UartArtifactFiles& operator=(UartArtifactFiles&&) noexcept;

    UartArtifactFiles(const UartArtifactFiles&) = delete;
    UartArtifactFiles& operator=(const UartArtifactFiles&) = delete;

    void write(const UartArtifactRecorder& recorder);

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};

void validate_uart_artifact_paths(
    const std::filesystem::path& capture_path,
    const std::filesystem::path& result_path
);

void write_uart_artifacts(
    const std::filesystem::path& capture_path,
    const std::filesystem::path& result_path,
    const UartArtifactRecorder& recorder
);

}
