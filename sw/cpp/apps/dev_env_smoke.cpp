#include <cstdlib>
#include <iostream>
#include <string_view>

int main() {
    constexpr std::string_view status = "ok";

    if (status != "ok") {
        return EXIT_FAILURE;
    }

    std::cout << "cpp_development_environment: ok\n";
    return EXIT_SUCCESS;
}
