# Third-party software

Kiln itself is MIT licensed (see [LICENSE](LICENSE)). The Swift app and the `KilnCore` library use only Apple system frameworks and have no third-party Swift dependencies.

The `kiln-engine` helper is statically linked against the components below. This list covers what is compiled into the helper with the options set in [Engine/CMakeLists.txt](Engine/CMakeLists.txt): Metal on, examples off, WebP off, WebM off, no CUDA.

Paths are relative to `Vendor/stable-diffusion.cpp/`, a git submodule.

## Components in the shipped helper

| Component | License | Upstream | License verified from |
| --- | --- | --- | --- |
| stable-diffusion.cpp | MIT, Copyright (c) 2023 leejet | https://github.com/leejet/stable-diffusion.cpp | `LICENSE` |
| ggml (the `leejet/ggml` fork used by stable-diffusion.cpp), including its CPU, BLAS and Metal backends | MIT, Copyright (c) 2023-2026 The ggml authors | https://github.com/leejet/ggml | `ggml/LICENSE` |
| JSON for Modern C++ (`thirdparty/json.hpp`, version 3.11.2). Also included directly by `Engine/main.cpp`. | MIT, Copyright 2013-2022 Niels Lohmann | https://github.com/nlohmann/json | SPDX header in the file |
| zip (`thirdparty/zip.c`, `thirdparty/zip.h`) | license not verified. The vendored files carry only a warranty disclaimer and no license name; see the upstream repository. | https://github.com/kuba--/zip | not determinable from the vendored files |
| miniz 2.2.0 (`thirdparty/miniz.h`, included by `zip.c`) | Public domain (Unlicense statement at the end of the file). The file also contains a section under an MIT-style notice, Copyright 2013-2014 RAD Game Tools and Valve Software, Copyright 2010-2014 Rich Geldreich and Tenacious Software LLC. | https://github.com/richgel999/miniz | notices in the file |
| Darts-clone (`thirdparty/darts.h`) | BSD 3-Clause, Copyright (c) 2008-2011 Susumu Yata | https://github.com/google/sentencepiece/tree/master/third_party/darts_clone | `thirdparty/LICENSE.darts_clone.txt` |
| Oniguruma 6.9.10 (`thirdparty/oniguruma/`, source subset) | BSD 2-Clause, Copyright (c) 2002-2021 K.Kosako | https://github.com/kkos/oniguruma | `thirdparty/oniguruma/COPYING` |
| utf8proc 2.10.0 (`thirdparty/utf8proc/`) | MIT, Copyright (c) 2014-2021 Steven G. Johnson, Jiahao Chen, Tony Kelman, Jonas Fonseca and other contributors; Copyright (c) 2009, 2013 Public Software Group e. V. Its Unicode data tables are under the Unicode data license, Copyright (c) 1991-2007 Unicode, Inc. | https://github.com/JuliaStrings/utf8proc | `thirdparty/utf8proc/LICENSE.md` |

### Notices inside the components above

- ggml's RoPE implementation (`ggml/src/ggml-cpu/ops.cpp` and `ggml/src/ggml-metal/kernels/rope.metal`) includes the YaRN algorithm based on https://github.com/jquesnelle/yarn, marked in the source as MIT licensed, Copyright (c) 2023 Jeffrey Quesnelle and Bowen Peng.
- stable-diffusion.cpp embeds tokenizer vocabulary data in `src/tokenizers/vocab/` (CLIP, T5, UMT5, Gemma, Mistral and Qwen vocabularies and merge tables). These files carry no license notices: license not verified.

## Vendored but not compiled into the helper

These are present in the submodule tree or referenced by it, but are not part of the Metal build Kiln ships, so their licenses do not apply to the helper binary:

| Component | Why it is excluded |
| --- | --- |
| cpp-httplib (`thirdparty/httplib.h`) | Not included by any library source; the examples are not built (`SD_BUILD_EXAMPLES=OFF`). |
| stb (`thirdparty/stb_image.h`, `stb_image_resize.h`, `stb_image_write.h`) | Not included by any library source. |
| libwebp (`thirdparty/libwebp`) | `SD_WEBP=OFF`. |
| libwebm (`thirdparty/libwebm`) | `SD_WEBM=OFF`. |
| CUTLASS (`thirdparty/cutlass`) and the CUDA sources under `src/core/cuda/` | CUDA only. |
| ggml's `llamafile` and KleidiAI CPU kernels | `GGML_LLAMAFILE` and `GGML_CPU_KLEIDIAI` are off in this build. |

If the build options in `Engine/CMakeLists.txt` change, this file must be updated.

## Model weights

Kiln does not bundle or distribute model weights. Models are downloaded by the user from Hugging Face and each carries its own license, which the user is responsible for complying with. For the curated recipes:

- Qwen-Image 2.1 Turbo: the denoiser and VAE are under the Qwen Research License (non-commercial).
- Stable Diffusion XL Base 1.0: CreativeML Open RAIL++-M License.

Each recipe's `license_note` field summarizes the terms, but the model's page on Hugging Face is authoritative.
