cmake_minimum_required(VERSION 3.20)
project(kiln-engine LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_OSX_DEPLOYMENT_TARGET "14.0" CACHE STRING "")

if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

set(SD_METAL ON CACHE BOOL "" FORCE)
set(SD_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(SD_WEBP OFF CACHE BOOL "" FORCE)
set(SD_WEBM OFF CACHE BOOL "" FORCE)

add_subdirectory(../Vendor/stable-diffusion.cpp sdcpp EXCLUDE_FROM_ALL)

add_executable(kiln-engine main.cpp)
target_link_libraries(kiln-engine PRIVATE stable-diffusion)
