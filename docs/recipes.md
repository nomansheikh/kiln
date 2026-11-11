# Recipe reference

A recipe is a JSON file that describes one runnable model: every file it needs from Hugging Face and the settings that make it work. The format is defined in [`Sources/KilnCore/Recipes/`](../Sources/KilnCore/Recipes) and described for editors by [`recipes/schema.json`](../recipes/schema.json).

Kiln loads recipes from these places:

- curated recipes in [`recipes/`](../recipes), bundled into the app and [updated from this repository](#how-a-merged-recipe-reaches-users)
- user recipes in `~/Library/Application Support/Kiln/recipes/`: the ones you imported, and the [single-file recipes](#single-file-recipes) Kiln writes when you download one file from the Hugging Face list

Contents: [quick start](#quick-start-with-the-script) · [fields](#top-level-fields) · [components and roles](#components) · [defaults](#defaults) · [variants](#variants) · [validation](#validation-rules) · [the script](#the-recipe-script) · [the schema](#the-schema) · [the index](#the-index) · [remote updates](#how-a-merged-recipe-reaches-users) · [manual method](#writing-a-recipe-by-hand) · [memory fit](#memory-fit) · [importing](#importing-a-recipe-in-the-app) · [single-file recipes](#single-file-recipes)

## Quick start with the script

[`scripts/recipe.py`](../scripts/recipe.py) creates and checks recipes. It needs only the `python3` that comes with Xcode's command line tools, and it asks the Hugging Face API for file metadata; it never downloads model files.

```sh
# 1. Create recipes/<id>.json. The script looks up revision, size and SHA-256.
python3 scripts/recipe.py new \
  --id sdxl-base-1.0 \
  --name "Stable Diffusion XL Base 1.0" \
  --component checkpoint=stabilityai/stable-diffusion-xl-base-1.0:sd_xl_base_1.0.safetensors \
  --steps 30 --cfg 7.0 --sampler euler --width 1024 --height 1024 \
  --license-note "CreativeML Open RAIL++-M License." \
  --min-memory-gb 16

# 2. Validate every recipe and verify every file against Hugging Face.
python3 scripts/recipe.py check

# 3. Run the tests.
swift test
```

That command produces exactly [`recipes/sdxl-base-1.0.json`](../recipes/sdxl-base-1.0.json). Details are under [the recipe script](#the-recipe-script).

## Top-level fields

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `$schema` | string | no | `"./schema.json"`, so editors validate and autocomplete the file. The app ignores it. |
| `id` | string | yes | Unique identifier. Also the file name (`<id>.json`). |
| `name` | string | yes | Display name. |
| `engine` | string | yes | Inference engine. The only engine Kiln includes is `sd.cpp`. |
| `components` | array of [component](#components) | yes | Files to download. At least one, unless the recipe has [variants](#variants), in which case these are the files shared by every variant and the array may be empty. The key must be present either way. |
| `defaults` | [defaults](#defaults) object | yes | Recommended generation settings. |
| `license_note` | string | no | Short, human-readable summary of the model's licence terms. |
| `min_memory_gb` | number | no | Smallest amount of system RAM the recipe is expected to run on. |
| `base_model` | string | no | Hugging Face repo of the original model the `diffusion_model` file was made from, for example `black-forest-labs/FLUX.1-dev`. Lets files from other repos of the same model run with this recipe. See [family recipes](#family-recipes). |
| `variants` | array of [variant](#variants) | no | Alternative sets of files for the same model, usually different quantizations. |

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

`revision`, `size_bytes` and `sha256` are optional for the app but required for curated recipes (see [curated recipes](#extra-rules-for-curated-recipes)). The script fills them in. What they do when present:

- `revision` pins the download URL: `https://huggingface.co/<repo>/resolve/<revision>/<file>`.
- `size_bytes` is compared against the downloaded file, feeds the disk-space check and progress totals, and is the input to the [memory-fit estimate](#memory-fit).
- `sha256` is compared against the downloaded file (case-insensitive).

A file without `size_bytes` or `sha256` is installed without that check.

The file is stored at `~/Library/Application Support/Kiln/models/<owner>/<repo>/<file>`. Two recipes that list the same repo and file share one copy on disk.

### Roles

Each role may appear at most once in a list of components. Any other value is rejected when the file is decoded.

| `role` | Meaning | Key in the helper's `model` object | stable-diffusion.cpp context parameter |
| --- | --- | --- | --- |
| `checkpoint` | A single-file checkpoint that carries everything (SD 1.x, SDXL) | `checkpoint` | `model_path` |
| `diffusion_model` | A standalone denoiser | `diffusion_model` | `diffusion_model_path` |
| `llm` | A language model used as the text encoder (Qwen-Image and similar) | `llm` | `llm_path` |
| `vae` | A standalone VAE | `vae` | `vae_path` |
| `clip_l` | CLIP-L text encoder (Flux and SD3 families) | `clip_l` | `clip_l_path` |
| `clip_g` | CLIP-G text encoder (SD3 family) | `clip_g` | `clip_g_path` |
| `t5xxl` | T5-XXL text encoder (Flux and SD3 families) | `t5xxl` | `t5xxl_path` |

Roles a recipe does not use are left unset. There is no role for a LoRA or a vision projector, so a model that needs one of those cannot be described yet. The mapping lives in `generateCommand` in [`EngineProtocol.swift`](../Sources/KilnCore/Engine/EngineProtocol.swift) and `load_model` in [`Engine/main.cpp`](../Engine/main.cpp).

To decide which roles a model needs, read its page under [`Vendor/stable-diffusion.cpp/docs/`](https://github.com/leejet/stable-diffusion.cpp/tree/master/docs) (for example `flux.md`, `sd3.md`, `qwen_image.md`). The command lines there use the flags `-m`, `--diffusion-model`, `--llm`, `--vae`, `--clip_l`, `--clip_g` and `--t5xxl`, which correspond to the seven roles in the order of the table.

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
| `scheduler` | string | no | Noise scheduler name as stable-diffusion.cpp spells it, for example `simple`. The engine's default for the model and sampler when absent. |
| `guidance` | number | no | Distilled guidance, used by guidance-distilled models such as Flux. The engine's default when absent. |
| `flow_shift` | number | no | Flow shift for flow-matching models. The model's own default when absent. |

How each one reaches the engine:

| Field | Sent as | stable-diffusion.cpp field |
| --- | --- | --- |
| `steps` | `params.steps` | `sample_params.sample_steps` |
| `cfg` | `params.cfg` | `sample_params.guidance.txt_cfg` |
| `sampler` | `params.sampler` | `sample_params.sample_method` |
| `width`, `height` | `params.width`, `params.height` | `width`, `height` |
| `sigmas` | `params.sigmas` | `sample_params.custom_sigmas` |
| `scheduler` | `params.scheduler` | `sample_params.scheduler` |
| `guidance` | `params.guidance` | `sample_params.guidance.distilled_guidance` |
| `flow_shift` | `params.flow_shift` | `sample_params.flow_shift` |
| `flash_attention` | `model.flash_attention` | `diffusion_flash_attn` (context parameter) |

Notes:

- Selecting a model on the Generate screen copies `width`, `height`, `steps`, `cfg` and `sampler` into the composer, where the user can change them. "Reset to recommended" in the advanced settings applies them again.
- `scheduler`, `guidance`, `flow_shift` and `flash_attention` belong to the model, not to one prompt. They are always taken from the recipe and cannot be changed in the app.
- Sampler and scheduler names are not checked when the app loads a recipe. An unknown name fails at generation time with an "Unknown sampler" or "Unknown scheduler" error from the helper. `scripts/recipe.py` does check them, against the lists in the vendored stable-diffusion.cpp.
- Sampler names: `euler`, `euler_a`, `heun`, `dpm2`, `dpm++2s_a`, `dpm++2m`, `dpm++2mv2`, `ipndm`, `ipndm_v`, `lcm`, `ddim_trailing`, `tcd`, `res_multistep`, `res_2s`, `er_sde`, `euler_cfg_pp`, `euler_a_cfg_pp`, `euler_ge`, `dpm++2m_sde`, `dpm++2m_sde_bt`, `lms`. The sampler menu in the app's advanced settings offers the first twelve of these (`euler` to `tcd`), plus the recipe's own sampler when it is not one of them.
- Scheduler names: `discrete`, `karras`, `exponential`, `ays`, `gits`, `sgm_uniform`, `simple`, `smoothstep`, `kl_optimal`, `lcm`, `bong_tangent`, `ltx2`, `logit_normal`, `flux2`, `flux`, `beta`, `llada_image`. The engine also reads `normal` as `discrete`.
- Both lists come from `sample_method_to_str` and `scheduler_to_str` in `Vendor/stable-diffusion.cpp/src/stable-diffusion.cpp`. If the submodule is updated, that file is the authority.
- When `sigmas` is present it is passed as the custom sigma schedule, but only while the step count is the recipe's own `steps`. If the user changes the step count, the app leaves `sigmas` out and the scheduler decides.
- A recipe has no fields for a negative prompt, a seed or an image-to-image strength. Those are chosen in the app.

## Variants

Many models are published in several quantizations: the same model as larger, more faithful files or smaller, lighter ones. A recipe describes these as `variants` instead of as separate recipes.

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `id` | string | yes | Identifier, unique within the recipe, for example `q8`. Same character rules as the recipe `id`. |
| `name` | string | yes | Shown in the app, for example `Q8 (best quality)`. |
| `components` | array of [component](#components) | yes | Files for this variant. At least one. |
| `min_memory_gb` | number | no | Smallest amount of system RAM this variant is expected to run on. Falls back to the recipe's `min_memory_gb`. |

How a variant becomes a set of files:

- The recipe's top-level `components` are shared by every variant.
- A variant's components are merged over them. A variant component with the same `role` as a shared one replaces it; the others are added.
- The result must be a complete model, and every variant must be complete on its own terms: the app never mixes files from two variants.
- With variants, the shared `components` may be empty (`"components": []`), with every file listed in the variants.

Which variant the app offers: the largest one that fits comfortably in this Mac's memory, since larger usually means higher quality. If none fits comfortably, the largest that is a tight fit; if none fits at all, the smallest. "Fits" is the [memory-fit estimate](#memory-fit) applied to the variant's merged files and its `min_memory_gb`. The user can switch to another variant.

Use variants when the alternatives are the same model with the same settings. `defaults` are shared by all variants, so a model that needs different steps, sampler or sigmas (a turbo or distilled version, for example) is a separate recipe.

### Worked example

This is [`recipes/qwen-image-2.1-turbo.json`](../recipes/qwen-image-2.1-turbo.json). JSON has no comments, so the notes follow the listing.

```json
{
  "$schema": "./schema.json",
  "id": "qwen-image-2.1-turbo",
  "name": "Qwen-Image 2.1 Turbo",
  "engine": "sd.cpp",
  "components": [
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
  "variants": [
    {
      "id": "q8",
      "name": "Q8 (best quality)",
      "min_memory_gb": 24,
      "components": [
        {
          "role": "llm",
          "repo": "Qwen/Qwen3-VL-8B-Instruct-GGUF",
          "file": "Qwen3VL-8B-Instruct-Q8_0.gguf",
          "revision": "f982a07559d4a2f6c8744d840bf6fccab30eea96",
          "size_bytes": 8709519456,
          "sha256": "0d264b3941185d00a74f75c4245521dae088ff1efc90ab8d1754e83f5844adb0"
        },
        {
          "role": "diffusion_model",
          "repo": "AtomicChat/Qwen-Image-2.1-Turbo-GGUF",
          "file": "Qwen-Image-2.1-Turbo-Q8_0.gguf",
          "revision": "cbcb9ff83b17e1eeef693479a8d34cea355a0ee4",
          "size_bytes": 7591577312,
          "sha256": "8d74ae0be534df394ea2d29f04b77f879318c9e0df20a3e208e6bedbf89b4159"
        }
      ]
    },
    {
      "id": "q4",
      "name": "Q4 (smaller)",
      "min_memory_gb": 16,
      "components": [
        {
          "role": "llm",
          "repo": "Qwen/Qwen3-VL-8B-Instruct-GGUF",
          "file": "Qwen3VL-8B-Instruct-Q4_K_M.gguf",
          "revision": "f982a07559d4a2f6c8744d840bf6fccab30eea96",
          "size_bytes": 5027784800,
          "sha256": "67d1659bfe71b89d50b45a4ad1a9e5b997e5bb16ce5da66a6a6167abd569e9e2"
        },
        {
          "role": "diffusion_model",
          "repo": "AtomicChat/Qwen-Image-2.1-Turbo-GGUF",
          "file": "Qwen-Image-2.1-Turbo-AD-Q4_K.gguf",
          "revision": "cbcb9ff83b17e1eeef693479a8d34cea355a0ee4",
          "size_bytes": 4201694944,
          "sha256": "4bb73c53cbe284bbd6d69b9fdc59539c531f0389dd2aa567663d777f8130bc59"
        }
      ]
    }
  ]
}
```

- `id` matches the file name, `qwen-image-2.1-turbo.json`.
- The model is split across three files in three repos, so each install has three roles: `llm` (text encoder), `diffusion_model` (denoiser) and `vae`. There is no `checkpoint`.
- The VAE is the same for both variants, so it is the one shared component. Each variant adds its own `llm` and `diffusion_model`. Installing `q8` downloads three files totalling 16,976,606,456 bytes; `q4` downloads three totalling 9,904,989,432 bytes.
- Every file is pinned to a commit, a byte size and a SHA-256, so the download is reproducible and verified.
- The VAE's `file` includes a subfolder. It is stored at `models/Comfy-Org/Qwen-Image-2.1/vae/qwen_image_2.1_vae_bf16.safetensors`.
- `steps` is 8 and `sigmas` has 9 values, satisfying the `steps + 1` rule. (The file itself has one sigma per line; that is how the script prints arrays.)
- `flash_attention` is on for this model.
- `license_note` lists the licence per component because they differ.
- `min_memory_gb` is set per variant: 24 for `q8`, 16 for `q4`. The recipe has no top-level value.

The command that generates this file is example 2 in `python3 scripts/recipe.py new --help`.

## Validation rules

A recipe is decoded and then validated. A file that fails either step is not loaded. These are all the rules in `ModelRecipe.validate()` ([`ModelRecipe+Validation.swift`](../Sources/KilnCore/Recipes/ModelRecipe+Validation.swift)):

Recipe:

1. `id` is not empty, contains only lowercase letters `a-z`, digits, `.`, `-` and `_`, and does not start with `.`.
2. `name` is not empty and does not consist only of spaces and tabs.
3. `components` has at least one entry, unless the recipe has at least one variant.
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

Each variant:

14. `id` follows rule 1 and is unique within the recipe; `name` follows rule 2.
15. `components` has at least one entry, no two share a `role`, and each follows rules 5 to 8.
16. The merged list (shared components with this variant's files replacing those of the same role) has no duplicate role.

Decoding adds the structural checks: every required field must be present with the right type, and `role` must be one of the seven values above. Unknown extra fields are ignored by the app, which is why `$schema` is safe, and also why a misspelt optional field goes unnoticed; `scripts/recipe.py check` reports unknown fields for that reason.

`index.json` and `schema.json` are reserved file names. The app does not load them as recipes.

When recipes are loaded, a recipe whose `id` was already seen is skipped as a duplicate. Bundled recipes are read before user recipes, so a curated recipe wins over a user recipe with the same id. Within a folder, files are read in file-name order.

Files that fail to decode or validate, and skipped duplicates, do not stop the others from loading. The Models screen lists them in a "recipes could not be loaded" card with the file name and the reason.

### Extra rules for curated recipes

Two things check every file in `recipes/` on each push: the test `everyCuratedRecipeIsValid` in [`ModelRecipeTests.swift`](../Tests/KilnCoreTests/ModelRecipeTests.swift), and `python3 scripts/recipe.py check` in CI.

The test requires:

- the file name without `.json` equals the recipe `id`
- `engine` is `sd.cpp`
- every component of every variant (or of the recipe, when it has no variants) has `revision`, `size_bytes` and `sha256`
- `recipes/index.json` lists exactly the recipe files

The script requires all of that, and also:

- `revision` is a full 40-character commit sha, not a branch name
- the file exists on Hugging Face at that revision, with that size and that SHA-256
- `sampler` and `scheduler` are names the vendored stable-diffusion.cpp accepts
- `base_model`, when set, is the model the Hub tags every `diffusion_model` repo of the recipe as made from (or is that repo itself), and the recipe has a `diffusion_model` component
- there are no unknown fields

## The recipe script

```sh
python3 scripts/recipe.py new --help
python3 scripts/recipe.py check --help
python3 scripts/recipe.py index --help
```

It uses the Python standard library only. The only network requests go to `https://huggingface.co/api/models/...`, which returns metadata; no model file is downloaded. If the environment variable `HF_TOKEN` is set, it is sent as a bearer token so private and gated repos can be read. It is sent only to `huggingface.co`; a redirect to any other host is refused.

### `new`

Creates `recipes/<id>.json` from command-line arguments.

Each file is written as `ROLE=OWNER/REPO:PATH`, where `PATH` is the file's path inside the repo. The script records the repo's current commit as `revision`, and the file's `size_bytes` and `sha256` as the Hub reports them. To pin a specific commit or branch instead of the current default branch, write `ROLE=OWNER/REPO@REVISION:PATH`; the commit it resolves to is what gets recorded.

| Argument | Meaning |
| --- | --- |
| `--id ID` | Recipe id and file name. Required. |
| `--name NAME` | Display name. Required. |
| `--component ROLE=OWNER/REPO:PATH` | A file every install needs. Repeat for each file. |
| `--variant ID "NAME" [min_memory_gb=N] ROLE=OWNER/REPO:PATH ...` | One variant: its id, its name, optionally its minimum memory, then its files. Repeat for each variant. |
| `--steps`, `--cfg`, `--sampler`, `--width`, `--height` | The required defaults. There are no built-in values: take them from the model card. |
| `--sigmas N,N,...` | Custom sigma schedule, `steps + 1` numbers separated by commas or spaces. |
| `--flash-attention` | Sets `flash_attention` to `true`. |
| `--scheduler NAME`, `--guidance N`, `--flow-shift N` | The optional defaults of the same names. |
| `--license-note TEXT` | `license_note`. |
| `--min-memory-gb GB` | Recipe-level `min_memory_gb`. |
| `--base-model OWNER/REPO` | `base_model`. The script refuses a value the `diffusion_model` repo's own tags do not state. |
| `--force` | Replace an existing file. Without it the script refuses to overwrite. |
| `--directory DIR` | Write somewhere other than `recipes/`. |

Give at least one `--component` or `--variant`. A recipe with variants looks like this:

```sh
python3 scripts/recipe.py new \
  --id qwen-image-2.1-turbo \
  --name "Qwen-Image 2.1 Turbo" \
  --component vae=Comfy-Org/Qwen-Image-2.1:vae/qwen_image_2.1_vae_bf16.safetensors \
  --variant q8 "Q8 (best quality)" min_memory_gb=24 \
      llm=Qwen/Qwen3-VL-8B-Instruct-GGUF:Qwen3VL-8B-Instruct-Q8_0.gguf \
      diffusion_model=AtomicChat/Qwen-Image-2.1-Turbo-GGUF:Qwen-Image-2.1-Turbo-Q8_0.gguf \
  --variant q4 "Q4 (smaller)" min_memory_gb=16 \
      llm=Qwen/Qwen3-VL-8B-Instruct-GGUF:Qwen3VL-8B-Instruct-Q4_K_M.gguf \
      diffusion_model=AtomicChat/Qwen-Image-2.1-Turbo-GGUF:Qwen-Image-2.1-Turbo-AD-Q4_K.gguf \
  --steps 8 --cfg 1.0 --sampler euler --width 1024 --height 1024 \
  --sigmas 1.0,0.978453,0.95418,0.926626,0.89508,0.845148,0.704534,0.414568,0.0 \
  --flash-attention \
  --license-note "Denoiser and VAE: Qwen Research License (non-commercial; see the base model repo). Text encoder: Apache-2.0."
```

Before writing anything the script applies the validation rules above and the curated rules, and reports every problem it finds. If a file is not in the repo, it lists the `.gguf` and `.safetensors` files that are. On success it writes the recipe with `"$schema": "./schema.json"` as the first key, regenerates `index.json`, and prints the download size of the recipe or of each variant, which is a useful input when choosing `min_memory_gb`.

The script cannot pin a file the Hub has no SHA-256 for (a file not stored with Git LFS). Model weights are stored with LFS, so this only happens when the path points at something else.

### `check`

```sh
python3 scripts/recipe.py check                       # every recipe, and the index
python3 scripts/recipe.py check recipes/my-model.json # one file
python3 scripts/recipe.py check --offline             # structure only, no network
```

For each recipe it validates the structure, then asks Hugging Face for each repo at its pinned revision and verifies every file of every variant: it exists, its size matches, its SHA-256 matches. It prints one line per file and a summary:

```
recipes/sdxl-base-1.0.json
  ok    checkpoint             stabilityai/stable-diffusion-xl-base-1.0:sd_xl_base_1.0.safetensors  (6938078334 bytes)
recipes/index.json
  ok    lists exactly the recipe files

1 recipe checked: 1 file verified, 0 failed, 0 not checked (network), 0 invalid recipes
OK
```

| Line | Meaning |
| --- | --- |
| `ok` | Verified against Hugging Face. |
| `FAIL` | The recipe is wrong: a rule is broken, the repo, revision or file does not exist, or the size or SHA-256 differs. The line says which. |
| `SKIP` | Hugging Face could not be reached for this file. Nothing was found wrong, and nothing was verified. |

| Exit status | Meaning |
| --- | --- |
| 0 | Everything was verified. |
| 1 | At least one `FAIL`, an invalid recipe, or an index that does not match. |
| 3 | No failure, but at least one file could not be checked because of a network error. Run it again. |

A recipe with `base_model` gets one more line per `diffusion_model` repo, `ok` when the Hub tags that repo as quantized, fine-tuned or merged from the base model.

When run without file arguments it also checks that `index.json` lists exactly the recipe files.

### `index`

```sh
python3 scripts/recipe.py index
```

Rewrites `recipes/index.json` from the recipe files present, sorted by name. `new` does this for you; run it yourself after adding, renaming or deleting a recipe by hand.

## The schema

[`recipes/schema.json`](../recipes/schema.json) is a JSON Schema (draft 2020-12) for curated recipes. A recipe that starts with

```json
{
  "$schema": "./schema.json",
```

gets validation, autocompletion and a description of every field in editors that support JSON Schema. The schema is stricter than the app in the same ways as the script: `revision`, `size_bytes` and `sha256` are required, `engine` must be `sd.cpp`, and unknown fields are errors. It cannot express the `sigmas` count rule, the uniqueness of roles and variant ids, or anything about Hugging Face; `scripts/recipe.py check` covers those.

The schema, the script and the Swift types describe the same format. A change to the format has to update all three, and this page.

## The index

[`recipes/index.json`](../recipes/index.json) lists the recipe files:

```json
{
  "version": 1,
  "recipes": [
    "qwen-image-2.1-turbo.json",
    "sdxl-base-1.0.json"
  ]
}
```

It must list exactly the recipe files in the folder; the tests and `check` both fail otherwise. Do not edit it by hand: run `python3 scripts/recipe.py index`.

## How a merged recipe reaches users

This applies once the repository is public.

Released apps fetch `https://raw.githubusercontent.com/nomansheikh/kiln/main/recipes/index.json` at most once a day, then each file it lists. Every fetched recipe is validated with the rules above and cached under `~/Library/Application Support/Kiln/recipes-remote/`. A fetched recipe replaces the bundled recipe with the same id.

What this means for a contributor:

- A recipe merged into `main` reaches users without a new app release.
- That only works for recipes that use fields released versions understand. A recipe a version cannot decode (a new role, for example) is skipped by that version, and the versions that can decode it show it.
- The index is the list of what gets fetched, so a recipe missing from it does not reach anyone.
- Editing a curated recipe changes it for every user within about a day. Treat a change to `defaults` or to pinned files with the same care as a new recipe.

## Writing a recipe by hand

The script is the recommended path. If you cannot use it, the same result can be produced manually.

1. Get the revision, size and SHA-256 of each file from the Hub API:

   ```sh
   curl -s "https://huggingface.co/api/models/<owner>/<repo>?blobs=true"
   ```

   `sha` is the revision. In `siblings`, the entry whose `rfilename` is your file has `size` and `lfs.sha256`. With `jq`:

   ```sh
   curl -s "https://huggingface.co/api/models/<owner>/<repo>?blobs=true" \
     | jq '{revision: .sha, files: [.siblings[] | {file: .rfilename, size_bytes: .size, sha256: .lfs.sha256}]}'
   ```

   For a specific commit or branch, use `https://huggingface.co/api/models/<owner>/<repo>/revision/<revision>?blobs=true`.

2. Copy an existing recipe to `recipes/<id>.json` and edit it. Keep `"$schema": "./schema.json"` as the first key.
3. Add the file name to `recipes/index.json`, keeping the list sorted (or run `python3 scripts/recipe.py index`).
4. Run `python3 scripts/recipe.py check` if you can, and `swift test`.

## Memory fit

Kiln estimates whether a recipe fits in the Mac's unified memory. The logic is `MemoryFitEstimator` in [`MemoryFit.swift`](../Sources/KilnCore/Recipes/MemoryFit.swift). It is a heuristic on file sizes only and ignores the working memory that grows with image resolution, so "comfortable" is not a guarantee.

Inputs:

- `RAM`: physical memory of the Mac. 1 GB here means 1,073,741,824 bytes.
- `size`: the sum of `size_bytes` over all components. It is unknown if any component has no `size_bytes`.
- `min_memory_gb`, if present.

For a recipe with variants, the estimate is made per variant, on the merged files and with the variant's `min_memory_gb` (or the recipe's, when the variant has none).

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

Worked example with the two variants above: `q8` is 16,976,606,456 bytes (about 15.8 GB) with `min_memory_gb` 24, and `q4` is 9,904,989,432 bytes (about 9.2 GB) with `min_memory_gb` 16.

| Mac RAM | Usable | 85% of usable | `q8` | `q4` | Offered first |
| --- | --- | --- | --- | --- | --- |
| 8 GB | 4.7 GB | 4.0 GB | too large (below 24) | too large (below 16) | `q4`, the smallest |
| 16 GB | 11.9 GB | 10.1 GB | too large (below 24) | comfortable | `q4` |
| 24 GB | 19.1 GB | 16.2 GB | comfortable | comfortable | `q8`, the largest comfortable |

On the Models screen the result is shown as "Fits your N GB Mac", "Tight fit on N GB" or "Needs more than N GB". A recipe that is too large can still be downloaded; its Download button is shown in the quieter style with a warning tooltip.

Individual files in the Hugging Face list get the same label, computed from that one file's size with steps 3 to 5 (there is no `min_memory_gb` for them).

The estimate is advisory. If the helper runs out of memory during generation, Kiln reports that as an out-of-memory error.

## Importing a recipe in the app

1. Open the Models screen.
2. Click "Import Recipe" in the header, next to the search field and the "Downloaded" filter.
3. Select your `.json` file. The file picker accepts JSON files only.

Kiln decodes and validates the file with the rules above. If it is valid, it is copied to `~/Library/Application Support/Kiln/recipes/<id>.json`, named after the recipe's `id` whatever the original file was called, and appears in the recipe list on the Models screen with a Download button. Importing a recipe with the same id as an existing user recipe replaces it.

Import fails, with a "Could Not Import Recipe" alert, when:

- the file is not valid JSON, a required field is missing or a value has the wrong type
- a validation rule is violated
- the `id` is already used by a built-in recipe

Imported recipes do not need `revision`, `size_bytes` or `sha256`, but leaving them out means the download is taken from `main` and is not verified, there is no disk-space check for that file, and there is no size-based memory estimate.

Importing is the way to try a recipe before opening a pull request: create it with the script, import the file, download it and generate an image.

There is no button to remove a recipe. Deleting a model on the Models screen removes its downloaded files and keeps the recipe in the list. To remove an imported recipe, delete its file from the user recipes folder.

## Family recipes

Most split models are published many times over: the same denoiser quantized by different people, or fine-tuned. Kiln does not need a recipe for each of those repos. When a repo in the Hugging Face list is a version of a model that a curated recipe covers, Kiln offers its files for download and completes the model from that recipe.

A repo matches a curated recipe when all of this holds:

- the recipe has `base_model` and a `diffusion_model` component
- the repo's Hub tags include `base_model:quantized:<base_model>`, `base_model:finetune:<base_model>` or `base_model:merge:<base_model>`. `base_model:adapter:` (a LoRA) does not count.
- none of the repo's files is already part of a curated recipe (such a repo shows that recipe instead)

Files that look like a denoiser can then be downloaded. That is a guess from the path: a `.gguf` or `.safetensors` file that is not split into shards (`-00001-of-00003`), is not named `ae.safetensors`, and has none of `vae`, `clip`, `t5`, `encoder`, `lora`, `mmproj`, `controlnet`, `adapter` in its path. The card's Download button picks the largest such file that fits comfortably in memory together with the recipe's other files, otherwise the smallest.

Downloading one builds a user recipe with `ModelRecipe.adapted(to:in:)` in [`ModelRecipe+Family.swift`](../Sources/KilnCore/Recipes/ModelRecipe+Family.swift):

| Field | Value |
| --- | --- |
| `id`, `name` | As for a [single-file recipe](#single-file-recipes) |
| `components` | The curated recipe's files in its current variant, with the `diffusion_model` replaced by the chosen file (repo, path, and the `revision`, `size_bytes` and `sha256` the Hub API reported) |
| `defaults` | The curated recipe's |
| `license_note` | The repo's licence tag for the chosen file, followed by the curated recipe's note for the rest |
| `min_memory_gb`, `tested`, `base_model`, `variants` | Not set |

Things to know:

- The pairing is inferred from a tag, not tested. A straight quantization behaves like the original. A fine-tune or merge loads with the same companions but may want other settings, and a file in a format stable-diffusion.cpp cannot read fails to load.
- Files the curated recipe already downloaded are reused, so usually only the new denoiser is fetched.
- Only the denoiser can be swapped this way. A different text encoder or VAE still needs a hand-written recipe.

## Single-file recipes

The Models screen also lists Hugging Face repos: the most downloaded text-to-image models, or search results. Opening "Files" on a repo shows its `.safetensors` and `.gguf` files (files whose name starts with `mmproj` are left out). Clicking Download on one of them does not need a hand-written recipe: Kiln builds one with `ModelRecipe.singleFile` in [`ModelRecipe+SingleFile.swift`](../Sources/KilnCore/Recipes/ModelRecipe+SingleFile.swift), saves it to the user recipes folder and starts the download.

The generated recipe has:

| Field | Value |
| --- | --- |
| `id` | `<repo id>-<file name>`, lowercased, with every character other than ASCII letters, digits, `.` and `-` replaced by `-`, and leading and trailing `.` and `-` removed |
| `name` | The file name |
| `engine` | `sd.cpp` |
| `components` | One component with the role `checkpoint`, the repo, the file path, and the `revision`, `size_bytes` and `sha256` the Hub API reported |
| `defaults` | 20 steps, cfg 7.0, sampler `euler`, and 1024 x 1024 when the file name contains `xl`, otherwise 512 x 512 |
| `license_note` | The repo's licence tag, when it has one |
| `min_memory_gb` | Not set |

Things to know:

- This only yields a runnable model for all-in-one checkpoints, for example SD 1.5 or SDXL `.safetensors`. The file is always loaded as a `checkpoint`. A text encoder or VAE downloaded this way will not run on its own, and neither will a denoiser unless its repo matches a [family recipe](#family-recipes); other models split into several files need a hand-written recipe.
- The defaults are generic, not taken from the model card. Adjust them in the advanced settings, or write a proper recipe.
- The recipe is an ordinary user recipe. It is validated before it is saved, and downloading the same file again replaces it.
