cmake_minimum_required(VERSION 3.20)
project(kiln-trellis LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_OSX_DEPLOYMENT_TARGET "14.0" CACHE STRING "")

if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

# One self-contained binary: the app bundles and signs a single file per helper.
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(GGML_METAL ON CACHE BOOL "" FORCE)
set(GGML_METAL_EMBED_LIBRARY ON CACHE BOOL "" FORCE)
# The helper runs on every Apple Silicon Mac, not only on the one that built it.
set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
# WebP textures would need a library downloaded at configure time, and macOS
# reads the PNG ones without help.
set(TRELLIS_WEBP OFF CACHE BOOL "" FORCE)

set(TRELLIS_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../Vendor/trellis.cpp")
add_subdirectory(${TRELLIS_DIR} trelliscpp EXCLUDE_FROM_ALL)
# trellis.cpp names its bundled libraries through CMAKE_SOURCE_DIR, which is this
# folder when it is built as a subdirectory, so they are named again here.
target_include_directories(trellis_core PUBLIC
    ${TRELLIS_DIR}/thirdparty/ggml/include
    ${TRELLIS_DIR}/thirdparty/stb
    ${TRELLIS_DIR}/thirdparty/xatlas
    ${TRELLIS_DIR}/thirdparty/meshoptimizer
    ${TRELLIS_DIR}/thirdparty/fqms)

# trellis_cli.cpp holds the whole pipeline behind one function, trellis_run.
add_executable(kiln-trellis main.cpp ${TRELLIS_DIR}/src/trellis_cli.cpp ${TRELLIS_DIR}/src/trellis_args.cpp)
target_include_directories(kiln-trellis PRIVATE ${TRELLIS_DIR}/src)
# json.hpp is the copy whisper.cpp ships for its own examples.
target_include_directories(kiln-trellis SYSTEM PRIVATE ../../Vendor/whisper.cpp/examples)
target_link_libraries(kiln-trellis PRIVATE trellis_core)
