cmake_minimum_required(VERSION 3.25)

project(llm_token_fec_fpga LANGUAGES CXX)

add_library(reference_model STATIC
    sw/cpp/src/bits.cpp
    sw/cpp/src/crc32c.cpp
    sw/cpp/src/fec.cpp
    sw/cpp/src/hex.cpp
    sw/cpp/src/protocol.cpp
)
target_include_directories(reference_model PUBLIC sw/cpp/include)
target_compile_features(reference_model PUBLIC cxx_std_20)

add_executable(dev_env_smoke sw/cpp/apps/dev_env_smoke.cpp)
target_compile_features(dev_env_smoke PRIVATE cxx_std_20)

if(MSVC)
    target_compile_options(reference_model PRIVATE /W4 /WX /permissive- /utf-8)
    target_compile_options(dev_env_smoke PRIVATE /W4 /permissive- /utf-8)
endif()

include(CTest)
if(BUILD_TESTING)
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

    add_executable(reference_unit_test sw/cpp/tests/reference_unit_test.cpp)
    target_link_libraries(reference_unit_test PRIVATE reference_model)

    add_executable(reference_vector_test sw/cpp/tests/reference_vector_test.cpp)
    target_link_libraries(reference_vector_test PRIVATE reference_vector_io)

    if(MSVC)
        target_compile_options(reference_vector_io PRIVATE /W4 /WX /permissive- /utf-8)
        target_compile_options(reference_unit_test PRIVATE /W4 /WX /permissive- /utf-8)
        target_compile_options(reference_vector_test PRIVATE /W4 /WX /permissive- /utf-8)
    endif()

    add_test(NAME dev_env_smoke COMMAND dev_env_smoke)
    add_test(NAME reference_unit_test COMMAND reference_unit_test)
    add_test(
        NAME reference_vector_test
        COMMAND reference_vector_test "${CMAKE_SOURCE_DIR}/datasets/test_vectors/protocol_v0"
    )
endif()
