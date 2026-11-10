# Contributing to Kiln

The most useful contribution is a model recipe: one JSON file that makes a model a one-click download with settings that work. This guide covers that first, then code contributions.

If you work through an AI coding agent, point it at [AGENTS.md](AGENTS.md). It holds the same rules in a form written for agents.

## Contributing a recipe

A recipe lists every file a model needs on Hugging Face and its recommended settings. A script does the tedious part (commit, size and SHA-256 of each file) and checks the result. It needs only the `python3` that comes with Xcode's command line tools, and it never downloads model files.

The full reference is [docs/recipes.md](docs/recipes.md). The path below is the short version.

### 1. Create the recipe

Find the model on Hugging Face, decide which files it needs, and give each one a role:

| Role | Use it for |
| --- | --- |
| `checkpoint` | A single file that carries everything (SD 1.x, SDXL) |
| `diffusion_model` | A standalone denoiser |
| `llm` | A language model used as the text encoder (Qwen-Image and similar) |
| `vae` | A standalone VAE |
| `clip_l`, `clip_g`, `t5xxl` | CLIP and T5 text encoders (Flux and SD3 families) |

Then run `new`, writing each file as `ROLE=OWNER/REPO:PATH`:

```sh
python3 scripts/recipe.py new \
  --id sdxl-base-1.0 \
  --name "Stable Diffusion XL Base 1.0" \
  --component checkpoint=stabilityai/stable-diffusion-xl-base-1.0:sd_xl_base_1.0.safetensors \
  --steps 30 --cfg 7.0 --sampler euler --width 1024 --height 1024 \
  --license-note "CreativeML Open RAIL++-M License." \
  --min-memory-gb 16
```

This writes `recipes/sdxl-base-1.0.json` and updates `recipes/index.json`. Things to know:

- **Settings come from the model card**, or from the model's page in stable-diffusion.cpp's [docs](https://github.com/leejet/stable-diffusion.cpp/tree/master/docs). The script has no default values for them on purpose.
- **Files may come from different repos.** Prefer `.gguf` or `.safetensors`. Each role can be used once.
- **Several quantizations of one model are variants of one recipe**, not separate recipes: add `--variant ID "NAME" min_memory_gb=N ROLE=OWNER/REPO:PATH ...` once per quantization, and keep the files they share in `--component`. See [variants](docs/recipes.md#variants).
- `python3 scripts/recipe.py new --help` shows every option and two complete examples.

A single all-in-one checkpoint does not strictly need a curated recipe: downloading the file from the Hugging Face list on the Models screen creates a single-file recipe automatically, with generic settings. A curated recipe is still worth contributing when the model card recommends different settings, and it is required for any model split into several files.

### 2. Check it

```sh
python3 scripts/recipe.py check
```

This validates every recipe and verifies each file against Hugging Face at its pinned revision: the file exists, the size matches, the SHA-256 matches. It must end with `OK`. CI runs the same command.

### 3. Run the tests

```sh
swift test
```

`everyCuratedRecipeIsValid` decodes every file in `recipes/` with the app's own code and fails if a file name does not match its id, if `engine` is not `sd.cpp`, if any file of any variant is missing `revision`, `size_bytes` or `sha256`, or if `index.json` does not list exactly the recipe files.

### 4. Try it in the app, if you can

Build the app ([README](README.md#build-from-source)), import your file on the Models screen with "Import Recipe", download it and generate an image. This is the only step that downloads weights, and it is optional: if you cannot do it, say so in the pull request.

### 5. Open a pull request

In the description:

- link the model card (or other primary source) for every setting and for the licence
- paste the output of `python3 scripts/recipe.py check`
- say which Mac (chip and memory) you ran the recipe on, or that you did not run it

Once the repository is public, released apps pick up merged recipes from this repository within about a day, without an app release. See [how a merged recipe reaches users](docs/recipes.md#how-a-merged-recipe-reaches-users).

### What reviewers check

- **Settings come from the model card.** Steps, CFG, sampler, resolution, and any scheduler, guidance, flow shift or custom sigmas match what the model authors recommend, and the PR links the source.
- **`license_note` is accurate.** It names the actual licence of each component and calls out restrictions such as non-commercial use. When components have different licences, list each one.
- **`min_memory_gb` is honest.** It is the smallest amount of system RAM the recipe (or the variant) is expected to run on, not the smallest that looks good in a table. If you have not tested at that size, pick a conservative value and say so in the PR.
- **Files are what they claim to be.** They come from the model authors or a well-known converter, the file name describes the content, and `check` passes.
- **Roles are right.** Each file is assigned the role the engine needs it in.
- **Variants are the same model.** They differ only in quantization or precision and share the recipe's settings.

## Contributing code

Build instructions are in the [README](README.md#build-from-source). The structure of the code is described in [docs/architecture.md](docs/architecture.md).

### Conventions

- **One primary type per file**, named after the type. A small helper that only that type uses may share the file.
- **Keep files short.** Aim for about 200 lines; 250 is the hard cap. Split a view or a type before it gets there.
- **Feature folders.** Each screen lives in its own folder under `App/Features/` (`Generate`, `Models`, `Gallery`, `Settings`). The window, sidebar, chat list and downloads popover are in `App/Shell/`.
- **One `@Observable` store per feature** in `App/Stores/`, owned by the root `AppModel`. Views read the stores from the environment and call their methods. Actions that touch more than one store belong on `AppModel`.
- **Shared views and styles go in `App/DesignSystem/`** (`Theme`, `Motion`, button styles, `Pill`, `Thumbnail` and so on). Use them instead of repeating colours, radii or animations in a feature.
- **`KilnCore` stays free of UI.** It must not import SwiftUI or AppKit; views and app state belong in `App/`.
- **Swift 6 strict concurrency.** The package and the app build in Swift 6 language mode. Do not silence concurrency diagnostics without a comment explaining why the code is safe.
- **`swift test` must pass.** New behaviour in `KilnCore` needs tests. Network and process boundaries are behind protocols (`HTTPTransport`, `FileDownloading`, `TokenStore`, `InferenceEngine`) so they can be tested without the network or real weights. The SwiftUI app has no tests, so keep logic that can be tested in `KilnCore`.
- Changes to the helper protocol must update `Engine/main.cpp`, `Sources/KilnCore/Engine/EngineProtocol.swift` and [docs/architecture.md](docs/architecture.md) together.
- Changes to the recipe format must update `Sources/KilnCore/Recipes/`, `recipes/schema.json`, `scripts/recipe.py` and [docs/recipes.md](docs/recipes.md) together.
- Do not edit `Vendor/stable-diffusion.cpp`; it is a git submodule.

### Screenshots for a pull request

If a change affects what the app looks like, attach screenshots. Debug builds can capture them without a model installed. Quit any running copy of Kiln, then launch the built app with:

```sh
open -n /path/to/Kiln.app --args --snapshot /absolute/path/to/folder
```

The app waits for the window to settle, switches to each screen in turn, writes `generate.png`, `models.png`, `gallery.png` and `settings.png` into the folder (creating it if needed), and quits. It draws its own window into the images, so no screen-recording permission is needed. The Models screenshot is taken after a few seconds so the Hugging Face list has time to load; that part needs a network connection.

Other debug-only flags, which can be combined with `--snapshot`:

| Flag | Effect |
| --- | --- |
| `--light` | Forces the light appearance. Without it the app follows the system setting. Works on its own, without `--snapshot`. |
| `--sample-thread` | Fills the Generate screen with a finished turn, a failed turn and a running turn with a step preview and an attached image, so every thread state is visible without a model. It writes one sample image to the temporary directory and one copy to the attachments folder. Only applies together with `--snapshot`. |
| `--sample-downloads` | Shows the first recipe as a download in progress with a sample speed and time left. Only applies together with `--snapshot`. |

None of these exist in release builds. The implementation is in [`App/Support/DebugSnapshot.swift`](App/Support/DebugSnapshot.swift).

### What is not verified

Say in your PR what you actually ran. At the time of writing, generation has only been confirmed on one machine with one recipe, and image-to-image and the step preview have not been confirmed with a real model (see the Status section of the [README](README.md#status)). Reports from other Macs and models are useful contributions in themselves.
