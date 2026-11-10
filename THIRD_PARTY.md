# Third-party software

Kiln itself is MIT licensed (see [LICENSE](LICENSE)). The Swift app and the `KilnCore` library use only Apple system frameworks and have no third-party Swift dependencies.

The `kiln-engine` helper is statically linked against the components below. This list covers what is compiled into the helper with the options set in [Engine/CMakeLists.txt](Engine/CMakeLists.txt): Metal on, examples off, WebP off, WebM off, no CUDA.

Paths are relative to `Vendor/stable-diffusion.cpp/`, a git submodule. This file was last checked against submodule commit `465adf389f252e401257f44efb0ea49da8e4e80b` on 2026-11-11.

## Components in the shipped helper

| Component | License | Upstream | License verified from |
| --- | --- | --- | --- |
| stable-diffusion.cpp | MIT, Copyright (c) 2023 leejet | https://github.com/leejet/stable-diffusion.cpp | `LICENSE` |
| ggml (the `leejet/ggml` fork used by stable-diffusion.cpp), including its CPU, BLAS (Apple Accelerate) and Metal backends | MIT, Copyright (c) 2023-2026 The ggml authors | https://github.com/leejet/ggml | `ggml/LICENSE` |
| JSON for Modern C++ (`thirdparty/json.hpp`, version 3.11.2). Also included directly by `Engine/main.cpp`. | MIT, Copyright 2013-2022 Niels Lohmann | https://github.com/nlohmann/json | SPDX header in the file |
| zip (`thirdparty/zip.c`, `thirdparty/zip.h`) | Public domain (Unlicense) for the vendored snapshot; upstream has since relicensed to MIT. See [zip](#zip) below. | https://github.com/kuba--/zip | Upstream `UNLICENSE` at commit `fb8df0f`, and upstream `LICENSE.txt` on `master` |
| miniz 2.2.0 (`thirdparty/miniz.h`, included by `zip.c`) | Public domain (Unlicense statement at the end of the file). The file also contains a section under an MIT-style notice, Copyright 2013-2014 RAD Game Tools and Valve Software, Copyright 2010-2014 Rich Geldreich and Tenacious Software LLC. | https://github.com/richgel999/miniz | notices in the file |
| Darts-clone (`thirdparty/darts.h`) | BSD 3-Clause, Copyright (c) 2008-2011 Susumu Yata | https://github.com/google/sentencepiece/tree/master/third_party/darts_clone | `thirdparty/LICENSE.darts_clone.txt` |
| Oniguruma 6.9.10 (`thirdparty/oniguruma/`, source subset) | BSD 2-Clause, Copyright (c) 2002-2021 K.Kosako | https://github.com/kkos/oniguruma | `thirdparty/oniguruma/COPYING` |
| utf8proc 2.10.0 (`thirdparty/utf8proc/`) | MIT, Copyright (c) 2014-2021 Steven G. Johnson, Jiahao Chen, Tony Kelman, Jonas Fonseca and other contributors; Copyright (c) 2009, 2013 Public Software Group e. V. Its Unicode data tables are under the Unicode data license, Copyright (c) 1991-2007 Unicode, Inc. | https://github.com/JuliaStrings/utf8proc | `thirdparty/utf8proc/LICENSE.md` |

### zip

The vendored files are the kuba--/zip library, confirmed as follows:

- `thirdparty/README.md` names https://github.com/kuba--/zip as the source.
- `thirdparty/zip.h` is byte-identical (same git blob, `a08c16ab`) to `src/zip.h` at upstream commit `fb8df0f11bc521b47b58b752102d4687687f4286` (2 October 2023). `thirdparty/miniz.h` is byte-identical (blob `71958ccf`) to `src/miniz.h` at the same commit.
- `thirdparty/zip.c` is `src/zip.c` from that commit plus two changes made in stable-diffusion.cpp commit `e1384de` ("perf: make crc32 100x faster on x86-64", PR #278): a `#define USE_EXTERNAL_MZCRC` and an appended `mz_crc32` implementation. The appended code carries no licence notice of its own; it was contributed to the stable-diffusion.cpp repository, whose `LICENSE` is MIT.

License: at commit `fb8df0f` the upstream repository's only licence file was `UNLICENSE` (a public-domain dedication; the warranty disclaimer at the top of `zip.c` and `zip.h` is the disclaimer paragraph of that file). On 23 August 2024 upstream deleted `UNLICENSE` and added `LICENSE.txt`, which is the MIT permission notice with "All Rights Reserved." in place of a named copyright holder; the GitHub licence API reports it as MIT. `thirdparty/README.md` links to that `LICENSE.txt`. The snapshot Kiln ships predates the change, so it was published under the Unlicense. Both are permissive; shipping the upstream MIT text as well satisfies either reading.

### Notices inside the components above

These are fragments ported or copied into the sources that are compiled into the helper. Each is marked in the source with a pointer to its original licence.

| Where | Origin | License | Verified from |
| --- | --- | --- | --- |
| `ggml/src/ggml-cpu/ops.cpp`, `ggml/src/ggml-metal/kernels/rope.metal` (YaRN RoPE) | https://github.com/jquesnelle/yarn | MIT, Copyright (c) 2023 Jeffrey Quesnelle and Bowen Peng | comment in the source; upstream `LICENSE` |
| `src/tokenizers/t5_unigram_tokenizer.cpp` (unigram model, ported) | https://github.com/google/sentencepiece | Apache-2.0 | comment in the source; upstream `LICENSE` as reported by the GitHub licence API. Upstream has no `NOTICE` file in its root. |
| `src/core/rng_mt19937.hpp` (random number generation, ported) | https://github.com/pytorch/pytorch at commit `d01a7b0` | BSD 3-Clause style, with the copyright holders listed in the PyTorch `LICENSE` (Facebook, Idiap, Deepmind, NEC, NYU and others) | comment in the source; upstream `LICENSE` at that commit |
| `src/core/util.cpp` (`sd_get_num_physical_cores`, copied) | https://github.com/ggerganov/llama.cpp | MIT, Copyright (c) 2023-2026 The ggml authors | comment in the source; upstream `LICENSE` |
| `src/runtime/latent-preview.h` (`sd3_latent_rgb_proj` constants) | https://github.com/Stability-AI/sd3.5 at commit `8565799` | MIT, Copyright (c) 2024 Stability AI | comment in the source; upstream `LICENSE-CODE` at that commit |

### Embedded tokenizer vocabularies

stable-diffusion.cpp compiles tokenizer vocabulary and merge tables into the library as byte arrays (`src/tokenizers/vocab/*.hpp`, pulled in by `vocab.cpp`). All of them are linked into the helper regardless of which model is used.

stable-diffusion.cpp makes no statement about the origin or licence of these files. They carry no header or notice, there is no README or licence file in `src/tokenizers/` or `src/tokenizers/vocab/`, and the commits that added them do not name a source. Its `CONTRIBUTING.md` ("Tokenizer Data") only sets a policy on which tokenizers may be embedded (CLIP, T5/UMT5, Qwen 2/3, Mistral, Gemma 3/4) for binary-size reasons. The upstream sources below are therefore inferred from the loader code and the project's model docs, and the licence in each row is the licence of that upstream, not a statement by stable-diffusion.cpp.

| File | Loaded by | Upstream source | License | Where confirmed |
| --- | --- | --- | --- | --- |
| `clip_merges.hpp` | `clip_tokenizer.cpp` | OpenAI CLIP BPE merge table (`clip/bpe_simple_vocab_16e6.txt.gz` in https://github.com/openai/CLIP). The opening lines of the embedded table match `merges.txt` in https://huggingface.co/openai/clip-vit-large-patch14. | MIT, Copyright (c) 2021 OpenAI | `LICENSE` in openai/CLIP. The Hugging Face model card has no licence field. |
| `t5.hpp` | `t5_unigram_tokenizer.cpp` | T5 SentencePiece vocabulary in Hugging Face `tokenizer.json` form (https://huggingface.co/google/t5-v1_1-xxl). That repository ships `spiece.model` rather than `tokenizer.json`, so the embedded file is a conversion whose origin is not stated. | Apache-2.0 | `license: apache-2.0` in the google/t5-v1_1-xxl model card; `LICENSE` of https://github.com/google-research/text-to-text-transfer-transformer |
| `umt5.hpp` | `t5_unigram_tokenizer.cpp` | UMT5 `tokenizer.json` (https://huggingface.co/google/umt5-xxl) | Apache-2.0 | `license: apache-2.0` in the google/umt5-xxl model card |
| `qwen_merges.hpp` | `qwen2_tokenizer.cpp` (also used by `sensenova_u1_tokenizer.cpp`) | Qwen2 BPE merge table. The opening lines of the embedded table match `merges.txt` in https://huggingface.co/Qwen/Qwen2.5-VL-7B-Instruct. | Apache-2.0 | `license: apache-2.0` in the Qwen/Qwen2.5-VL-7B-Instruct and Qwen/Qwen2-7B model cards |
| `mistral_merges.hpp`, `mistral_vocab.hpp` | `mistral_tokenizer.cpp` | Mistral tokenizer for the Flux.2 text encoder, which `docs/flux2.md` names as Mistral-Small-3.2-24B-Instruct-2506 (https://huggingface.co/mistralai/Mistral-Small-3.2-24B-Instruct-2506). The official repository ships the tokenizer as `tekken.json`, so the embedded vocabulary and merge tables are a conversion whose origin is not stated. | Apache-2.0 for the upstream model repository. Provenance of the exact embedded tables: not verified. | `license: apache-2.0` in the model card |
| `gemma_merges.hpp`, `gemma_vocab.hpp` | `gemma_tokenizer.cpp` | Gemma tokenizer, added in stable-diffusion.cpp commit `67dda3f` ("feat: add ltx2.3 support", PR #1463). `docs/ltx2.md` pairs LTX-2.3 with gemma-3-12b-it and LTX-2.5 with a Gemma 4 text encoder; `CONTRIBUTING.md` calls the embedded table "Gemma 3/4". | **license not verified.** See below. | see below |

Gemma: which Gemma release the embedded tables were taken from is not stated anywhere in stable-diffusion.cpp, and the two candidates have different terms.

- https://huggingface.co/google/gemma-3-12b-it is a gated repository. Its model card and files could not be read without accepting Google's terms; the repository metadata from the Hugging Face API reports `license: gemma`, which is Google's Gemma Terms of Use, a custom licence with use restrictions and not an open-source licence.
- https://huggingface.co/google/gemma-4-12B-it is not gated and its model card states `license: apache-2.0` (with `license_link: https://ai.google.dev/gemma/docs/gemma_4_license`).

The commit that added the tables was for LTX-2.3, which uses Gemma 3, so the Gemma Terms of Use may apply to this data. This was not resolved: the data files were not compared against either upstream tokenizer. Until it is, treat the Gemma tables as third-party data under terms that have not been established. Kiln's curated recipes do not use the Gemma tokenizer, but the tables are still present in the helper binary.

## Notices that must ship with a release build

The MIT, BSD and Apache-2.0 licences above all require their copyright notice and licence text to accompany binary distributions, and the helper is distributed inside the app. A release build must therefore carry, somewhere a user can read them (in the app bundle's resources, and ideally reachable from the About screen), the full text of:

- **MIT**, with each of these copyright lines: stable-diffusion.cpp (leejet); ggml and the function copied from llama.cpp (The ggml authors); JSON for Modern C++ (Niels Lohmann); utf8proc (its contributors and Public Software Group e. V.); YaRN (Jeffrey Quesnelle and Bowen Peng); Stability AI (sd3.5 constants); OpenAI (CLIP merge table); the MIT-style notice inside miniz (RAD Game Tools and Valve Software; Rich Geldreich and Tenacious Software LLC); and upstream zip's `LICENSE.txt`.
- **BSD 2-Clause** for Oniguruma (`thirdparty/oniguruma/COPYING`).
- **BSD 3-Clause** for Darts-clone (`thirdparty/LICENSE.darts_clone.txt`) and for the code ported from PyTorch (the PyTorch `LICENSE`, including its list of copyright holders).
- **Unicode data license** for the utf8proc data tables (second half of `thirdparty/utf8proc/LICENSE.md`).
- **Apache License 2.0**, once, covering the code ported from SentencePiece and the T5, UMT5, Qwen and Mistral tokenizer tables. Apache-2.0 also asks that modified files be marked as changed; the SentencePiece-derived file identifies itself as a port in its source comment.

The Unlicense components (miniz, and zip as vendored) have no notice requirement.

`project.yml` copies `LICENSE` and this file into the app bundle. This file names each licence and copyright holder but does not reproduce the licence texts, so on its own it does not meet the "include this permission notice" condition of the MIT and BSD licences or section 4(a) of Apache-2.0. The licence texts listed above need to be added to the bundle before a signed build is distributed. The Gemma tokenizer question above should be settled before then as well.

## Vendored but not compiled into the helper

These are present in the submodule tree or referenced by it, but are not part of the Metal build Kiln ships, so their licenses do not apply to the helper binary:

| Component | Why it is excluded |
| --- | --- |
| cpp-httplib (`thirdparty/httplib.h`) | Not included by any library source; the examples are not built (`SD_BUILD_EXAMPLES=OFF`). |
| stb (`thirdparty/stb_image.h`, `stb_image_resize.h`, `stb_image_write.h`) | Not included by any library source. |
| libwebp (`thirdparty/libwebp`) | `SD_WEBP=OFF`. |
| libwebm (`thirdparty/libwebm`) | `SD_WEBM=OFF`. |
| CUTLASS (`thirdparty/cutlass`) and the CUDA sources under `src/core/cuda/` | CUDA only. |
| ggml's `llamafile` and KleidiAI CPU kernels | `GGML_LLAMAFILE` and `GGML_CPU_KLEIDIAI` default to off in `ggml/CMakeLists.txt` and nothing in this build turns them on. |
| The sdcpp-webui frontend (`examples/server/frontend`) | Part of the server example, which is not built. |

If the build options in `Engine/CMakeLists.txt` change, or the submodule is updated, this file must be re-checked.

## Model weights

Kiln does not bundle or distribute model weights. Models are downloaded by the user from Hugging Face and each carries its own license, which the user is responsible for complying with. For the curated recipes:

- Qwen-Image 2.1 Turbo: the denoiser and VAE are under the Qwen Research License (non-commercial).
- Stable Diffusion XL Base 1.0: CreativeML Open RAIL++-M License.

Each recipe's `license_note` field summarizes the terms, but the model's page on Hugging Face is authoritative.
