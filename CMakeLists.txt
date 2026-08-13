cmake_minimum_required(VERSION 3.25)

project(llm_token_fec_fpga LANGUAGES CXX)

if(MSVC)
    add_compile_definitions(_WIN32_WINNT=0x0600)
endif()

add_library(reference_model STATIC
    sw/cpp/src/bits.cpp
    sw/cpp/src/crc32c.cpp
    sw/cpp/src/fec.cpp
    sw/cpp/src/hex.cpp
    sw/cpp/src/protocol.cpp
    sw/cpp/src/types.cpp
)
target_include_directories(reference_model PUBLIC sw/cpp/include)
target_compile_features(reference_model PUBLIC cxx_std_20)

add_executable(dev_env_smoke sw/cpp/apps/dev_env_smoke.cpp)
target_compile_features(dev_env_smoke PRIVATE cxx_std_20)

add_library(uart_runner_core STATIC sw/cpp/src/uart_transaction.cpp)
target_include_directories(uart_runner_core PUBLIC sw/cpp/include)
target_link_libraries(uart_runner_core PUBLIC reference_model)
target_compile_features(uart_runner_core PUBLIC cxx_std_20)

if(MSVC)
    target_compile_options(reference_model PRIVATE /W4 /WX /permissive- /utf-8)
    target_compile_options(dev_env_smoke PRIVATE /W4 /permissive- /utf-8)
    target_compile_options(uart_runner_core PRIVATE /W4 /WX /permissive- /utf-8)
endif()

include(CTest)
if(BUILD_TESTING OR WIN32)
    set(
        NLOHMANN_JSON_INCLUDE_DIR
        "${CMAKE_SOURCE_DIR}/build/tools/nlohmann-json/include"
        CACHE PATH
        "Path containing nlohmann/json.hpp"
    )
    if(NOT EXISTS "${NLOHMANN_JSON_INCLUDE_DIR}/nlohmann/json.hpp")
        message(FATAL_ERROR "Run scripts/bootstrap.ps1 to install the pinned JSON test dependency")
    endif()

    add_library(reference_vector_io STATIC sw/cpp/src/vector.cpp)
    target_include_directories(reference_vector_io PRIVATE "${NLOHMANN_JSON_INCLUDE_DIR}")
    target_link_libraries(reference_vector_io PUBLIC reference_model)
    target_compile_features(reference_vector_io PUBLIC cxx_std_20)

    add_library(uart_vector_cases STATIC sw/cpp/src/uart_vector_cases.cpp)
    target_include_directories(uart_vector_cases PUBLIC sw/cpp/include)
    target_link_libraries(uart_vector_cases PUBLIC uart_runner_core reference_vector_io)
    target_compile_features(uart_vector_cases PUBLIC cxx_std_20)

    if(MSVC)
        target_compile_options(reference_vector_io PRIVATE /W4 /WX /permissive- /utf-8)
        target_compile_options(uart_vector_cases PRIVATE /W4 /WX /permissive- /utf-8)
    endif()
endif()

if(WIN32)
    add_library(win32_serial STATIC sw/cpp/src/win32_serial.cpp)
    target_include_directories(win32_serial PUBLIC sw/cpp/include)
    target_link_libraries(win32_serial PUBLIC uart_runner_core)
    target_compile_features(win32_serial PUBLIC cxx_std_20)

    add_executable(uart_vector_runner sw/cpp/apps/uart_vector_runner.cpp)
    target_link_libraries(uart_vector_runner PRIVATE uart_vector_cases win32_serial)
    target_compile_features(uart_vector_runner PRIVATE cxx_std_20)

    if(MSVC)
        target_compile_options(win32_serial PRIVATE /W4 /WX /permissive- /utf-8)
        target_compile_options(uart_vector_runner PRIVATE /W4 /WX /permissive- /utf-8)
    endif()
endif()

if(BUILD_TESTING)
    add_executable(reference_unit_test sw/cpp/tests/reference_unit_test.cpp)
    target_link_libraries(reference_unit_test PRIVATE reference_model)

    add_executable(reference_vector_test sw/cpp/tests/reference_vector_test.cpp)
    target_link_libraries(reference_vector_test PRIVATE reference_vector_io)

    add_executable(uart_transaction_test sw/cpp/tests/uart_transaction_test.cpp)
    target_link_libraries(uart_transaction_test PRIVATE uart_vector_cases)

    if(MSVC)
        target_compile_options(reference_unit_test PRIVATE /W4 /WX /permissive- /utf-8)
        target_compile_options(reference_vector_test PRIVATE /W4 /WX /permissive- /utf-8)
        target_compile_options(uart_transaction_test PRIVATE /W4 /WX /permissive- /utf-8)
    endif()

    add_test(NAME dev_env_smoke COMMAND dev_env_smoke)
    add_test(NAME reference_unit_test COMMAND reference_unit_test)
    add_test(
        NAME reference_vector_test
        COMMAND reference_vector_test "${CMAKE_SOURCE_DIR}/datasets/test_vectors/protocol_v0"
    )
    add_test(
        NAME uart_transaction_test
        COMMAND uart_transaction_test
                "${CMAKE_SOURCE_DIR}/datasets/test_vectors/protocol_v0/protocol_pipeline.jsonl"
    )
endif()
