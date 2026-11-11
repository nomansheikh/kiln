# Architecture

Kiln has three parts:

- the **app** (`App/`), a SwiftUI front end
- **KilnCore** (`Sources/KilnCore/`), a UI-free Swift library with the logic that can be tested without a window
- **kiln-engine** (`Engine/`), a C++ helper process that runs stable-diffusion.cpp with the Metal backend

```
+--------------------------- Kiln.app ----------------------------+
|  App/ (SwiftUI)                                                 |
|    Stores      AppModel -> ModelLibrary, GenerationStore,       |
|                GalleryLibrary, ChatLibrary, HubAccount          |
|    Features    Generate, Models (+ Hub), Gallery, Settings      |
|    Shell       window, sidebar, chat list, downloads popover    |
|     |                                                           |
|     v                                                           |
|  KilnCore                                                       |
|    Recipes      RecipeStore, ModelRecipe, MemoryFitEstimator    |
|    HuggingFace  HFClient, KeychainTokenStore  ----HTTPS----> huggingface.co
|    Downloads    DownloadManager, FileDownloader, ModelStorage   |
|    Engine       StableDiffusionCppEngine, HelperProcess         |
|    Gallery      GalleryStore, ImageCodec, PNGText               |
|    Chats        ChatStore, Chat                                 |
+--------|---------------------------^----------------------------+
         | stdin: JSON requests      | stdout: JSON events
         v                           | stderr: logs
+-----------------------------------------------------------------+
|  kiln-engine (separate process)                                 |
|  stable-diffusion.cpp + ggml (Metal)                            |
+-----------------------------------------------------------------+

~/Library/Application Support/Kiln/
    models/<owner>/<repo>/<file>     model files
    recipes/<id>.json                imported and single-file recipes
    gallery/*.png                    generated images
    chats/<uuid>.json                saved chats
    attachments/<uuid>.<ext>         images attached to prompts

<temporary directory>/kiln-engine/
    <uuid>.raw, <uuid>.preview, <uuid>.init    files exchanged with the helper
```

## KilnCore modules

KilnCore has no dependencies outside Apple's frameworks and does not import SwiftUI or AppKit. Network and process boundaries are behind protocols (`HTTPTransport`, `FileDownloading`, `TokenStore`, `InferenceEngine`) so the tests run without the network or model weights. The engine tests drive the real `StableDiffusionCppEngine` against shell scripts that stand in for the helper.

| Module | Main types | Responsibility |
| --- | --- | --- |
| `Recipes/` | `ModelRecipe`, `RecipeStore`, `MemoryFitEstimator` | Recipe schema and validation, loading bundled and user recipes, building a recipe from a Hub file (single-file, or completed from the curated recipe of the same model), memory-fit estimate. See [recipes.md](recipes.md). |
| `HuggingFace/` | `HFClient`, `HFModelSummary`, `HFModelInfo`, `HFFile`, `KeychainTokenStore` | Read-only Hub API client and access-token storage. |
| `Downloads/` | `DownloadManager`, `FileDownloader`, `ModelStorage`, `DownloadStatus`, `TransferRateEstimator` | Download queue, resumable transfers, verification, on-disk layout, speed estimate. |
| `Engine/` | `InferenceEngine`, `StableDiffusionCppEngine`, `HelperProcess`, `EngineMessage` | Generation API, helper process management, wire format. |
| `Gallery/` | `GalleryStore`, `ImageCodec`, `PNGText`, `GenerationRecord` | PNG encoding with embedded settings, reading an image file as raw RGB, listing and deleting images. |
| `Chats/` | `Chat`, `ChatTurn`, `ChatStore` | Saved chats as JSON files. |

### Hugging Face client

`HFClient` uses three endpoints on `https://huggingface.co`:

- `GET /api/models?pipeline_tag=text-to-image&sort=downloads&direction=-1&limit=<n>[&search=<query>]` for search (the limit defaults to 30; an empty query lists the most downloaded models)
- `GET /api/models/<owner>/<repo>?blobs=true` for a repo's files with sizes and SHA-256 checksums
- `GET /api/whoami-v2` to check a token

Files are downloaded from `https://huggingface.co/<repo>/resolve/<revision>/<file>`, with `main` as the revision when a recipe does not pin one.

`HFFile` marks a file as weights when its name ends in `.gguf` or `.safetensors`, and parses a quantization label such as `Q8_0` or `BF16` from the file name for display.

The access token is optional. `KeychainTokenStore` keeps it as a generic password in the login Keychain (service `app.kiln.huggingface`, account `access-token`). `HFClient.authorizationHeader(for:token:)` returns a header only for `https` URLs whose host is exactly `huggingface.co`. `FileDownloader` asks for the header again on every redirect, so the token is not forwarded when a download is redirected to another host.

## The helper process

`kiln-engine` is a single C++ file, [`Engine/main.cpp`](../Engine/main.cpp), linked statically against stable-diffusion.cpp. [`Engine/CMakeLists.txt`](../Engine/CMakeLists.txt) builds it with `SD_METAL=ON` and with examples, WebP and WebM support off. `scripts/build-engine.sh` writes it to `build/engine/kiln-engine`. A post-build script in `project.yml` copies it next to the app's executable (building it first if it is missing) and signs it ad hoc.

### Why a separate process

- **Crash isolation.** A Metal failure, an out-of-memory kill or a bug in the native code ends the helper, not the app. `StableDiffusionCppEngine` reports the failure and starts a fresh helper on the next request.
- **Cancellation that always works.** Loading a model cannot be interrupted from inside the library. If a cancelled job has not stopped within a grace period (3 seconds by default), the app terminates the helper.
- **Releasing memory.** Stopping the helper frees the model and everything the library allocated. This is how "Unload Model" works: `InferenceEngine.shutdown()` terminates the helper, and the next generation starts a new one.
- **A narrow interface.** The app does not link any C or C++ code. The whole contract is the line protocol below.

The helper stays alive between generations so the model stays loaded.

### Process lifecycle

- The helper is launched lazily on the first generation (`HelperProcess.launch`), with pipes for stdin, stdout and stderr.
- At startup it duplicates the real stdout for events and points file descriptor 1 at stderr, so anything a library prints to stdout cannot corrupt the event stream.
- It registers a log callback, and a preview callback that asks the library for a latent-to-RGB projection (`PREVIEW_PROJ`) of the denoised image after every step.
- Library log lines at level info and above go to stderr as `[level] text`. The app keeps the last 40 lines to describe failures and to detect out-of-memory conditions.
- One reader thread parses requests; one worker thread runs generations in order.
- Closing stdin ends the helper. If writing an event fails because the app is gone, the helper exits.

## Helper protocol

One JSON object per line, UTF-8, newline-terminated. Requests go to the helper's stdin, events come back on its stdout. Empty lines are ignored. The Swift side is [`EngineProtocol.swift`](../Sources/KilnCore/Engine/EngineProtocol.swift).

There are two requests (`generate`, `cancel`) and eight events (`ready`, `loading`, `progress`, `preview`, `image`, `cancelled`, `error`, `idle`).

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
    "seed": 42,
    "init_image": "/path/to/source.init",
    "strength": 0.6
  },
  "output": "/path/to/output.raw",
  "preview": "/path/to/output.preview"
}
```

(Formatted here for reading; on the wire it is a single line. The example shows every field; a real request carries only the model roles its recipe has, and `init_image` and `strength` only for image-to-image.)

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
| `init_image` | string | no | Image-to-image. Path of a file holding the source image as raw 8-bit RGB, row by row, exactly `width * height * 3` bytes, no header. A file of any other size (including one that cannot be read) is an `invalid_request` error. |
| `strength` | number | no | Read only when `init_image` is set. How far the result may move from the source image: 0 keeps it, 1 ignores it. When absent, the library's default is used. |

The scheduler is always the library's default for the loaded model and sampler. The batch size is always 1.

`output` (string, required) is the path the helper writes the result to: raw 8-bit pixels, row by row, `width * height * channels` bytes, with no header.

`preview` (string, optional) is a path the helper overwrites with a rough picture after each step, in the same raw format. Each frame is written to `<preview>.tmp` and renamed, so the app never reads half a frame. When the field is missing or empty, no previews are written. Models for which the library has no latent projection produce no previews.

The app keeps these files in a `kiln-engine` folder inside the temporary directory, named after the job: `<uuid>.raw` (output), `<uuid>.preview` and, for image-to-image, `<uuid>.init`. Before sending the request, the app writes `<uuid>.init` itself: `ImageCodec.rgbPixels` scales the attached image to fill the output size, crops it around its centre and fills transparent areas with white. The output file is deleted once it has been read; the preview and init files are deleted when the job ends.

#### `cancel`

```json
{"type":"cancel"}
```

Marks the current work as cancelled and, if sampling is in progress, asks the library to stop. A cancel that arrives while the model is loading takes effect once loading finishes. The next `generate` request clears the cancelled flag.

### Events

#### `ready`

Sent once at startup with the stable-diffusion.cpp version and commit.

```json
{"type":"ready","version":"<version>","commit":"<commit>"}
```

#### `loading`

The requested model is not the loaded one; loading has started. No fields.

```json
{"type":"loading"}
```

#### `progress`

Progress reported by the library. `stage` and `detail` are strings, `completed` and `total` integers. `total` is 0 when unknown.

```json
{"type":"progress","stage":"sampling","detail":"","completed":3,"total":8}
```

#### `preview`

A step preview was written to `path` (the `preview` path of the request). `step` is the step number; `width`, `height` and `channels` describe the raw pixels in the file, which is usually much smaller than the final image (the numbers below are only an illustration). Only single-frame previews are sent.

```json
{"type":"preview","path":"/path/to/output.preview","step":3,"width":128,"height":128,"channels":3}
```

#### `image`

The final raw pixels were written to `path` (the `output` path of the request).

```json
{"type":"image","path":"/path/to/output.raw","width":1024,"height":1024,"channels":3}
```

#### `cancelled`

The job was cancelled. No fields.

```json
{"type":"cancelled"}
```

#### `error`

The request failed. `code` is one of the values below; `message` is a short description.

```json
{"type":"error","code":"load_failed","message":"The model could not be loaded."}
```

| `code` | When |
| --- | --- |
| `invalid_request` | The line is not a JSON object, the `type` is unknown, a required field is missing or has the wrong type, the sampler name is unknown, or the `init_image` file does not match the requested size. |
| `load_failed` | stable-diffusion.cpp could not create a context from the model files. |
| `generation_failed` | The library returned no image. |
| `write_failed` | The pixels could not be written to `output`. |

#### `idle`

The worker finished a `generate` request, whatever its outcome. No fields.

```json
{"type":"idle"}
```

#### Order of events

Every `generate` request produces: `loading` if the model has to be loaded, any number of `progress` and `preview` events, then at most one of `image`, `cancelled` or `error`, then exactly one `idle`.

An `invalid_request` for an unparsable line or unknown `type` is not followed by `idle`, because no job was queued.

### How the app interprets events

- `ready` is ignored.
- `loading` becomes `GenerationEvent.loadingModel`.
- `progress` becomes `GenerationEvent.progress`. The stage names `preparing`, `conditioning`, `sampling` and `vae_decode` map to preparing, encoding the prompt, sampling and decoding; any other name is passed through. The `detail` field is not used.
- `preview`: the app reads the file and yields `GenerationEvent.preview`. The `step` field is not used. A preview whose file cannot be read or does not hold `width * height * channels` bytes is skipped; it never fails the job.
- `image`: the app checks that the file holds exactly `width * height * channels` bytes (with 1, 3 or 4 channels), yields `GenerationEvent.finished` and ends the stream. Otherwise the job fails with an "invalid output" error.
- `cancelled` ends the stream with a cancellation error.
- `error`: `load_failed` becomes a model-load error; other codes become a generation error. If the recent log mentions memory exhaustion, the error is reported as out of memory instead.
- `idle` for a job that produced no image, error or cancellation is reported as a generation failure.
- Lines that are not a known event, or an `image` or `preview` event without its fields, are ignored, so a newer helper can add event types.
- If the helper exits during a job, the result is a cancellation (when cancel was requested), out of memory (when the log says so) or a crash error with the last log lines.

The app runs one generation at a time. A second request while one is active fails with a "busy" error. Before starting, the engine checks that the recipe's `engine` is `sd.cpp`, that every component file exists, and, for image-to-image, that the source image can be read.

## Download flow

`DownloadManager` is an actor that runs one recipe at a time; further recipes wait in a queue. For each recipe it downloads the components that are not installed yet, in the order the recipe lists them. A file picked from a Hugging Face repo goes through the same path: the app first turns it into a single-file recipe (`ModelRecipe.singleFile`), saves that recipe to the user recipes folder, and starts it like any other.

### On-disk layout

`ModelStorage` maps a component to `<root>/<owner>/<repo>/<file>`, with `~/Library/Application Support/Kiln/models` as the default root. A file appears at its final path only after it was fully downloaded and verified, so "the file exists" means "installed". Deleting a model removes its files, partial files and sidecars, except files another installed recipe also uses, and removes directories left empty. The recipe itself stays in the list.

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
- **Cancel** stops the transfer, deletes the `.partial` and `.source` files of the components that are not installed, and removes the entry. Files that already finished are kept.
- **Failure** (network error, HTTP error) leaves the partial file in place, so starting the recipe again resumes. A verification failure removes it.
- **Clear** forgets a finished or failed entry without touching files.

Status per recipe is one of queued, downloading, verifying, paused, completed or failed, with bytes received, total bytes (when every component has a size) and the current file. `DownloadManager.updates()` streams the full status table on every change. Transfer progress is reported at most every 0.1 seconds.

### Speed and time left

`TransferRateEstimator` averages the bytes received over a sliding window (8 seconds by default). It gives no speed until its samples span at least one second, or while no bytes are arriving, and starts over when the byte count drops. In the app, `ModelLibrary` keeps one estimator per transferring download and publishes a `DownloadSpeed` (bytes per second and, when the total size is known, seconds remaining) at most once a second.

## Chats, attachments and gallery storage

There is no database. Each of the three folders is its own source of truth.

### Gallery

Generated images are PNG files in one folder, `~/Library/Application Support/Kiln/gallery/` by default. Each PNG carries its own settings.

- **File name:** a timestamp of the creation date followed by the first eight characters of the record's UUID, with the extension `.png`.
- **Pixels:** the raw 8-bit output of the helper (1, 3 or 4 channels) encoded with ImageIO.
- **Metadata:** two uncompressed `iTXt` chunks inserted right after the `IHDR` chunk:

| Keyword | Contents |
| --- | --- |
| `parameters` | Readable text in the layout other Stable Diffusion tools read: the prompt, an optional `Negative prompt:` line, then `Steps`, `Sampler`, `CFG scale`, `Seed`, `Size` and `Model`. |
| `kiln` | The full `GenerationRecord` as JSON: `id`, `createdAt` (ISO 8601), `recipeID`, `recipeName`, `durationSeconds` (when known) and `request` with the prompt, negative prompt, width, height, steps, cfg, sampler, sigmas and seed, plus `sourceImage` and `strength` for image-to-image. |

The chunks are written and read directly by `PNGText`, because ImageIO does not round-trip arbitrary PNG text.

Listing the gallery reads only the chunks before the pixel data of each `.png` file. A PNG without a readable `kiln` chunk is not shown. Items are sorted newest first by `createdAt`. Deleting an item deletes its file.

"Reuse Settings" reads the record back into the Generate screen: the prompt, negative prompt, size, steps, cfg, sampler and exact seed, and the recipe if it is still known. It does not restore an attached image.

### Chats

`ChatStore` keeps one JSON file per chat, `chats/<uuid>.json`, so a damaged file costs one chat at most. Files that cannot be decoded are skipped. Chats are listed most recently updated first.

A `Chat` has an `id`, a `title`, `createdAt`, `updatedAt`, an `isArchived` flag and a list of turns. The title defaults to the first prompt, shortened to a single line of about 48 characters. A `ChatTurn` stores the prompt, the requested width and height, an optional `attachmentFileName`, and an outcome:

- `image`: the file name of the result inside the gallery folder
- `failed`: the error message
- `cancelled`

A turn does not copy the image or its settings; it points at the gallery file by name. When a chat is opened and the file is no longer in the gallery, the turn is shown as failed with "This image is no longer in the Gallery." A turn that is still running is saved as cancelled, which is what it will be if the app quits before it finishes.

The chat is created when its first prompt is sent and saved again when each turn ends. Deleting a chat removes its JSON file only; its images stay in the gallery.

### Attachments

`AttachmentLibrary` (in `App/Stores/`) copies every attached image into `attachments/<uuid>.<ext>`, so a chat keeps its picture after the original file is moved or deleted. A file is accepted when ImageIO can open it. Chat turns refer to the copy by file name. Kiln does not currently delete attachment copies.

## The app layer

The app target is `App/`. It contains no engine, network or file-format logic of its own beyond what the stores need to connect KilnCore to views.

```
App/
  KilnApp.swift     scene, menu commands, debug launch arguments
  Stores/           observable state, one store per feature
  Features/         Generate/, Models/ (+ Hub/), Gallery/, Settings/
  Shell/            window, sidebar, chat list, Downloads/
  DesignSystem/     Theme, Motion, button styles, shared small views
  Support/          AppDelegate, KeyboardNavigationMonitor, DebugSnapshot
```

### Stores

`AppModel` is the root. It is created once in `KilnApp`, injected into the environment, and owns one `@MainActor @Observable` store per feature plus the current sidebar selection. It also holds the few actions that touch more than one store (open a chat, delete a chat, reuse an image's settings, delete a gallery item, use a model).

| Store | Owns |
| --- | --- |
| `ModelLibrary` | Recipes and recipe load problems, the set of installed recipes, download statuses and speeds; import, download of a file from the Hub, delete. Wraps `RecipeStore`, `ModelStorage`, `DownloadManager`, `HFClient` and `MemoryFitEstimator`. |
| `GenerationStore` | The draft being edited (`GenerationDraft`), the thread on screen (`GenerationTurn`), the running phase and step preview, and which recipe is loaded in memory. Runs generations through `InferenceEngine`, saves results to the gallery and the thread to its chat. |
| `GalleryLibrary` | The gallery items; add, delete, copy to the pasteboard, reveal in Finder. Wraps `GalleryStore`. |
| `ChatLibrary` | The saved chats; save, rename, archive, delete. Wraps `ChatStore`. |
| `HubAccount` | Whether a token is saved; save, remove, verify. Wraps `TokenStore` and `HFClient`. |

Smaller value types live beside them: `GenerationDraft` and `GenerationPhase`, `GenerationTurn`, `EditStrength` (Subtle 0.35, Balanced 0.6, Strong 0.8, sent as `strength`), `DownloadSpeed`, `SidebarItem` and `AttachmentLibrary`.

Some behaviour worth knowing when reading `GenerationStore`:

- Selecting a recipe applies its recommended size, steps, cfg and sampler to the draft.
- A recipe's `sigmas` are sent only when the draft's step count equals the recipe's default step count, because the schedule fits no other count.
- The seed is random per generation unless the user turns that off.
- "Generate again" reruns a turn's prompt and attachment with the current settings.
- The loaded-model indicator is tracked in the app: it is set when the first progress event arrives and cleared on unload or after a failed run.

### Features

Each screen has a folder under `App/Features/` with one primary view per file.

- **Generate:** the thread (`GenerationThread`, `GenerationTurnView`), the composer (`PromptComposer`) with attachment, size menu and advanced settings, the progress placeholder that shows step previews (`GenerationPlaceholder`), and the actions under a finished image.
- **Models:** recipe cards with download controls and the memory-fit label, the "Import Recipe" button, and under `Hub/` the Hugging Face list and search. `HubSearchModel` is a view-local observable that holds the debounced search and the file lists of opened repos.
- **Gallery:** the grid, the detail panel and the item actions.
- **Settings:** cards for the Hugging Face token, hardware, storage folders and app information.

### Shell

`ContentView` places a floating sidebar beside the selected screen. The sidebar holds the navigation rows, the chat list (`ChatList`, `ChatRow`, with archived chats under a toggle) and, while there is anything to show, the downloads button (`Shell/Downloads/`), whose popover lists each download with its progress, speed, time left and controls.

`AppDelegate` quits the app when its last window closes, unless a generation or download is running. The helper exits with the app.

### Design system

`App/DesignSystem/` holds what more than one feature uses: `Theme` (colours, radii, widths), `Motion` (animations and transitions that fall back to fades under Reduce Motion), button styles, the card modifier, and small views such as `Pill`, `FitLabel`, `Thumbnail`, `ScreenHeader` and `RoundIconButton`.

### Debug launch arguments

Debug builds accept `--snapshot <folder>`, which saves a PNG of each screen and quits. See [CONTRIBUTING.md](../CONTRIBUTING.md#screenshots-for-a-pull-request).
