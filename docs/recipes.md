# Recipe reference

A recipe is a JSON file that describes one runnable model: every file it needs from Hugging Face and the settings that make it work. The schema is defined in [`Sources/KilnCore/Recipes/ModelRecipe.swift`](../Sources/KilnCore/Recipes/ModelRecipe.swift).

Kiln loads recipes from two places:

- curated recipes in [`recipes/`](../recipes), bundled into the app
- recipes you imported, stored in `~/Library/Application Support/Kiln/recipes/`

## Top-level fields

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `id` | string | yes | Unique identifier. Also the file name (`<id>.json`). |
| `name` | string | yes | Display name. |
| `engine` | string | yes | Inference engine. The only engine Kiln includes is `sd.cpp`. |
| `components` | array of [component](#components) | yes | Files to download. At least one. |
| `defaults` | [defaults](#defaults) object | yes | Recommended generation settings. |
| `license_note` | string | no | Short, human-readable summary of the model's license terms. |
| `min_memory_gb` | number | no | Smallest amount of system RAM the recipe is expected to run on. |

A recipe with an `engine` other than `sd.cpp` still loads, but generating with it fails with an "unsupported engine" error.

## Components

Each entry in `components` is one file in a Hugging Face repo.

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `role` | string | yes | What the file is used for. See [roles](#roles). |
| `repo` | string | yes | Hugging Face repo id, `owner/name`. |
| `file` | string | yes | Path of the file inside the repo. May contain subfolders, for example `vae/model.safetensors`. |
| `revision` | string | no | Commit to download from. Falls back to `main` when absent. |
| `size_bytes` | integer | no | Exact file size in bytes. |
| `sha256` | string | no | SHA-256 of the file, 64 hexadecimal characters. |

`revision`, `size_bytes` and `sha256` are optional in the schema but required for curated recipes (see [curated recipes](#extra-rules-for-curated-recipes)). What they do when present:

- `revision` pins the download URL: `https://huggingface.co/<repo>/resolve/<revision>/<file>`.
- `size_bytes` is compared against the downloaded file, feeds the disk-space check and progress totals, and is the input to the [memory-fit estimate](#memory-fit).
- `sha256` is compared against the downloaded file (case-insensitive).

A file without `size_bytes` or `sha256` is installed without that check.

The file is stored at `~/Library/Application Support/Kiln/models/<owner>/<repo>/<file>`. Two recipes that list the same repo and file share one copy on disk.

### Roles

Each role may appear at most once per recipe. Any other value is rejected when the file is decoded.

| `role` | Meaning | Key in the helper's `model` object | stable-diffusion.cpp context parameter |
| --- | --- | --- | --- |
| `checkpoint` | A single-file checkpoint that carries everything (SD 1.x, SDXL) | `checkpoint` | `model_path` |
| `diffusion_model` | A standalone denoiser | `diffusion_model` | `diffusion_model_path` |
| `llm` | A language-model text encoder | `llm` | `llm_path` |
| `vae` | A standalone VAE | `vae` | `vae_path` |

Roles a recipe does not use are left unset. The mapping lives in [`EngineProtocol.swift`](../Sources/KilnCore/Engine/EngineProtocol.swift) and `load_model` in [`Engine/main.cpp`](../Engine/main.cpp).

## Defaults

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `steps` | integer | yes | Sampling steps. |
| `cfg` | number | yes | Classifier-free guidance scale. |
| `sampler` | string | yes | Sampling method name as stable-diffusion.cpp spells it, for example `euler`. |
| `width` | integer | yes | Image width in pixels. |
| `height` | integer | yes | Image height in pixels. |
| `sigmas` | array of numbers | no | Explicit noise schedule. Must contain exactly `steps + 1` values. |
| `flash_attention` | boolean | no | Enables flash attention for the diffusion model when the model is loaded. Treated as `false` when absent. |

Notes:

- The sampler name is not checked when the recipe is loaded. An unknown name fails at generation time with an "Unknown sampler" error from the helper. Names accepted by the vendored stable-diffusion.cpp are: `euler`, `euler_a`, `heun`, `dpm2`, `dpm++2s_a`, `dpm++2m`, `dpm++2mv2`, `ipndm`, `ipndm_v`, `lcm`, `ddim_trailing`, `tcd`, `res_multistep`, `res_2s`, `er_sde`, `euler_cfg_pp`, `euler_a_cfg_pp`, `euler_ge`, `dpm++2m_sde`, `dpm++2m_sde_bt`, `lms`.
- A recipe cannot choose a scheduler. The helper uses stable-diffusion.cpp's default scheduler for the loaded model and sampler. When `sigmas` is present it is passed as the custom sigma schedule.
- `flash_attention` is a model-load setting, not a per-image one. It comes from the recipe and is sent in the helper's `model` object.

## Validation rules

A recipe is decoded and then validated. A file that fails either step is not loaded. These are all the rules in `ModelRecipe.validate()`:

Recipe:

1. `id` is not empty, contains only lowercase letters `a-z`, digits, `.`, `-` and `_`, and does not start with `.`.
2. `name` is not empty or whitespace only.
3. `components` has at least one entry.
4. No two components share a `role`.

Each component:

5. `repo` is exactly two non-empty parts separated by one `/`, and neither part is `.` or `..`.
6. `file` is not empty, contains no backslash, and no path segment is empty, `.` or `..`. This rules out absolute paths, `//` and anything that would escape the model folder.
7. `sha256`, when present, is exactly 64 hexadecimal characters.
8. `size_bytes`, when present, is greater than zero.

Defaults:

9. `steps` is greater than zero.
10. `cfg` is not negative.
11. `sampler` is not empty.
12. `width` and `height` are greater than zero.
13. `sigmas`, when present, has exactly `steps + 1` values.

Decoding adds the structural checks: every required field must be present with the right type, and `role` must be one of the four values above. Unknown extra fields are ignored.

When recipes are loaded, a recipe whose `id` was already seen is skipped as a duplicate. Bundled recipes are read first, so a bundled recipe wins over an imported one with the same id.

### Extra rules for curated recipes

The test `everyCuratedRecipeIsValid` in [`ModelRecipeTests.swift`](../Tests/KilnCoreTests/ModelRecipeTests.swift) applies these to every file in `recipes/`:

- the file name without `.json` equals the recipe `id`
- `engine` is `sd.cpp`
- every component has `revision`, `size_bytes` and `sha256`

Get those three values from the Hub API:

```sh
curl -s "https://huggingface.co/api/models/<owner>/<repo>?blobs=true"
```

`sha` is the revision. In `siblings`, the entry whose `rfilename` is your file has `size` and `lfs.sha256`.

## Annotated example

This is [`recipes/qwen-image-2.1-turbo.json`](../recipes/qwen-image-2.1-turbo.json). JSON has no comments, so the notes follow the listing.

```json
{
  "id": "qwen-image-2.1-turbo",
  "name": "Qwen-Image 2.1 Turbo",
  "engine": "sd.cpp",
  "components": [
    {
      "role": "llm",
      "repo": "AtomicChat/Qwen-Image-2.1-Turbo-Uncensored-GGUF",
      "file": "Qwen-Image-2.1-Turbo-Uncensored-Q8_0.gguf",
      "revision": "881a778e306c44920e42536def3e52c3a3ecc7cd",
      "size_bytes": 8709520096,
      "sha256": "f8f9f6276b726db5291f4a5343089612cb5fd08aa81e8f0791dc66d2c03d07ca"
    },
    {
      "role": "diffusion_model",
      "repo": "AtomicChat/Qwen-Image-2.1-Turbo-GGUF",
      "file": "Qwen-Image-2.1-Turbo-Q8_0.gguf",
      "revision": "cbcb9ff83b17e1eeef693479a8d34cea355a0ee4",
      "size_bytes": 7591577312,
      "sha256": "8d74ae0be534df394ea2d29f04b77f879318c9e0df20a3e208e6bedbf89b4159"
    },
    {
      "role": "vae",
      "repo": "Comfy-Org/Qwen-Image-2.1",
      "file": "vae/qwen_image_2.1_vae_bf16.safetensors",
      "revision": "aacf31a6d48e707f352ecba714cee0680da3479b",
      "size_bytes": 675509688,
      "sha256": "bb21f7473051e1ac368515dd3f2e15cd44d7a11748ee8823e1ddca3e4876b7c9"
    }
  ],
  "defaults": {
    "steps": 8,
    "cfg": 1.0,
    "sampler": "euler",
    "width": 1024,
    "height": 1024,
    "sigmas": [1.0, 0.978453, 0.95418, 0.926626, 0.89508, 0.845148, 0.704534, 0.414568, 0.0],
    "flash_attention": true
  },
  "license_note": "Denoiser and VAE: Qwen Research License (non-commercial; see the base model repo). Text encoder: Apache-2.0.",
  "min_memory_gb": 24
}
```

- `id` matches the file name, `qwen-image-2.1-turbo.json`.
- The model is split across three files in three repos, so it uses three roles: `llm` (text encoder), `diffusion_model` (denoiser) and `vae`. There is no `checkpoint`.
- Each component is pinned to a commit, a byte size and a SHA-256, so the download is reproducible and verified.
- The VAE's `file` includes a subfolder. It is stored at `models/Comfy-Org/Qwen-Image-2.1/vae/qwen_image_2.1_vae_bf16.safetensors`.
- `steps` is 8 and `sigmas` has 9 values, satisfying the `steps + 1` rule.
- `flash_attention` is on for this model.
- `license_note` lists the license per component because they differ.
- `min_memory_gb` is 24: on a Mac with less RAM the recipe is reported as too large regardless of file sizes.

## Memory fit

Kiln estimates whether a recipe fits in the Mac's unified memory. The logic is `MemoryFitEstimator` in [`MemoryFit.swift`](../Sources/KilnCore/Recipes/MemoryFit.swift). It is a heuristic on file sizes only and ignores the working memory that grows with image resolution, so "comfortable" is not a guarantee.

Inputs:

- `RAM`: physical memory of the Mac. 1 GB here means 1,073,741,824 bytes.
- `size`: the sum of `size_bytes` over all components. It is unknown if any component has no `size_bytes`.
- `min_memory_gb` from the recipe, if present.

Usable memory reserves a fixed 2.5 GB for macOS plus 10% of RAM:

```
usable = max(0, RAM - 2.5 GB - 0.10 * RAM)
```

The result is decided in this order:

1. If `min_memory_gb` is set and `RAM < min_memory_gb`: **too large**.
2. If `size` is unknown: **comfortable** when `min_memory_gb` is set (and was met), otherwise no estimate.
3. If `size > usable`: **too large**.
4. If `size <= 0.85 * usable`: **comfortable**.
5. Otherwise: **tight**.

Worked example with the recipe above, whose files total 16,976,607,096 bytes (about 15.8 GB):

| Mac RAM | Usable | Result | Why |
| --- | --- | --- | --- |
| 16 GB | 11.9 GB | too large | below `min_memory_gb` (24) |
| 24 GB | 19.1 GB | comfortable | 15.8 GB is under 85% of usable (16.2 GB) |
| 32 GB | 26.3 GB | comfortable | 15.8 GB is under 85% of usable (22.4 GB) |

The estimate is advisory. If the helper runs out of memory during generation, Kiln reports that as an out-of-memory error.

## Importing a recipe in the app

1. Open the Models screen.
2. Choose "Import Recipe" and select your `.json` file.

Kiln decodes and validates the file with the rules above. If it is valid, it is copied to `~/Library/Application Support/Kiln/recipes/<id>.json`, named after the recipe's `id` whatever the original file was called. Importing a recipe with the same id as one you imported earlier replaces it.

Import fails when:

- the file is not valid JSON, a required field is missing or a value has the wrong type
- a validation rule is violated
- the `id` is already used by a built-in recipe

Imported recipes do not need `revision`, `size_bytes` or `sha256`, but leaving them out means the download is taken from `main` and is not verified, there is no disk-space check for that file, and there is no size-based memory estimate.
