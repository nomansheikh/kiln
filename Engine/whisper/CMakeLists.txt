cmake_minimum_required(VERSION 3.20)
project(kiln-whisper LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_OSX_DEPLOYMENT_TARGET "14.0" CACHE STRING "")

if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

# One self-contained binary: the app bundles and signs a single file per helper.
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(GGML_METAL ON CACHE BOOL "" FORCE)
# The helper runs on every Apple Silicon Mac, not only on the one that built it.
# Left on, ggml builds for the chip it is compiled on, and an M1 lacks
# instructions a newer chip has.
set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
set(GGML_METAL_EMBED_LIBRARY ON CACHE BOOL "" FORCE)
set(WHISPER_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_SERVER OFF CACHE BOOL "" FORCE)

add_subdirectory(../../Vendor/whisper.cpp whispercpp EXCLUDE_FROM_ALL)

add_executable(kiln-whisper main.cpp)
# json.hpp is the copy whisper.cpp ships for its own examples.
target_include_directories(kiln-whisper SYSTEM PRIVATE ../../Vendor/whisper.cpp/examples)
target_link_libraries(kiln-whisper PRIVATE whisper)
