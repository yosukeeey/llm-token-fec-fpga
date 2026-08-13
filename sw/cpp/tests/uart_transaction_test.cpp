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
#include <memory>
#include <span>
#include <stdexcept>
#include <string>
#include <string_view>
#include <system_error>
#include <utility>
#include <vector>

#include "host/uart_transaction.hpp"
#include "host/uart_vector_cases.hpp"

namespace {

enum class StepKind {
    data,
    timeout,
    failure,
    zero,
};

struct WriteStep {
    StepKind kind{StepKind::data};
    std::size_t limit{};
};

struct ReadStep {
    StepKind kind{StepKind::data};
    reference::Bytes data;
};

class ScriptedTransport final : public host::ByteTransport {
public:
    explicit ScriptedTransport(int* destroyed = nullptr) : destroyed_(destroyed) {}

    ~ScriptedTransport() override {
        if (destroyed_ != nullptr) {
            ++*destroyed_;
        }
    }

    std::size_t write_some(
        const std::span<const std::uint8_t> data,
        const host::UartClock::time_point deadline
    ) override {
        write_deadlines.push_back(deadline);
        WriteStep step{StepKind::data, data.size()};
        if (!write_steps.empty()) {
            step = write_steps.front();
            write_steps.pop_front();
        }
        if (step.kind == StepKind::timeout) {
            throw host::TransportTimeout("scripted write timeout");
        }
        if (step.kind == StepKind::failure) {
            throw std::runtime_error("scripted write failure");
        }
        if (step.kind == StepKind::zero) {
            return 0U;
        }
        const auto count = std::min(data.size(), step.limit);
        written.insert(written.end(), data.begin(), data.begin() + static_cast<std::ptrdiff_t>(count));
        return count;
    }

    std::size_t read_some(
        const std::span<std::uint8_t> data,
        const host::UartClock::time_point deadline
    ) override {
        read_deadlines.push_back(deadline);
        if (read_steps.empty()) {
            throw std::runtime_error("scripted read exhausted");
        }
        auto step = std::move(read_steps.front());
        read_steps.pop_front();
        if (step.kind == StepKind::timeout) {
            throw host::TransportTimeout("scripted read timeout");
        }
        if (step.kind == StepKind::failure) {
            throw std::runtime_error("scripted read failure");
        }
        if (step.kind == StepKind::zero) {
            return 0U;
        }
        const auto count = std::min(data.size(), step.data.size());
        std::copy_n(step.data.begin(), count, data.begin());
        if (count < step.data.size()) {
            step.data.erase(step.data.begin(), step.data.begin() + static_cast<std::ptrdiff_t>(count));
            read_steps.push_front(std::move(step));
        }
        return count;
    }

    std::deque<WriteStep> write_steps;
    std::deque<ReadStep> read_steps;
    reference::Bytes written;
    std::vector<host::UartClock::time_point> write_deadlines;
    std::vector<host::UartClock::time_point> read_deadlines;

private:
    int* destroyed_;
};

class TempDirectory {
public:
    TempDirectory()
        : path_(std::filesystem::temp_directory_path()
                / ("uart-transaction-test-"
                   + std::to_string(host::UartClock::now().time_since_epoch().count()))) {
        std::filesystem::create_directories(path_);
    }

    ~TempDirectory() {
        std::error_code ignored;
        std::filesystem::remove_all(path_, ignored);
    }

    [[nodiscard]] const std::filesystem::path& path() const noexcept {
        return path_;
    }

private:
    std::filesystem::path path_;
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
            "failure message mismatch"
        );
        return;
    }
    throw std::runtime_error("expected failure was not raised");
}

reference::Bytes joined_requests(const std::span<const host::UartCase> cases) {
    reference::Bytes output;
    for (const auto& uart_case : cases) {
        output.insert(output.end(), uart_case.request.begin(), uart_case.request.end());
    }
    return output;
}

void append_fragmented_reads(
    ScriptedTransport& transport,
    const std::span<const std::uint8_t> data
) {
    std::size_t offset = 0;
    for (const std::size_t size : {1U, 2U, 5U, 3U}) {
        if (offset == data.size()) {
            break;
        }
        const auto count = std::min(size, data.size() - offset);
        transport.read_steps.push_back({
            StepKind::data,
            reference::Bytes(
                data.begin() + static_cast<std::ptrdiff_t>(offset),
                data.begin() + static_cast<std::ptrdiff_t>(offset + count)
            ),
        });
        offset += count;
    }
    if (offset < data.size()) {
        transport.read_steps.push_back({
            StepKind::data,
            reference::Bytes(data.begin() + static_cast<std::ptrdiff_t>(offset), data.end()),
        });
    }
}

void test_fixed_vectors(const std::vector<host::UartCase>& cases) {
    require(cases.size() == 2U, "fixed UART case count mismatch");
    ScriptedTransport transport;
    transport.write_steps = {
        {StepKind::data, 1U},
        {StepKind::data, 2U},
        {StepKind::data, 3U},
        {StepKind::data, 4U},
    };
    for (const auto& uart_case : cases) {
        append_fragmented_reads(transport, uart_case.expected_response);
    }
    const auto passed = host::run_uart_cases(
        transport,
        cases,
        std::chrono::milliseconds(1'000)
    );
    require(passed == cases.size(), "fixed UART cases did not pass");
    require(transport.written == joined_requests(cases), "fixed UART request order changed");
}

void test_partial_io_and_deadline(const host::UartCase& uart_case) {
    ScriptedTransport transport;
    transport.write_steps = {
        {StepKind::data, 1U},
        {StepKind::data, 2U},
        {StepKind::data, 1U},
    };
    append_fragmented_reads(transport, uart_case.expected_response);
    require(
        host::run_uart_cases(transport, std::span(&uart_case, 1), std::chrono::seconds(1)) == 1U,
        "partial I/O case failed"
    );
    require(transport.written == uart_case.request, "partial write changed request bytes");
    require(!transport.write_deadlines.empty(), "write deadline was not recorded");
    require(!transport.read_deadlines.empty(), "read deadline was not recorded");
    const auto deadline = transport.write_deadlines.front();
    require(
        std::all_of(
            transport.write_deadlines.begin(),
            transport.write_deadlines.end(),
            [deadline](const auto value) { return value == deadline; }
        ),
        "partial writes changed the absolute deadline"
    );
    require(
        std::all_of(
            transport.read_deadlines.begin(),
            transport.read_deadlines.end(),
            [deadline](const auto value) { return value == deadline; }
        ),
        "reads did not share the write deadline"
    );
}

void test_timeout_and_cleanup(const host::UartCase& uart_case) {
    int success_destroyed = 0;
    auto success_transport = std::make_unique<ScriptedTransport>(&success_destroyed);
    success_transport->read_steps.push_back({StepKind::data, uart_case.expected_response});
    require(
        host::run_uart_session(
            std::move(success_transport),
            std::span(&uart_case, 1),
            std::chrono::seconds(1)
        ) == 1U,
        "owned transport success failed"
    );
    require(success_destroyed == 1, "transport was not destroyed after success");

    for (const auto write_timeout : {true, false}) {
        int destroyed = 0;
        auto transport = std::make_unique<ScriptedTransport>(&destroyed);
        if (write_timeout) {
            transport->write_steps.push_back({StepKind::timeout, 0U});
        } else {
            transport->read_steps.push_back({StepKind::timeout, {}});
        }
        require_failure(
            [&] {
                static_cast<void>(host::run_uart_session(
                    std::move(transport),
                    std::span(&uart_case, 1),
                    std::chrono::milliseconds(10)
                ));
            },
            "timeout"
        );
        require(destroyed == 1, "transport was not destroyed after timeout");
    }

    ScriptedTransport partial;
    partial.read_steps.push_back({
        StepKind::data,
        reference::Bytes(uart_case.expected_response.begin(), uart_case.expected_response.begin() + 4),
    });
    partial.read_steps.push_back({StepKind::timeout, {}});
    require_failure(
        [&] {
            static_cast<void>(host::run_uart_cases(
                partial,
                std::span(&uart_case, 1),
                std::chrono::milliseconds(10)
            ));
        },
        "timeout"
    );
}

void test_transport_failures(const host::UartCase& uart_case) {
    for (const auto kind : {StepKind::failure, StepKind::zero}) {
        ScriptedTransport write_transport;
        write_transport.write_steps.push_back({kind, 0U});
        require_failure(
            [&] {
                static_cast<void>(host::run_uart_cases(
                    write_transport,
                    std::span(&uart_case, 1),
                    std::chrono::seconds(1)
                ));
            },
            kind == StepKind::failure ? "write failure" : "invalid progress"
        );

        ScriptedTransport read_transport;
        read_transport.read_steps.push_back({kind, {}});
        require_failure(
            [&] {
                static_cast<void>(host::run_uart_cases(
                    read_transport,
                    std::span(&uart_case, 1),
                    std::chrono::seconds(1)
                ));
            },
            kind == StepKind::failure ? "read failure" : "invalid progress"
        );
    }
}

void test_malformed_recovery(const std::vector<host::UartCase>& cases) {
    auto malformed = cases.front().expected_response;
    malformed.back() ^= 1U;
    auto combined = malformed;
    combined.insert(
        combined.end(),
        cases.front().expected_response.begin(),
        cases.front().expected_response.end()
    );

    ScriptedTransport transport;
    transport.read_steps.push_back({StepKind::data, std::move(combined)});
    transport.read_steps.push_back({StepKind::data, cases.back().expected_response});
    require_failure(
        [&] {
            static_cast<void>(host::run_uart_cases(
                transport,
                std::span(cases).first(1),
                std::chrono::seconds(1)
            ));
        },
        "resynchronization"
    );
    require(
        host::run_uart_cases(
            transport,
            std::span(cases).last(1),
            std::chrono::seconds(1)
        ) == 1U,
        "transport did not recover after malformed response"
    );
}

void test_response_mismatch(const std::vector<host::UartCase>& cases) {
    ScriptedTransport mismatch;
    mismatch.read_steps.push_back({StepKind::data, cases.back().expected_response});
    require_failure(
        [&] {
            static_cast<void>(host::run_uart_cases(
                mismatch,
                std::span(cases).first(1),
                std::chrono::seconds(1)
            ));
        },
        "does not match"
    );

    auto duplicate = cases.front().expected_response;
    duplicate.insert(
        duplicate.end(),
        cases.front().expected_response.begin(),
        cases.front().expected_response.end()
    );
    ScriptedTransport multiple;
    multiple.read_steps.push_back({StepKind::data, std::move(duplicate)});
    require_failure(
        [&] {
            static_cast<void>(host::run_uart_cases(
                multiple,
                std::span(cases).first(1),
                std::chrono::seconds(1)
            ));
        },
        "more than one Frame"
    );
}

std::string read_text(const std::filesystem::path& path) {
    std::ifstream input(path, std::ios::binary);
    if (!input) {
        throw std::runtime_error("cannot read fixture");
    }
    return {
        std::istreambuf_iterator<char>(input),
        std::istreambuf_iterator<char>(),
    };
}

void write_text(const std::filesystem::path& path, const std::string_view value) {
    std::ofstream output(path, std::ios::binary);
    if (!output) {
        throw std::runtime_error("cannot write fixture");
    }
    output << value;
}

std::string replaced_once(
    std::string value,
    const std::string_view source,
    const std::string_view replacement
) {
    const auto position = value.find(source);
    if (position == std::string::npos) {
        throw std::runtime_error("fixture token was not found");
    }
    value.replace(position, source.size(), replacement);
    return value;
}

void test_vector_validation(const std::filesystem::path& vector_path) {
    TempDirectory temporary;
    const auto source = read_text(vector_path);
    const std::vector<std::pair<std::string, std::string>> invalid_files{
        {"empty.jsonl", ""},
        {
            "algorithm.jsonl",
            replaced_once(source, "\"algorithm\":\"protocol_pipeline\"", "\"algorithm\":\"frame_v0\"")
        },
        {
            "alignment.jsonl",
            replaced_once(source, "\"input_bit_length\":96", "\"input_bit_length\":95")
        },
        {
            "frame.jsonl",
            replaced_once(source, "\"input_hex\":\"a55a", "\"input_hex\":\"005a")
        },
    };
    for (const auto& [name, content] : invalid_files) {
        const auto path = temporary.path() / name;
        write_text(path, content);
        require_failure(
            [&] { static_cast<void>(host::load_uart_cases(path)); },
            name == "empty.jsonl" ? "must not be empty" : "UART"
        );
    }
}

void test_invalid_arguments(const host::UartCase& uart_case) {
    ScriptedTransport transport;
    require_failure(
        [&] {
            static_cast<void>(host::run_uart_cases(
                transport,
                {},
                std::chrono::seconds(1)
            ));
        },
        "must not be empty"
    );
    require_failure(
        [&] {
            static_cast<void>(host::run_uart_cases(
                transport,
                std::span(&uart_case, 1),
                std::chrono::milliseconds(0)
            ));
        },
        "must be positive"
    );
    require_failure(
        [&] {
            static_cast<void>(host::run_uart_cases(
                transport,
                std::span(&uart_case, 1),
                std::chrono::milliseconds::max()
            ));
        },
        "clock range"
    );
    require_failure(
        [&] {
            static_cast<void>(host::run_uart_session(
                nullptr,
                std::span(&uart_case, 1),
                std::chrono::seconds(1)
            ));
        },
        "must not be null"
    );

    auto invalid_case = uart_case;
    invalid_case.request.front() = 0U;
    require_failure(
        [&] {
            static_cast<void>(host::run_uart_cases(
                transport,
                std::span(&invalid_case, 1),
                std::chrono::seconds(1)
            ));
        },
        "SOF"
    );
    require(transport.written.empty(), "invalid case reached the transport");
}

}

int main(const int argument_count, const char* const arguments[]) {
    try {
        if (argument_count != 2) {
            throw std::invalid_argument("expected protocol pipeline vector path");
        }
        const std::filesystem::path vector_path(arguments[1]);
        const auto cases = host::load_uart_cases(vector_path);
        test_fixed_vectors(cases);
        test_partial_io_and_deadline(cases.front());
        test_timeout_and_cleanup(cases.front());
        test_transport_failures(cases.front());
        test_malformed_recovery(cases);
        test_response_mismatch(cases);
        test_vector_validation(vector_path);
        test_invalid_arguments(cases.front());
        std::cout << "uart_transaction_test: 8 cases passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "uart_transaction_test: " << error.what() << '\n';
        return 1;
    }
}
