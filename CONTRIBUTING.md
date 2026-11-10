# Contributing to Kiln

The most useful contribution is a model recipe: a JSON manifest that makes a model a one-click download with settings that work. This guide covers that first, then code contributions.

## Contributing a recipe

The full field reference is in [docs/recipes.md](docs/recipes.md). The steps below are the short version.

### 1. Pick the files

Find the model on Hugging Face and decide which files it needs. Each file gets one role, and a role can appear only once per recipe:

| Role | Use it for |
| --- | --- |
| `checkpoint` | A single file that carries everything (SD 1.x, SDXL) |
| `diffusion_model` | A standalone denoiser |
| `llm` | A language-model text encoder |
| `vae` | A standalone VAE |

Files may come from different repos. Prefer `.gguf` or `.safetensors`.

### 2. Get the revision, size and SHA-256

Curated recipes must pin every file. Query the Hub API for each repo:

```sh
curl -s "https://huggingface.co/api/models/<owner>/<repo>?blobs=true"
```

From the response, take:

- `sha`: the commit, used as `revision`
- for your file in `siblings` (matched by `rfilename`): `size` for `size_bytes` and `lfs.sha256` for `sha256`

With `jq`, for example:

```sh
curl -s "https://huggingface.co/api/models/<owner>/<repo>?blobs=true" \
  | jq '{revision: .sha, files: [.siblings[] | {file: .rfilename, size_bytes: .size, sha256: .lfs.sha256}]}'
```

### 3. Write the JSON

Use an existing recipe as a template, for example [recipes/sdxl-base-1.0.json](recipes/sdxl-base-1.0.json):

```json
{
  "id": "sdxl-base-1.0",
  "name": "Stable Diffusion XL Base 1.0",
  "engine": "sd.cpp",
  "components": [
    {
      "role": "checkpoint",
      "repo": "stabilityai/stable-diffusion-xl-base-1.0",
      "file": "sd_xl_base_1.0.safetensors",
      "revision": "462165984030d82259a11f4367a4eed129e94a7b",
      "size_bytes": 6938078334,
      "sha256": "31e35c80fc4829d14f90153f4c74cd59c90b779f6afe05a74cd6120b893f7e5b"
    }
  ],
  "defaults": {
    "steps": 30,
    "cfg": 7.0,
    "sampler": "euler",
    "width": 1024,
    "height": 1024
  },
  "license_note": "CreativeML Open RAIL++-M License.",
  "min_memory_gb": 16
}
```

Take `defaults` from the model card, not from memory. Set `engine` to `sd.cpp`.

### 4. Name the file `<id>.json`

Save it as `recipes/<id>.json`. The file name must equal the recipe `id`. Ids use only lowercase letters, digits, dots, dashes and underscores, and cannot start with a dot.

### 5. Run the tests

```sh
swift test
```

`everyCuratedRecipeIsValid` decodes and validates every file in `recipes/` and fails if a file name does not match its id, if `engine` is not `sd.cpp`, or if any component is missing `revision`, `size_bytes` or `sha256`.

### 6. Open a pull request

In the description, link the model card (or other primary source) your settings come from, and say which Mac you tried the recipe on, if any. If you could not run it, say so.

### What reviewers check

- **Settings come from the model card.** Steps, CFG, sampler, resolution and any custom sigmas match what the model authors recommend, and the PR links the source.
- **`license_note` is accurate.** It names the actual license of each component and calls out restrictions such as non-commercial use. When components have different licenses, list each one.
- **`min_memory_gb` is honest.** It is the smallest amount of system RAM the recipe is expected to run on, not the smallest that looks good in a table. If you have not tested at that size, pick a conservative value and say so in the PR.
- **Files are pinned and correct.** `revision`, `size_bytes` and `sha256` match the Hub API output for the repo and file listed.
- **Roles are right.** Each file is assigned the role the engine needs it in.

## Contributing code

- `swift test` must pass.
- The package builds in Swift 6 language mode with strict concurrency checking. Do not silence concurrency diagnostics without a comment explaining why the code is safe.
- Keep `KilnCore` UI-free. It must not import SwiftUI or AppKit; views and app state belong in `App/`.
- New behavior in `KilnCore` needs tests. Network and process boundaries are behind protocols (`HTTPTransport`, `FileDownloading`, `TokenStore`, `InferenceEngine`) so they can be tested without the network or real weights.
- Changes to the helper protocol must update both `Engine/main.cpp` and `Sources/KilnCore/Engine/EngineProtocol.swift`, and [docs/architecture.md](docs/architecture.md).
- Do not edit `Vendor/stable-diffusion.cpp`; it is a git submodule.

Build instructions are in the [README](README.md#build).
