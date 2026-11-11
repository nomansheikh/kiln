# Kiln

Kiln is a native macOS app that browses Hugging Face text-to-image models, downloads them and generates images locally on Apple Silicon with [stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp) and Metal. It is written in Swift 6 and SwiftUI, runs on macOS 14 or later, and is MIT licensed.

<!-- demo GIF goes here -->

## Status

Kiln is early. Read this before relying on it.

- **Tested:** text-to-image with the Stable Diffusion XL Base 1.0 recipe has been downloaded and run end to end through the app on one machine, an Apple M5 Ultra with 96 GB of memory. No other machine has been tested.
- **Not run yet:** the Qwen-Image 2.1 Turbo recipe.
- **Implemented but not confirmed with a real model:** image-to-image (attaching an image) and the live step preview. Both are unit-tested at the protocol level only.
- **Memory-fit label:** a heuristic based on file sizes only. It does not account for the memory a generation needs on top of the weights.
- **Hugging Face single-file downloads:** downloading one file from a repo gives a runnable model for all-in-one checkpoints (for example SD 1.5 or SDXL `.safetensors`), and for other versions of a model Kiln has a recipe for (for example another GGUF quantization), which borrow that recipe's remaining files and settings untested. Any other model split into several files needs a recipe.
- **Releases:** there are no signed or notarized builds and no auto-update. A release script exists but no release has been cut yet (see [docs/releasing.md](docs/releasing.md)); until then you build from source.
- **Tests:** the core library has unit tests (`swift test`). The SwiftUI app has none.
- **CI:** a GitHub Actions workflow runs the core tests, builds the engine helper and builds the app on every push.
- **Not implemented:** video, training, LoRA, instruction-based editing with a vision encoder, pasting images from the clipboard, automatic choice of quantization.

## Features

- **Chat-style generation.** Each prompt and its image form a turn in a thread. Chats are saved and listed in the sidebar, where they can be renamed, archived and deleted.
- **Live step preview.** While an image is sampling, a rough preview is shown when the model can provide one.
- **Image-to-image.** Attach an image with the plus button, by dropping a file on the composer, or with "Edit this image" on a result. Three strengths: Subtle, Balanced and Strong.
- **Model recipes.** A JSON manifest lists every file a model needs and its recommended settings, so a model is one click to download. Two recipes ship with the app: Stable Diffusion XL Base 1.0 and Qwen-Image 2.1 Turbo.
- **Hugging Face browsing and search.** The Models screen lists the most downloaded text-to-image repos and searches the Hub. Each repo shows its `.safetensors` and `.gguf` files, which can be downloaded one at a time.
- **Downloads.** Resumable, checked against the pinned size and SHA-256, with pause and cancel. A downloads panel in the sidebar shows progress, speed and time left.
- **Memory-fit label.** Each recipe and Hub file is marked as fitting, tight or too large for this Mac.
- **Gallery.** Every image is a plain PNG with its prompt and settings embedded. "Reuse Settings" loads them back into the composer, including the seed.
- **Unload the model.** Frees the memory held by the loaded model from the Image menu, the model menu or Settings.
- **Optional Hugging Face token** for gated models, stored in the macOS Keychain and sent only to `huggingface.co`.

## Requirements

- Apple Silicon Mac running macOS 14 or later
- Xcode 16 or later (Swift 6)
- CMake and XcodeGen: `brew install cmake xcodegen`

## Build from source

```sh
git clone --recursive https://github.com/nomansheikh/kiln.git
cd kiln

# If you cloned without --recursive:
git submodule update --init --recursive

brew install cmake xcodegen

# Build the engine helper (output: build/engine/kiln-engine)
./scripts/build-engine.sh

# Generate Kiln.xcodeproj from project.yml
xcodegen generate
```

Then open `Kiln.xcodeproj` in Xcode and run the `Kiln` scheme, or build from the command line:

```sh
xcodebuild -scheme Kiln -configuration Release build
```

Run the core library tests with:

```sh
swift test
```

### Repository layout

| Path | Contents |
| --- | --- |
| `App/` | SwiftUI app: `Stores/`, `Features/`, `Shell/`, `DesignSystem/`, `Support/` |
| `Sources/KilnCore/` | UI-free core library: recipes, Hugging Face client, downloads, engine client, gallery, chats |
| `Engine/` | `kiln-engine`, the C++ helper that runs stable-diffusion.cpp |
| `recipes/` | Curated recipe manifests bundled into the app |
| `Tests/` | Unit tests for KilnCore |
| `docs/` | Architecture and recipe reference |
| `scripts/` | Build scripts |
| `Vendor/stable-diffusion.cpp` | Git submodule |

## How it works

- A recipe names the files a model needs on Hugging Face and its default settings.
- `DownloadManager` fetches each missing file into `<file>.partial`, resumes with HTTP `Range` requests, verifies size and SHA-256, then moves the file into place.
- To generate, the app starts `kiln-engine`, a small C++ program linked against stable-diffusion.cpp with the Metal backend. It runs as a separate process, so an engine crash does not take the app down.
- The app and the helper exchange one JSON object per line over stdin and stdout. The helper keeps the model loaded between generations.
- The finished image is written as a PNG into the gallery folder with its settings embedded in text chunks, and the turn is saved to its chat.

Details, including the full helper protocol, are in [docs/architecture.md](docs/architecture.md).

## Add a model recipe

A recipe is one JSON file in `recipes/`: the Hugging Face files to download, the role each one plays, and the recommended settings. A script writes it for you, looking up each file's commit, size and SHA-256 without downloading anything:

```sh
python3 scripts/recipe.py new \
  --id sdxl-base-1.0 \
  --name "Stable Diffusion XL Base 1.0" \
  --component checkpoint=stabilityai/stable-diffusion-xl-base-1.0:sd_xl_base_1.0.safetensors \
  --steps 30 --cfg 7.0 --sampler euler --width 1024 --height 1024 \
  --license-note "CreativeML Open RAIL++-M License." \
  --min-memory-gb 16

python3 scripts/recipe.py check   # verifies every file against Hugging Face
```

You can also import a recipe file from the Models screen with "Import Recipe" without contributing it.

- How to contribute a recipe: [CONTRIBUTING.md](CONTRIBUTING.md)
- Field reference, variants and validation rules: [docs/recipes.md](docs/recipes.md)
- Contributing through an AI coding agent: [AGENTS.md](AGENTS.md)

## Where files are stored

Everything lives under `~/Library/Application Support/Kiln/`:

| Path | Contents |
| --- | --- |
| `models/<owner>/<repo>/<file>` | Downloaded model files |
| `gallery/*.png` | Generated images. Settings are embedded in two text chunks: `parameters` (readable text) and `kiln` (JSON). |
| `chats/<uuid>.json` | Saved chats, one file each |
| `attachments/<uuid>.<ext>` | Copies of images attached to prompts |
| `recipes-remote/<id>.json` | Curated recipes fetched from this repository, at most once a day |
| `recipes/<id>.json` | Recipes you imported, and the single-file recipes created when you download one file from the Hugging Face list |

Kiln talks to two hosts: `huggingface.co` to browse and download models, and `raw.githubusercontent.com` to fetch newly published recipes for this project. Nothing about you or your images is sent anywhere.

The Hugging Face access token is optional and is stored in the macOS Keychain, not in these folders. Deleting a chat does not delete its images or attachments.

## Licence

Kiln is released under the [MIT License](LICENSE). Third-party components and their licences are listed in [THIRD_PARTY.md](THIRD_PARTY.md).

Kiln does not bundle or distribute model weights. Every model has its own licence, and you are responsible for complying with it. For the curated recipes: the Qwen-Image 2.1 denoiser and VAE are under the Qwen Research License (non-commercial), and SDXL Base 1.0 is under the CreativeML Open RAIL++-M License.
