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

A single all-in-one checkpoint does not strictly need a hand-written recipe: downloading the file from the Hugging Face list on the Models screen creates a single-file recipe automatically, with generic settings. A curated recipe is still worth contributing when the model card recommends different settings, and it is required for any model split into several files.

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

In the description, link the model card (or other primary source) your settings come from, and say which Mac (chip and memory) you ran the recipe on, if any. If you could not run it, say so.

To try a recipe before opening the PR, import it on the Models screen with "Import Recipe", download it and generate an image.

### What reviewers check

- **Settings come from the model card.** Steps, CFG, sampler, resolution and any custom sigmas match what the model authors recommend, and the PR links the source.
- **`license_note` is accurate.** It names the actual license of each component and calls out restrictions such as non-commercial use. When components have different licenses, list each one.
- **`min_memory_gb` is honest.** It is the smallest amount of system RAM the recipe is expected to run on, not the smallest that looks good in a table. If you have not tested at that size, pick a conservative value and say so in the PR.
- **Files are pinned and correct.** `revision`, `size_bytes` and `sha256` match the Hub API output for the repo and file listed.
- **Roles are right.** Each file is assigned the role the engine needs it in.

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
- Do not edit `Vendor/stable-diffusion.cpp`; it is a git submodule.

### Screenshots for a pull request

If a change affects what the app looks like, attach screenshots. Debug builds can capture them without a model installed. Launch the built app's executable with:

```sh
/path/to/Kiln.app/Contents/MacOS/Kiln --snapshot <folder>
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
