# Architecture

Kiln has three parts:

- the **app** (`App/`), a SwiftUI front end
- **KilnCore** (`Sources/KilnCore/`), a UI-free Swift library with all the logic
- **kiln-engine** (`Engine/`), a C++ helper process that runs stable-diffusion.cpp with the Metal backend

```
+--------------------------- Kiln.app ----------------------------+
|  App/ (SwiftUI)                                                 |
|     |                                                           |
|     v                                                           |
|  KilnCore                                                       |
|    Recipes      RecipeStore, ModelRecipe, MemoryFitEstimator    |
|    HuggingFace  HFClient, KeychainTokenStore  ----HTTPS----> huggingface.co
|    Downloads    DownloadManager, FileDownloader, ModelStorage   |
|    Engine       StableDiffusionCppEngine                        |
|    Gallery      GalleryStore, ImageCodec                        |
+--------|---------------------------^----------------------------+
         | stdin: JSON requests      | stdout: JSON events
         v                           | stderr: logs
+-----------------------------------------------------------------+
|  kiln-engine (separate process)                                 |
|  stable-diffusion.cpp + ggml (Metal)                            |
+-----------------------------------------------------------------+

~/Library/Application Support/Kiln/
    models/<owner>/<repo>/<file>     model files
    recipes/<id>.json                imported recipes
    gallery/*.png                    generated images
```

## KilnCore modules

KilnCore has no dependencies outside Apple's frameworks and does not import any UI framework. Network and process boundaries are behind protocols (`HTTPTransport`, `FileDownloading`, `TokenStore`, `InferenceEngine`) so the tests run without the network or model weights.

| Module | Main types | Responsibility |
| --- | --- | --- |
| `Recipes/` | `ModelRecipe`, `RecipeStore`, `MemoryFitEstimator` | Recipe schema and validation, loading bundled and imported recipes, memory-fit estimate. See [recipes.md](recipes.md). |
| `HuggingFace/` | `HFClient`, `HFModelSummary`, `HFModelInfo`, `HFFile`, `KeychainTokenStore` | Read-only Hub API client and access-token storage. |
| `Downloads/` | `DownloadManager`, `FileDownloader`, `ModelStorage` | Download queue, resumable transfers, verification, on-disk layout. |
| `Engine/` | `InferenceEngine`, `StableDiffusionCppEngine`, `EngineMessage` | Generation API, helper process management, wire format. |
| `Gallery/` | `GalleryStore`, `ImageCodec`, `GenerationRecord` | PNG encoding with embedded settings, listing and deleting images. |

### Hugging Face client

`HFClient` uses three endpoints on `https://huggingface.co`:

- `GET /api/models?pipeline_tag=text-to-image&sort=downloads&direction=-1&limit=<n>[&search=<query>]` for search
- `GET /api/models/<owner>/<repo>?blobs=true` for a repo's files with sizes and SHA-256 checksums
- `GET /api/whoami-v2` to check a token

Files are downloaded from `https://huggingface.co/<repo>/resolve/<revision>/<file>`, with `main` as the revision when a recipe does not pin one.

The access token is optional. `KeychainTokenStore` keeps it as a generic password in the login Keychain (service `app.kiln.huggingface`, account `access-token`). `HFClient.authorizationHeader(for:token:)` returns a header only for `https` URLs whose host is exactly `huggingface.co`. `FileDownloader` asks for the header again on every redirect, so the token is not forwarded when a download is redirected to another host.

## The helper process

`kiln-engine` is a single C++ file, [`Engine/main.cpp`](../Engine/main.cpp), linked statically against stable-diffusion.cpp. [`Engine/CMakeLists.txt`](../Engine/CMakeLists.txt) builds it with `SD_METAL=ON` and with examples, WebP and WebM support off. `scripts/build-engine.sh` writes it to `build/engine/kiln-engine`.

### Why a separate process

- **Crash isolation.** A Metal failure, an out-of-memory kill or a bug in the native code ends the helper, not the app. `StableDiffusionCppEngine` reports the failure and starts a fresh helper on the next request.
- **Cancellation that always works.** Loading a model cannot be interrupted from inside the library. If a cancelled job has not stopped within a grace period (3 seconds by default), the app terminates the helper.
- **Releasing memory.** Stopping the helper frees the model and everything the library allocated.
- **A narrow interface.** The app does not link any C or C++ code. The whole contract is the line protocol below.

The helper stays alive between generations so the model stays loaded.

### Process lifecycle

- The helper is launched lazily on the first generation, with pipes for stdin, stdout and stderr.
- At startup it duplicates the real stdout for events and points file descriptor 1 at stderr, so anything a library prints to stdout cannot corrupt the event stream.
- Library log lines at level info and above go to stderr as `[level] text`. The app keeps the last 40 lines to describe failures and to detect out-of-memory conditions.
- One reader thread parses requests; one worker thread runs generations in order.
- Closing stdin ends the helper. If writing an event fails because the app is gone, the helper exits.

## Helper protocol

One JSON object per line, UTF-8, newline-terminated. Requests go to the helper's stdin, events come back on its stdout. Empty lines are ignored. The Swift side is [`EngineProtocol.swift`](../Sources/KilnCore/Engine/EngineProtocol.swift).

### Requests

#### `generate`

```json
{
  "type": "generate",
  "model": {
    "checkpoint": "/path/to/checkpoint.safetensors",
    "diffusion_model": "/path/to/denoiser.gguf",
    "llm": "/path/to/text-encoder.gguf",
    "vae": "/path/to/vae.safetensors",
    "flash_attention": false
  },
  "params": {
    "prompt": "a lighthouse at dusk",
    "negative_prompt": "",
    "width": 1024,
    "height": 1024,
    "steps": 8,
    "cfg": 1.0,
    "sampler": "euler",
    "sigmas": [1.0, 0.5, 0.0],
    "seed": 42
  },
  "output": "/path/to/output.raw"
}
```

(Formatted here for reading; on the wire it is a single line.)

`model`:

| Key | Type | Maps to (`sd_ctx_params_t`) | Notes |
| --- | --- | --- | --- |
| `checkpoint` | string | `model_path` | Optional. Absolute path. |
| `diffusion_model` | string | `diffusion_model_path` | Optional. |
| `llm` | string | `llm_path` | Optional. |
| `vae` | string | `vae_path` | Optional. |
| `flash_attention` | boolean | `diffusion_flash_attn` | Defaults to `false`. |

A missing or empty path is left unset. The app sends only the roles the recipe has. The helper keeps one model loaded and compares the whole `model` object with the one it loaded last; if they differ it frees the old context and loads the new one. The app encodes the object with sorted keys so the same recipe always produces the same object.

`params`:

| Key | Type | Required | Notes |
| --- | --- | --- | --- |
| `prompt` | string | no | Defaults to empty. |
| `negative_prompt` | string | no | Defaults to empty. |
| `width`, `height` | integer | yes | Pixels. |
| `steps` | integer | yes | Sampling steps. |
| `cfg` | number | yes | Text guidance scale. |
| `seed` | integer | yes | 64-bit signed. |
| `sampler` | string | no | stable-diffusion.cpp sample method name. When missing or empty, the library's default for the loaded model is used. An unknown name is an `invalid_request` error. |
| `sigmas` | array of numbers | no | Custom sigma schedule. When missing or empty, the default schedule is used. |

The scheduler is always the library's default for the loaded model and sampler. The batch size is always 1.

`output` (string, required) is the path the helper writes the result to: raw 8-bit pixels, row by row, `width * height * channels` bytes, with no header. The app passes a file named `<uuid>.raw` in a `kiln-engine` folder inside the temporary directory, reads it when the `image` event arrives, and deletes it.

#### `cancel`

```json
{"type":"cancel"}
```

Marks the current work as cancelled and, if sampling is in progress, asks the library to stop. A cancel that arrives while the model is loading takes effect once loading finishes. The next `generate` request clears the cancelled flag.

### Events

| `type` | Fields | Meaning |
| --- | --- | --- |
| `ready` | `version`, `commit` (strings) | Sent once at startup with the stable-diffusion.cpp version and commit. |
| `loading` | none | The requested model is not the loaded one; loading has started. |
| `progress` | `stage`, `detail` (strings), `completed`, `total` (integers) | Progress reported by the library. `total` is 0 when unknown. |
| `image` | `path` (string), `width`, `height`, `channels` (integers) | The raw pixels were written to `path`. |
| `cancelled` | none | The job was cancelled. |
| `error` | `code`, `message` (strings) | The request failed. |
| `idle` | none | The worker finished a `generate` request, whatever its outcome. |

Every `generate` request produces: `loading` if the model has to be loaded, any number of `progress` events, then at most one of `image`, `cancelled` or `error`, then exactly one `idle`.

Error codes:

| `code` | When |
| --- | --- |
| `invalid_request` | The line is not a JSON object, the `type` is unknown, a required field is missing or has the wrong type, or the sampler name is unknown. |
| `load_failed` | stable-diffusion.cpp could not create a context from the model files. |
| `generation_failed` | The library returned no image. |
| `write_failed` | The pixels could not be written to `output`. |

An `invalid_request` for an unparsable line or unknown `type` is not followed by `idle`, because no job was queued.

### How the app interprets events

- `ready` is ignored.
- `loading` becomes `GenerationEvent.loadingModel`.
- `progress` becomes `GenerationEvent.progress`. The stage names `preparing`, `conditioning`, `sampling` and `vae_decode` map to preparing, encoding the prompt, sampling and decoding; any other name is passed through. The `detail` field is not used.
- `image`: the app checks that the file holds exactly `width * height * channels` bytes, yields `GenerationEvent.finished` and ends the stream.
- `cancelled` ends the stream with a cancellation error.
- `error`: `load_failed` becomes a model-load error; other codes become a generation error. If the recent log mentions memory exhaustion, the error is reported as out of memory instead.
- `idle` for a job that produced no image, error or cancellation is reported as a generation failure.
- Lines that are not a known event are ignored, so a newer helper can add event types.
- If the helper exits during a job, the result is a cancellation (when cancel was requested), out of memory (when the log says so) or a crash error with the last log lines.

The app runs one generation at a time. A second request while one is active fails with a "busy" error. Before starting, the engine checks that the recipe's `engine` is `sd.cpp` and that every component file exists.

## Download flow

`DownloadManager` is an actor that runs one recipe at a time; further recipes wait in a queue. For each recipe it downloads the components that are not installed yet, in the order the recipe lists them.

### On-disk layout

`ModelStorage` maps a component to `<root>/<owner>/<repo>/<file>`, with `~/Library/Application Support/Kiln/models` as the default root. A file appears at its final path only after it was fully downloaded and verified, so "the file exists" means "installed". Deleting a recipe removes its files, partial files and sidecars, except files another recipe also uses, and removes directories left empty.

While a file is downloading there are two extra files next to its destination:

| File | Contents |
| --- | --- |
| `<file>.partial` | The bytes received so far. |
| `<file>.source` | The URL the partial file is being downloaded from. |

### Steps

1. **Disk-space check.** Before any transfer, the manager sums, over the missing components, `size_bytes` minus the size of any existing `.partial` file. It compares that with the volume's available capacity (queried on the closest existing parent of the models folder) and fails with "not enough disk space" if it does not fit. Components without `size_bytes` count as zero.
2. **Decide whether to resume.** `FileDownloader` reads the `.source` sidecar. If it does not match the URL being requested, or the `.partial` file is larger than the expected size, the partial file is deleted. The sidecar is then rewritten with the current URL. Pinning a different `revision` changes the URL, so a partial file from another commit is never continued.
3. **Transfer.** If a `.partial` file exists, the request carries `Range: bytes=<size>-`.
   - `206`: the response is appended to the partial file.
   - `200`: the server ignored the range; the partial file is truncated and the download starts over.
   - `416`: the server has nothing beyond the offset. If the partial file already has the expected size, it is treated as complete. Otherwise it is deleted and the download is retried once from the start.
   - `401` or `403`: fails with an access-denied error that points at the model's terms and the access token.
   - Any other status fails with an HTTP error.
4. **Verify.** In this order: first the size against `size_bytes`, then the SHA-256 against `sha256`. Each check is skipped if the recipe does not give the value. The hash is computed by streaming the file in 4 MB chunks. On a mismatch, the `.partial` and `.source` files are deleted and the download fails.
5. **Install.** The `.partial` file is moved to the final path, replacing any existing file, and the `.source` sidecar is removed.

### Pause, cancel and failure

- **Pause** stops the transfer and keeps the `.partial` and `.source` files. Starting the recipe again resumes from where it stopped.
- **Cancel** stops the transfer and deletes the `.partial` and `.source` files of the components that are not installed. Files that already finished are kept.
- **Failure** (network error, HTTP error) leaves the partial file in place, so starting the recipe again resumes. A verification failure removes it.

Status per recipe is one of queued, downloading, verifying, paused, completed or failed, with bytes received, total bytes (when every component has a size) and the current file. `DownloadManager.updates()` streams the full status table on every change. Transfer progress is reported at most every 0.1 seconds.

## Gallery storage

Generated images are PNG files in one folder, `~/Library/Application Support/Kiln/gallery/` by default. There is no database: the folder is the only source of truth, and each PNG carries its own settings.

- **File name:** a timestamp of the creation date followed by the first eight characters of the record's UUID, with the extension `.png`.
- **Pixels:** the raw 8-bit output of the helper (1, 3 or 4 channels) encoded with ImageIO.
- **Metadata:** two uncompressed `iTXt` chunks inserted right after the `IHDR` chunk:

| Keyword | Contents |
| --- | --- |
| `parameters` | Readable text in the layout other Stable Diffusion tools read: the prompt, an optional `Negative prompt:` line, then `Steps`, `Sampler`, `CFG scale`, `Seed`, `Size` and `Model`. |
| `kiln` | The full `GenerationRecord` as JSON: `id`, `createdAt` (ISO 8601), `recipeID`, `recipeName`, `durationSeconds` (when known) and `request` with the prompt, negative prompt, width, height, steps, cfg, sampler, sigmas and seed. |

The chunks are written and read directly by `PNGText`, because ImageIO does not round-trip arbitrary PNG text.

Listing the gallery reads only the chunks before the pixel data of each `.png` file. A PNG without a readable `kiln` chunk is not shown. Items are sorted newest first by `createdAt`. Deleting an item deletes its file.
