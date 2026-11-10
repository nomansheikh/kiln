#!/bin/sh
# Builds the kiln-engine helper (stable-diffusion.cpp with Metal).
# Output: build/engine/kiln-engine
set -eu

root="$(cd "$(dirname "$0")/.." && pwd)"

if [ ! -f "$root/Vendor/stable-diffusion.cpp/CMakeLists.txt" ]; then
    echo "error: stable-diffusion.cpp is missing. Run: git submodule update --init --recursive" >&2
    exit 1
fi

cmake -S "$root/Engine" -B "$root/build/engine" -DCMAKE_BUILD_TYPE=Release
cmake --build "$root/build/engine" --target kiln-engine -j "$(sysctl -n hw.ncpu)"
