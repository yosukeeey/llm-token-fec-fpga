#pragma once

#include <filesystem>
#include <vector>

#include "host/uart_transaction.hpp"

namespace host {

[[nodiscard]] std::vector<UartCase> load_uart_cases(
    const std::filesystem::path& vector_path
);

}
