#!/bin/sh
# Builds the helpers, each with Metal:
#   build/engine/kiln-engine    stable-diffusion.cpp, makes images
#   build/whisper/kiln-whisper  whisper.cpp, turns speech into text
#   build/audio/kiln-audio      audio.cpp, turns text into speech
set -eu

root="$(cd "$(dirname "$0")/.." && pwd)"

for library in stable-diffusion.cpp whisper.cpp audio.cpp; do
    if [ ! -f "$root/Vendor/$library/CMakeLists.txt" ]; then
        echo "error: $library is missing. Run: git submodule update --init --recursive" >&2
        exit 1
    fi
done

cmake -S "$root/Engine" -B "$root/build/engine" -DCMAKE_BUILD_TYPE=Release
cmake --build "$root/build/engine" --target kiln-engine -j "$(sysctl -n hw.ncpu)"

cmake -S "$root/Engine/whisper" -B "$root/build/whisper" -DCMAKE_BUILD_TYPE=Release
cmake --build "$root/build/whisper" --target kiln-whisper -j "$(sysctl -n hw.ncpu)"

cmake -S "$root/Engine/audio" -B "$root/build/audio" -DCMAKE_BUILD_TYPE=Release
cmake --build "$root/build/audio" --target kiln-audio -j "$(sysctl -n hw.ncpu)"
