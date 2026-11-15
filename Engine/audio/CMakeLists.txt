cmake_minimum_required(VERSION 3.20)
project(kiln-audio LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_OSX_DEPLOYMENT_TARGET "14.0" CACHE STRING "")

if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

set(AUDIOCPP_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../Vendor/audio.cpp)

# One self-contained binary: the app bundles and signs a single file per helper.
set(ENGINE_ENABLE_METAL ON CACHE BOOL "" FORCE)
set(GGML_METAL_EMBED_LIBRARY ON CACHE BOOL "" FORCE)
set(ENGINE_ENABLE_CUDA OFF CACHE BOOL "" FORCE)
set(ENGINE_ENABLE_VULKAN OFF CACHE BOOL "" FORCE)
set(ENGINE_ENABLE_OPENMP OFF CACHE BOOL "" FORCE)
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
# The app ships to other Macs, so the CPU code must not assume this one's chip.
set(ENGINE_ENABLE_NATIVE_CPU OFF CACHE BOOL "" FORCE)
set(ENGINE_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(ENGINE_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(AUDIOCPP_BUILD_NATIVE_MODEL_MANAGER OFF CACHE BOOL "" FORCE)
# Compile the model descriptions in, so the helper needs no files beside it.
set(AUDIOCPP_DEPLOYMENT_BUILD ON CACHE BOOL "" FORCE)
# Only the model families Kiln has recipes for are compiled in.
set(AUDIOCPP_MODEL_SET "custom" CACHE STRING "" FORCE)
set(AUDIOCPP_MODELS "pocket_tts" CACHE STRING "" FORCE)

add_subdirectory(${AUDIOCPP_DIR} audiocpp EXCLUDE_FROM_ALL)

# audio.cpp builds its C interface only as a shared library. Compiling that one
# file into the helper gives the same interface without a second file to ship.
add_executable(kiln-audio main.cpp ${AUDIOCPP_DIR}/src/capi/audiocpp.cpp)
target_compile_definitions(kiln-audio PRIVATE AUDIOCPP_VERSION_STRING="${AUDIOCPP_VERSION}")
target_include_directories(kiln-audio PRIVATE ${AUDIOCPP_DIR}/include)
# json.hpp is the copy stable-diffusion.cpp ships, the one kiln-engine uses.
target_include_directories(kiln-audio SYSTEM PRIVATE ../../Vendor/stable-diffusion.cpp/thirdparty)
target_link_libraries(kiln-audio PRIVATE engine_runtime ggml)
