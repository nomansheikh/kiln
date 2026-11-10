# AGENTS.md

Instructions for AI coding agents contributing to Kiln. Follow this file and the pull request you produce should be ready to merge. Humans: the same material is in [CONTRIBUTING.md](CONTRIBUTING.md).

## 1. The project

Kiln is a native macOS app (Swift 6, SwiftUI, macOS 14 or later, Apple Silicon, MIT licence). It downloads image-generation models from Hugging Face and runs them locally with [stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp) through a separate helper process.

A model is described by a **recipe**: one JSON file in `recipes/` listing every file the model needs (Hugging Face repo, path, pinned commit, byte size, SHA-256, role) and its default settings.

There are two kinds of contribution:

- **A recipe** (section 4). No Swift, no build needed. This is the most common one.
- **A code change** (section 5).

## 2. Repository map

| Path | What belongs there |
| --- | --- |
| `recipes/` | Curated recipes, one `<id>.json` per model. `index.json` (generated list of recipes) and `schema.json` (JSON Schema) are reserved names, not recipes. |
| `scripts/` | `recipe.py` (create, check and index recipes), `build-engine.sh` (build the helper), `package-dmg.sh` and `make-icon.swift` (release tooling). |
| `Sources/KilnCore/` | UI-free Swift library. Subfolders: `Recipes/` (format, validation, loading, memory fit), `HuggingFace/` (Hub API client, token storage), `Downloads/` (queue, resumable transfers, verification), `Engine/` (generation API, helper process, wire format), `Gallery/` (PNG files with embedded settings), `Chats/` (saved chats). |
| `Tests/KilnCoreTests/` | Unit tests for KilnCore, written with Swift Testing. Test doubles and fixtures are in `Support/`. |
| `App/` | The SwiftUI app. `KilnApp.swift` is the entry point. |
| `App/Stores/` | Observable state: `AppModel` (the root) and one store per feature. |
| `App/Features/` | One folder per screen: `Generate/`, `Models/` (with `Hub/`), `Gallery/`, `Settings/`. |
| `App/Shell/` | Window, sidebar, chat list, and `Downloads/` (the downloads popover). |
| `App/DesignSystem/` | Shared views and styles: `Theme`, `Motion`, button styles, `Pill`, `Thumbnail` and others. |
| `App/Support/` | `AppDelegate`, `KeyboardNavigationMonitor`, `DebugSnapshot`. |
| `Engine/` | `kiln-engine`: `main.cpp` and `CMakeLists.txt`. The C++ helper that links stable-diffusion.cpp. |
| `Vendor/stable-diffusion.cpp/` | Git submodule. Read-only. Its `docs/` folder documents each supported model family. |
| `docs/` | `architecture.md` (modules, helper protocol, download flow), `recipes.md` (recipe reference), `releasing.md`. |
| `.github/` | CI (`workflows/ci.yml`), release workflow, issue and pull request templates. |
| `Package.swift` | Swift package: the `KilnCore` library and its tests. |
| `project.yml` | XcodeGen definition of the app target. `Kiln.xcodeproj` is generated from it. |

Read [docs/architecture.md](docs/architecture.md) before a code change and [docs/recipes.md](docs/recipes.md) before a recipe change.

## 3. Setup and commands

Run everything from the repository root.

A recipe contribution needs only this (fast, no build):

```sh
python3 scripts/recipe.py check
swift test
```

A code contribution needs the full setup:

```sh
git submodule update --init --recursive
brew install cmake xcodegen
./scripts/build-engine.sh
xcodegen generate
swift test
xcodebuild -scheme Kiln -configuration Debug -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO build
python3 scripts/recipe.py check
```

| Command | What it does | Cost |
| --- | --- | --- |
| `git submodule update --init --recursive` | Fetches stable-diffusion.cpp into `Vendor/`. | Network |
| `brew install cmake xcodegen` | Installs the two build tools. | Once |
| `./scripts/build-engine.sh` | Compiles stable-diffusion.cpp and the helper into `build/engine/kiln-engine`. | Slow |
| `xcodegen generate` | Writes `Kiln.xcodeproj` from `project.yml`. Run it again after adding, moving or deleting files under `App/`. | Fast |
| `swift test` | Builds KilnCore and runs its unit tests. Needs no engine, no network and no model. | Fast |
| `xcodebuild ... build` | Builds the app (the line above is the one CI uses). | Slow |
| `python3 scripts/recipe.py check` | Validates every recipe and verifies every file against the Hugging Face API. Needs network. Downloads nothing. | Fast |

CI (`.github/workflows/ci.yml`) runs, in order: the recipe check, `swift test`, the engine build, `xcodegen generate`, the `xcodebuild` line.

Never commit these. They are in `.gitignore`:

- `Kiln.xcodeproj` (generated)
- `build/`, `.build/`, `DerivedData/`, `.swiftpm/`, `xcuserdata/`, `.DS_Store`

## 4. Adding a recipe

### Steps

1. **Read the model card** on Hugging Face and the model's page in `Vendor/stable-diffusion.cpp/docs/` if there is one (for example `flux.md`, `sd3.md`, `qwen_image.md`). If the submodule is not checked out, read the same files in the stable-diffusion.cpp repository.
2. **Choose the files and roles** (see "Roles" below).
3. **Collect the settings**, each with its source (see "Settings" below).
4. **Create the recipe** with the script. It looks up the commit, size and SHA-256 of each file from the Hugging Face API, writes `recipes/<id>.json` and regenerates `recipes/index.json`:

   ```sh
   python3 scripts/recipe.py new \
     --id sdxl-base-1.0 \
     --name "Stable Diffusion XL Base 1.0" \
     --component checkpoint=stabilityai/stable-diffusion-xl-base-1.0:sd_xl_base_1.0.safetensors \
     --steps 30 --cfg 7.0 --sampler euler --width 1024 --height 1024 \
     --license-note "CreativeML Open RAIL++-M License." \
     --min-memory-gb 16
   ```

   Run `python3 scripts/recipe.py new --help` for every option and a second example with variants. Do not hand-write `revision`, `size_bytes` or `sha256`, and do not hand-edit `index.json`.
5. **Check it.** This must end with `OK` and exit status 0:

   ```sh
   python3 scripts/recipe.py check
   ```

   Exit status 1 means the recipe is wrong; fix it. Exit status 3 means Hugging Face could not be reached; the recipe is not verified, so run it again, and do not report it as passing.
6. **Run the tests.** `swift test` must pass.
7. **Open the pull request** (section 7) with the sources and the `check` output.

Trying the recipe in the app means downloading several gigabytes of weights. Do not do that unless the user asked for it. State in the pull request that the recipe was not run.

### Component syntax

```
ROLE=OWNER/REPO:PATH              current commit of the default branch
ROLE=OWNER/REPO@REVISION:PATH     a specific commit or branch
```

`PATH` is the file's path inside the repo, for example `vae/model.safetensors`.

### Roles

| Role | Use it for | stable-diffusion.cpp flag in its docs |
| --- | --- | --- |
| `checkpoint` | A single file that carries everything (SD 1.x, SDXL) | `-m` |
| `diffusion_model` | A standalone denoiser | `--diffusion-model` |
| `llm` | A language model used as the text encoder | `--llm` |
| `vae` | A standalone VAE | `--vae` |
| `clip_l` | CLIP-L text encoder | `--clip_l` |
| `clip_g` | CLIP-G text encoder | `--clip_g` |
| `t5xxl` | T5-XXL text encoder | `--t5xxl` |

- Pick roles from the example command for the model family in `Vendor/stable-diffusion.cpp/docs/`: each flag in the table maps to one role.
- Each role may appear once per install. There are no other roles. If the model needs a file with no role here (a LoRA, a vision projector, or any other flag), it cannot be described yet: stop and say so instead of forcing the file into another role.
- Prefer `.gguf` or `.safetensors` files.

### Settings

`--steps`, `--cfg`, `--sampler`, `--width` and `--height` are required. `--scheduler`, `--guidance`, `--flow-shift`, `--sigmas` and `--flash-attention` are optional.

- Every value must come from the model card or from the model's page in `Vendor/stable-diffusion.cpp/docs/`. Never guess, never carry a value over from a different model, never fill a gap from memory.
- Leave an optional setting out when no source gives it. The engine then uses its own default.
- If a required setting has no source, stop and ask the user, or state plainly in the pull request which value has no source.
- Sampler and scheduler names are stable-diffusion.cpp's, not the names other tools use. The script rejects unknown names and lists the valid ones.
- `--sigmas` needs exactly `steps + 1` values.
- Record the link for each setting. The pull request must include them.

### Variants

Use variants when one model is published in several quantizations or precisions (for example Q8 and Q4 GGUF files). They are one recipe, not several:

```sh
  --component vae=OWNER/REPO:vae.safetensors \
  --variant q8 "Q8 (best quality)" min_memory_gb=24 diffusion_model=OWNER/REPO:model-Q8_0.gguf \
  --variant q4 "Q4 (smaller)" min_memory_gb=16 diffusion_model=OWNER/REPO:model-Q4_K.gguf \
```

- `--component` files are shared by every variant. A variant lists the files that differ; a file with the same role as a shared one replaces it.
- Every variant must be a complete model after merging.
- All variants share the recipe's settings. A version that needs different steps, sampler or sigmas (a turbo or distilled model) is a separate recipe.
- The app offers the largest variant that fits comfortably in the Mac's memory and lets the user switch.

### `min_memory_gb`

- It is the smallest amount of system RAM the recipe, or the variant, is expected to run on.
- Use a value from the model card or from a test the user ran. Otherwise choose a conservative value (well above the download size the script prints) and say in the pull request that it is an untested estimate.
- Never lower it to make a model look more accessible.

### `license_note`

- State the licence of every file as its Hugging Face page states it, and name restrictions such as non-commercial use.
- When files have different licences, name each one. A converted or quantized file keeps the licence of the original model unless its page says otherwise; check both pages.
- Never invent or assume a licence. If a file's licence is unclear, stop and say so.

### Files a curated recipe must not use

- Files whose origin cannot be traced to the model authors or a well-known converter.
- Files whose name does not describe their content (a fine-tune or merge labelled as the base model, a different quantization than the name says).
- Files that only load with patches or options Kiln does not pass.

### Editing an existing recipe

Curated recipes are fetched by released apps from this repository (once it is public) and replace the bundled copy with the same id, so an edit reaches every user within about a day. Keep the `id`. Use only fields documented in [docs/recipes.md](docs/recipes.md); a recipe that a released version cannot decode is skipped by that version. To refresh pinned files, rerun `new` with `--force`.

## 5. Changing code

### Steps

1. Read [docs/architecture.md](docs/architecture.md) and the files you will touch.
2. Put the change where it belongs (section 2). Logic that can be tested goes in `Sources/KilnCore/`; views and app state go in `App/`.
3. Add or update tests for any KilnCore behaviour you change.
4. Run `swift test`. For any change under `App/`, `Engine/` or `project.yml`, also run `xcodegen generate` and the `xcodebuild` line.
5. For a change to what the app looks like, capture screenshots (below).
6. Update the documentation that describes what you changed.

### Conventions

- **One primary type per file**, named after the type. A small helper used only by that type may share the file.
- **File length:** about 200 lines, hard cap 250. Split before reaching it.
- **Feature folders:** each screen has its folder under `App/Features/`.
- **One observable store per feature** in `App/Stores/`, owned by `AppModel`. Views read stores from the environment and call their methods. Actions that touch more than one store belong on `AppModel`.
- **Shared views and styles** go in `App/DesignSystem/`. Use `Theme` and the existing styles instead of repeating colours, radii or animations.
- **KilnCore is free of UI:** no `import SwiftUI`, no `import AppKit`. It is fully unit-tested; new behaviour there needs tests.
- **Swift 6 strict concurrency.** Do not silence a concurrency diagnostic without a comment explaining why the code is safe.
- **User-facing errors are in plain language:** say what happened and what the user can do, without type names, codes or jargon. Follow the existing `errorDescription` texts.
- **Respect Reduce Motion:** take animations and transitions from `App/DesignSystem/Motion.swift`, which falls back to plain fades. Do not write ad hoc animations in a feature.
- **Comments** only where something is not obvious from the code. Explain why, not what.
- **Coupled changes:**
  - Helper protocol: `Engine/main.cpp`, `Sources/KilnCore/Engine/EngineProtocol.swift` and `docs/architecture.md` together.
  - Recipe format: `Sources/KilnCore/Recipes/`, `recipes/schema.json`, `scripts/recipe.py` and `docs/recipes.md` together.

### Tests

Tests use Swift Testing, not XCTest:

```swift
import Foundation
import Testing
@testable import KilnCore

@Suite struct ThingTests {
    @Test func describesTheBehaviourBeingChecked() throws {
        let recipe = makeRecipe()
        #expect(recipe.id == "test-model")
    }
}
```

- One suite per file in `Tests/KilnCoreTests/`, named `<Subject>Tests.swift`.
- Test doubles and fixtures live in `Tests/KilnCoreTests/Support/`: `RecipeFixtures.swift` (`makeRecipe`, `curatedRecipesDirectory`), `MockTransport.swift`, `StubURLProtocol.swift`, `FakeDownloader.swift`, `EngineFixture.swift`. Reuse them; add a new double there, not inside a test file.
- Tests must not use the network, real model files or the real helper. The boundaries are protocols (`HTTPTransport`, `FileDownloading`, `TokenStore`, `InferenceEngine`).
- The SwiftUI app has no tests. Keep testable logic in KilnCore.

### Screenshots

Debug builds can save a PNG of each screen without a model installed. The flags are defined in `App/Support/DebugSnapshot.swift` and do not exist in release builds.

1. Build the app. Adding `-derivedDataPath build/xcode` to the `xcodebuild` line puts it at `build/xcode/Build/Products/Debug/Kiln.app` (`build/` is ignored by git).
2. Make sure no other instance of Kiln is running.
3. Launch it through `open` with an absolute output folder:

   ```sh
   open -n build/xcode/Build/Products/Debug/Kiln.app --args --snapshot /absolute/path/to/folder
   ```

The app writes `generate.png`, `models.png`, `gallery.png` and `settings.png` into the folder and quits. The Models screenshot needs network for the Hugging Face list.

| Flag | Effect |
| --- | --- |
| `--snapshot <folder>` | Save one PNG per screen into the folder, then quit. |
| `--light` | Force the light appearance. Without it the app follows the system setting. |
| `--sample-thread` | With `--snapshot`: fill the Generate screen with a finished, a failed and a running turn. |
| `--sample-downloads` | With `--snapshot`: show the first recipe as a download in progress. |

To capture the light appearance regardless of the system setting, add `--light`.

## 6. Hard rules

- **Never download model weights and never run a generation** as part of a contribution unless the user asked for it. The recipe script and the tests do not need either.
- **Never edit `Vendor/`.** It is a submodule.
- **Never invent** command-line flags, API fields, recipe fields, sampler or scheduler names, settings or licences. If it is not in the source, the documentation or the model card, it does not exist.
- **Never weaken, skip or delete a test** to make it pass. Fix the code, or report the failure.
- **Do not add dependencies** (Swift packages, Python packages, tools, GitHub Actions) without discussing it with the maintainer first. `scripts/recipe.py` uses the Python standard library only and must keep working on Python 3.9.
- **Keep the change scoped** to the task. No drive-by refactors, reformatting or renames.
- **Never commit** generated or local files (section 3), secrets or access tokens. `HF_TOKEN` is read from the environment and must not be written to any file.
- **Do not hand-edit** `recipes/index.json`; run `python3 scripts/recipe.py index`.

## 7. Definition of done

Check every item that applies before opening the pull request.

All changes:

- [ ] The change does what was asked and nothing else.
- [ ] `swift test` passes, and you ran it after your last edit.
- [ ] No generated files, build output or secrets are staged.
- [ ] Documentation that describes the changed behaviour is updated.

Recipes:

- [ ] `python3 scripts/recipe.py check` ends with `OK` and exit status 0, after your last edit.
- [ ] The file is `recipes/<id>.json`, starts with `"$schema": "./schema.json"`, and `recipes/index.json` was regenerated by the script.
- [ ] Every setting has a source link, and no setting is a guess.
- [ ] `license_note` matches the licence pages of every file.
- [ ] `min_memory_gb` is sourced, tested by the user, or declared as a conservative estimate.

Code:

- [ ] New KilnCore behaviour has tests.
- [ ] For changes under `App/`, `Engine/` or `project.yml`: `xcodegen generate` and the `xcodebuild` line succeed.
- [ ] No file exceeds 250 lines, and each new file holds one primary type.
- [ ] Screenshots are captured for visual changes.

### Commits

Conventional commits: `type(scope): subject`.

- Subject in the imperative mood, lower case, no full stop, at most 50 characters.
- Types: `feat`, `fix`, `docs`, `test`, `refactor`, `build`, `ci`, `chore`.
- Scope is the area touched, for example `recipes`, `models`, `app`, `engine`.
- One self-contained change per commit.

```
feat(recipes): add flux.1 schnell recipe
fix(downloads): resume after a 416 response
docs(recipes): document variants
```

### Pull request

Use `.github/pull_request_template.md`. The description must contain:

1. **What changed and why**, in a few sentences. Link the issue if there is one.
2. **How it was verified:** the exact commands you ran and their results, for example the summary line of `swift test` and the full output of `python3 scripts/recipe.py check`.
3. **For recipes:** a link to the model card or other primary source for every setting and every licence, and whether the recipe was run in the app (on which Mac) or not.
4. **For UI changes:** the screenshots.
5. **What was not verified.**

## 8. Reporting honestly

- Report a command as passing only if you ran it after your last change and saw it pass. Quote the result.
- Separate what you verified from what you inferred or did not check. "Not run" is an acceptable answer; an unstated gap is not.
- A recipe that passes `check` has correct, existing files. It has not been shown to generate an image. Say which of the two you established.
- If `check` exited with status 3, or any step was skipped for lack of network, tools or permissions, say so.
- If a setting, role or licence could not be sourced, name it. Do not fill the gap.
- If you are blocked, stop and describe the blocker instead of working around it.
