# Kiln

Kiln is a native macOS app that browses Hugging Face text-to-image models, downloads them in one click and generates images locally on Apple Silicon with [stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp) and Metal. Think LM Studio, but for image models.

<!-- demo GIF goes here -->

## Status

Kiln is early. Read this before relying on it.

- End-to-end generation with real model weights has not been verified on this codebase yet. The core library (recipes, memory fit, Hugging Face client, downloads, engine protocol, gallery) is covered by unit tests.
- There are no signed or notarized releases. You build it yourself.
- There is no auto-update.
- Text-to-image only. Video, training and LoRA are not implemented.

## Features

- Search Hugging Face for text-to-image models, most downloaded first.
- Model recipes: one JSON manifest lists every file a model needs and the settings that make it work, so a model is one click to download.
- Resumable downloads that are checked against the size and SHA-256 pinned in the recipe before a file counts as installed.
- A disk-space check before a download starts, and a memory-fit estimate per recipe for the Mac it runs on.
- Local generation through a separate helper process, so an engine crash does not take the app down.
- A gallery of plain PNG files. Each image carries its own prompt and settings.
- Optional Hugging Face access token for gated models, kept in the macOS Keychain and sent only to `huggingface.co`.

Two curated recipes ship with the app: Qwen-Image 2.1 Turbo and Stable Diffusion XL Base 1.0.

## Requirements

- Apple Silicon Mac running macOS 14 or later
- Xcode 16 or later (Swift 6)
- CMake and XcodeGen: `brew install cmake xcodegen`

## Build

```sh
git clone --recursive https://github.com/nomansheikh/kiln.git
cd kiln

# If you cloned without --recursive:
git submodule update --init --recursive

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
| `App/` | SwiftUI app target |
| `Sources/KilnCore/` | Core library: recipes, Hugging Face client, downloads, engine client, gallery |
| `Engine/` | `kiln-engine`, the C++ helper that runs stable-diffusion.cpp |
| `recipes/` | Curated recipe manifests bundled into the app |
| `Tests/` | Unit tests for KilnCore |
| `docs/` | Architecture and recipe reference |
| `scripts/` | Build scripts |
| `Vendor/stable-diffusion.cpp` | Git submodule |

## How it works

- A recipe names the files a model needs on Hugging Face and its default settings.
- `DownloadManager` fetches each missing file into `<file>.partial`, resumes with HTTP `Range` requests, verifies size and SHA-256, then moves the file into place.
- To generate, the app starts `kiln-engine`, a small C++ program linked against stable-diffusion.cpp with the Metal backend.
- The app and the helper exchange one JSON object per line over stdin and stdout. The helper keeps the model loaded between generations.
- The finished image is written as a PNG into the gallery folder with its settings embedded in text chunks.

Details are in [docs/architecture.md](docs/architecture.md).

## Add a model recipe

A recipe is a small JSON file: the Hugging Face files to download, the role each one plays, and the recommended settings. You can import your own from the Models screen with "Import Recipe", or contribute one to the curated set in `recipes/`.

- Field reference and validation rules: [docs/recipes.md](docs/recipes.md)
- How to contribute a recipe: [CONTRIBUTING.md](CONTRIBUTING.md)

## Where files are stored

Everything lives under `~/Library/Application Support/Kiln/`:

| Path | Contents |
| --- | --- |
| `models/<owner>/<repo>/<file>` | Downloaded model files |
| `gallery/` | Generated images as PNG. Settings are embedded in two text chunks: `parameters` (readable text) and `kiln` (JSON). |
| `recipes/` | Recipes you imported |

The Hugging Face access token is optional and is stored in the macOS Keychain, not in these folders.

## License

Kiln is released under the [MIT License](LICENSE). Third-party components and their licenses are listed in [THIRD_PARTY.md](THIRD_PARTY.md).

Kiln does not bundle or distribute model weights. Every model has its own license, and you are responsible for complying with it. For the curated recipes: the Qwen-Image 2.1 denoiser and VAE are under the Qwen Research License (non-commercial), and SDXL Base 1.0 is under the CreativeML Open RAIL++-M License.
