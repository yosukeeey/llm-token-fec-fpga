#pragma once

#include <cstdint>
#include <span>
#include <string>
#include <string_view>

#include "reference/bits.hpp"

namespace reference {

[[nodiscard]] Bytes hex_decode(std::string_view value);

[[nodiscard]] std::string hex_encode(std::span<const std::uint8_t> data);

}
