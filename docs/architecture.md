# Architecture

Kiln has three parts:

- the **app** (`App/`), a SwiftUI front end
- **KilnCore** (`Sources/KilnCore/`), a UI-free Swift library with the logic that can be tested without a window
- **kiln-engine** (`Engine/`), a C++ helper process that runs stable-diffusion.cpp with the Metal backend and makes images
- **kiln-whisper** (`Engine/whisper/`), a second helper process that runs whisper.cpp and turns speech into text
- **kiln-audio** (`Engine/audio/`), a third helper process that runs audio.cpp and turns text into speech

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
|    Engine       EngineRouter, HelperSession, and one engine     |
|                 class per helper                                |
|    Audio        GeneratedAudio, AudioStore                      |
|    Gallery      GalleryStore, ImageCodec, PNGText               |
|    Files        UserFile                                        |
|    Chats        ChatStore, Chat                                 |
|    Updates      ReleaseCheck, AppVersion  ----HTTPS----> api.github.com
+--------|---------------------------^----------------------------+
         | stdin: JSON requests      | stdout: JSON events
         v                           | stderr: logs
+-----------------------------------------------------------------+
|  Three separate helper processes, each with its own ggml:      |
|  kiln-engine   stable-diffusion.cpp   images                    |
|  kiln-whisper  whisper.cpp            speech to text            |
|  kiln-audio    audio.cpp              text to speech            |
+-----------------------------------------------------------------+

~/Library/Application Support/Kiln/
    models/<owner>/<repo>/<file>     model files
    recipes/<id>.json                imported and single-file recipes
    gallery/*.png                    generated images
    audio/*.wav, *.json              generated sound, each with its settings
    chats/<uuid>.json                saved chats
    attachments/<uuid>[-<name>].<ext>   files attached to prompts

<temporary directory>/kiln-engine/
    <uuid>.raw, <uuid>.preview, <uuid>.init    files exchanged with kiln-engine
<temporary directory>/kiln-whisper/
    <uuid>.f32, <uuid>.txt                     files exchanged with kiln-whisper
<temporary directory>/kiln-audio/
    <uuid>.f32                                 file exchanged with kiln-audio
```

## KilnCore modules

KilnCore has no dependencies outside Apple's frameworks and does not import SwiftUI or AppKit. Network and process boundaries are behind protocols (`HTTPTransport`, `FileDownloading`, `TokenStore`, `InferenceEngine`) so the tests run without the network or model weights. The engine tests drive the real `StableDiffusionCppEngine` against shell scripts that stand in for the helper.

| Module | Main types | Responsibility |
| --- | --- | --- |
| `Recipes/` | `ModelRecipe`, `RecipeStore`, `MemoryFitEstimator` | Recipe schema and validation, loading bundled and user recipes and the generated catalogue of models without a recipe, building a recipe from a Hub file (single-file, or completed from the curated recipe of the same model), memory-fit estimate. See [recipes.md](recipes.md). |
| `HuggingFace/` | `HFClient`, `HFModelSummary`, `HFModelInfo`, `HFFile`, `KeychainTokenStore` | Read-only Hub API client and access-token storage. |
| `Downloads/` | `DownloadManager`, `FileDownloader`, `ModelStorage`, `DownloadStatus`, `TransferRateEstimator` | Download queue, resumable transfers, verification, on-disk layout, speed estimate. |
| `Engine/` | `InferenceEngine`, `GenerationRequest`, `EngineRouter`, `HelperSession`, `StableDiffusionCppEngine`, `WhisperCppEngine`, `AudioCppEngine`, `AudioSamples`, `HelperProcess`, `EngineMessage` | Generation API, routing each recipe to its engine, helper process management, decoding audio for speech models, wire format. |
| `Audio/` | `GeneratedAudio`, `AudioStore`, `AudioItem` | Sound a model made, WAV encoding, saving and listing sounds with their settings. |
| `Gallery/` | `GalleryStore`, `ImageCodec`, `PNGText`, `GenerationRecord` | Saving outputs (PNG encoding with embedded settings for images), reading an image file as raw RGB, listing and deleting items. |
| `Files/` | `UserFile` | Deleting something the user made (a clip, a voice, an image) moves it to the Trash, so it can be put back from the Finder. Each move and each saved clip is written to the system log under the subsystem `codes.noman.kiln`, category `files`. |
| `Chats/` | `Chat`, `ChatTurn`, `ChatStore` | Saved chats as JSON files. |
| `Updates/` | `ReleaseCheck`, `PublishedRelease`, `AppVersion` | Asking GitHub for the latest release of Kiln and comparing its version with the running app's. See [New versions](#new-versions). |

### Hugging Face client

`HFClient` uses three endpoints on `https://huggingface.co`:

- `GET /api/models?pipeline_tag=text-to-image&sort=downloads&direction=-1&limit=<n>[&search=<query>]` for search (the limit defaults to 30; an empty query lists the most downloaded models)
- `GET /api/models/<owner>/<repo>?blobs=true` for a repo's files with sizes and SHA-256 checksums
- `GET /api/models/<owner>/<repo>` for one repo's summary. A search that is a repo id (`owner/name`) or a link to a repo page asks for that repo first and puts it at the top of the results, so a model outside the text-to-image list can be found by its id
- `GET /api/whoami-v2` to check a token

Files are downloaded from `https://huggingface.co/<repo>/resolve/<revision>/<file>`, with `main` as the revision when a recipe does not pin one.

`HFFile` marks a file as weights when its name ends in `.gguf` or `.safetensors`, and parses a quantization label such as `Q8_0` or `BF16` from the file name for display.

The access token is optional. `KeychainTokenStore` keeps it as a generic password in the login Keychain (service `app.kiln.huggingface`, account `access-token`). `HFClient.authorizationHeader(for:token:)` returns a header only for `https` URLs whose host is exactly `huggingface.co`. `FileDownloader` asks for the header again on every redirect, so the token is not forwarded when a download is redirected to another host.

### Engines and kinds

A recipe's `output` and `accepts` fields say what kind of content the model makes and takes (image, audio or text; see [recipes.md](recipes.md#kinds-of-model)). A `GenerationRequest` has the parts every kind shares, the prompt and an optional attachment, plus the settings of its kind, `image` for an image model. A finished generation yields a `GenerationOutput`: an image, which the gallery saves; text, which is kept in the chat turn; or audio, which `AudioStore` saves.

The app talks to one `InferenceEngine`, an `EngineRouter` that sends each recipe to the engine named by its `engine` field. Three are registered: `sd.cpp` (`StableDiffusionCppEngine`, images), `whisper.cpp` (`WhisperCppEngine`, speech to text) and `audio.cpp` (`AudioCppEngine`, text to speech).

Each engine class prepares the files and the command for one job and hands them to a `HelperSession`, which owns the helper process: launching it, reading its events and log, cancelling, classifying a crash, and removing the job's scratch files. An engine only interprets the events that are its own, such as a finished image. Before it starts an engine other than the one used last, the router shuts the previous one down, so only one model is in memory at a time. "Unload from Memory" shuts down every engine.

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
- It is started with `--sandbox <models folder> <scratch folder>` and a short list of environment variables instead of the app's own. The first thing a helper does is enter a sandbox built from those two folders ([`Engine/sandbox.h`](../Engine/sandbox.h), shared by the three helpers): no network, no new processes, no reading under `/Users` or `/Volumes` outside the models and scratch folders, no writing outside the scratch folder and the system's per-user cache. A helper that cannot enter it exits. Run by hand without the argument, a helper is not confined. [SECURITY.md](../SECURITY.md) states what this does and does not protect.
- Every file a helper is given or asked to write is in the engine's scratch folder, which is why the sandbox can be that narrow: the app decodes attached audio and images itself and writes them there. `HelperSession` reads a result only from a file that belongs to the job; an event naming another file fails the job and stops the helper (a preview naming one is skipped).
- At startup it duplicates the real stdout for events and points file descriptor 1 at stderr, so anything a library prints to stdout cannot corrupt the event stream.
- It registers a log callback, and a preview callback that asks the library for a latent-to-RGB projection (`PREVIEW_PROJ`) of the denoised image after every step.
- Library log lines at level info and above go to stderr as `[level] text`. The app keeps the last 40 lines to describe failures and to detect out-of-memory conditions.
- One reader thread parses requests; one worker thread runs generations in order.
- Closing stdin ends the helper. If writing an event fails because the app is gone, the helper exits.
- An `error` event and the log line that explains it travel through different pipes, so the error can arrive first. `HelperSession` then waits up to three quarters of a second for a line that explains it before reporting the failure, and reports it at once when the reason is already there.

## The speech helper

`kiln-whisper` is [`Engine/whisper/main.cpp`](../Engine/whisper/main.cpp), linked statically against whisper.cpp (`Vendor/whisper.cpp`, a submodule pinned to a release tag) with Metal on and its examples, tests and server off. It is a separate program from `kiln-engine` because both libraries bundle their own copy of ggml, which cannot be linked into one binary. `scripts/build-engine.sh` builds both helpers and the post-build script bundles and signs both.

It follows the same lifecycle and line protocol as `kiln-engine`, with one request of its own:

```json
{"type":"transcribe","model":"/…/ggml-large-v3-turbo.bin","audio":"/tmp/kiln-whisper/<uuid>.f32","prompt":"","language":"auto","output":"/tmp/kiln-whisper/<uuid>.txt"}
```

| Field | Meaning |
| --- | --- |
| `model` | Path of the model file. The helper keeps it loaded and reloads only when the path changes. |
| `audio` | File of raw 32-bit little-endian float samples, mono, 16 kHz. The app decodes the attached file with AVFoundation (`AudioSamples`), so the helper needs no audio codecs. |
| `prompt` | Optional words to expect, such as names. Passed to whisper.cpp as the initial prompt. |
| `language` | Code of the spoken language, or `auto` to detect it. |
| `output` | File the helper writes the transcript to, as UTF-8. |

Timestamps are not produced. The language is detected unless the user picks one: a recipe's `languages` field lists what the model supports, the composer offers them in a menu with "Auto" first, and an engine passes the choice on only when the recipe lists it. `kiln-audio`'s `speak` request takes the same optional `language` field. Events are `ready`, `loading`, `progress` (stage `transcribing`, `completed` out of 100), then one of `text` (`{"type":"text","path":…}`), `cancelled` or `error`, then `idle`. `cancel` sets a flag that whisper.cpp's abort callback reads.

`WhisperCppEngine` requires an attachment (`missingAudio` otherwise), writes the samples and reads the transcript in its scratch folder, and removes both files when the job ends. A file AVFoundation cannot decode fails with `unreadableAudio` before the helper is started.

## The text-to-speech helper

`kiln-audio` is [`Engine/audio/main.cpp`](../Engine/audio/main.cpp), linked statically against audio.cpp (`Vendor/audio.cpp`, a submodule pinned to a release tag) with Metal on. [`Engine/audio/CMakeLists.txt`](../Engine/audio/CMakeLists.txt) compiles in every model family audio.cpp supports, so that any model in the catalogue can run, compiles the model descriptions into the binary so it needs no files beside it, and builds for any Apple Silicon chip rather than the build machine's. audio.cpp offers its C interface only as a shared library, so the helper compiles that one source file (`src/capi/audiocpp.cpp`) into itself. With every family compiled in the helper is about 38 MB, against 7 MB with one.

It has one request:

```json
{"type":"speak","model":"/…/pocket-tts-english-bf16.gguf","family":"pocket_tts","text":"Hello.","voice":"alba","backend":"metal","output":"/tmp/kiln-audio/<uuid>.f32"}
```

| Field | Meaning |
| --- | --- |
| `model` | Path of the model file. The helper keeps it loaded and reloads only when the path or family changes. |
| `family` | audio.cpp's name for the kind of model, from the recipe's `speech.family`. |
| `text` | What to say. |
| `voice` | A voice name. Some models have voices built in; PocketTTS loads `embeddings/<voice>.safetensors` beside the model file, which is where the recipe's `voice` files are stored. |
| `voice_audio`, `voice_sample_rate` | Optional. A recording of the voice to speak in, as a file of raw mono 32-bit floats, and its sample rate. It takes the place of `voice`. The helper then opens the model for audio.cpp's `clon` task when the model has one, and for `tts` otherwise; switching between the two reloads the model. The app sends it only for a recipe with `speech.reference`. |
| `language` | A language code, when the user chose one. Absent lets the model decide. |
| `options` | Optional object of settings by the names audio.cpp gives them, each a string. The app sends `{"reference_text": "…"}` with a voice recording for a recipe that has `speech.reference_text`, and `{"instruct": "…"}` for a recipe whose model takes a description of the voice (`speech.instruction`) or fixed style words (`speech.styles`), and never for another. For a recipe with `speech.speakers` it sends `{"voice_samples": "…"}`, the paths of one WAV file per speaker with a voice, separated by commas, and the `text` is the script rewritten in the model's spelling (see `SpeechScript`). A script for any other recipe never reaches the helper whole: `InferenceEngine.speak` splits it with `SpeechCast` into one `speak` command per turn and joins the sound. |
| `backend` | `metal` for the GPU (the default) or `cpu`. Changing it reloads the model. |
| `output` | File the helper writes the sound to, as raw interleaved 32-bit floats. |

Events are `ready`, `loading`, `progress` (stage `speaking`, no measurable total), then `audio` (`{"type":"audio","path":…,"sample_rate":24000,"channels":1,"frames":…}`) or `error`, then `idle`. audio.cpp cannot stop a run in progress, so `cancel` is accepted and ignored: a cancelled job ends for the app at once, and the helper is killed only if the run has not finished within the grace period.

Not every audio.cpp model works on Metal yet: Soprano, for one, brings the helper down on the GPU and runs correctly on the CPU. So when the helper crashes during a GPU run, `AudioCppEngine` runs the same request once more with `"backend":"cpu"`, and keeps that model on the CPU for as long as the app is open. A crash on the CPU is reported as a crash.

`AudioCppEngine` refuses an empty text (`missingText`) and a voice the recipe does not list (`unknownVoice`), checks that the output file holds exactly `frames * channels` floats, and yields a `GeneratedAudio`. Recipe validation restricts `speech.family` and voice names to letters, digits, dots, dashes and underscores, because the engine builds a file path from a voice name.

## Helper protocol

The protocol of `kiln-engine`. One JSON object per line, UTF-8, newline-terminated. Requests go to the helper's stdin, events come back on its stdout. Empty lines are ignored. The Swift side is [`EngineProtocol.swift`](../Sources/KilnCore/Engine/EngineProtocol.swift).

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

## New versions

Kiln has no updater. It only tells the user that a newer version exists, so that a fix reaches people who installed from a disk image.

- **The request.** `ReleaseCheck` sends `GET https://api.github.com/repos/nomansheikh/kiln/releases/latest` with the headers `Accept: application/vnd.github+json` and `User-Agent: Kiln`, no token and no body. It reads `tag_name`, `html_url`, `draft` and `prerelease` from the answer and nothing else.
- **What counts as a release.** A draft or a prerelease is ignored. So is a tag that is not a version, and a release whose page is not an `https` address on `github.com` (`PublishedRelease`), because that page is what the notice opens in the browser.
- **Versions.** `AppVersion` is dotted numbers with an optional leading `v`, compared number by number: `0.10.0` is newer than `0.9.2`, and `0.1` equals `0.1.0`. Anything else, such as `0.2.0-beta`, does not parse.
- **How often.** At most once every 24 hours (`ReleaseCheck.isDue`). `UpdateStore` (in `App/Stores/`) checks at launch and looks again every hour while the app is open. The time of the last successful check is kept in `UserDefaults` (`updates.checkedAt`), next to the recipe catalogue's. A failed check (offline, rate limited, no release published yet, an unreadable answer) shows nothing and is tried again a day later or at the next launch.
- **The notice.** When the latest release is newer than `CFBundleShortVersionString`, the sidebar shows `UpdateNotice` above the downloads button: the version, "View release", which opens the release page, and a button that hides the notice for that version (`updates.dismissedVersion`). The latest version found is kept in `UserDefaults` too, so the notice is still there after a relaunch on the same day. Nothing is downloaded or installed.
- **The setting.** "Check for new versions" in Settings, under About, turns the request and the notice off (`updates.checkEnabled`, on by default).

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
| `kiln` | The full `GenerationRecord` as JSON: `id`, `createdAt` (ISO 8601), `recipeID`, `recipeName`, `durationSeconds` (when known) and `request`. The request holds the `prompt`, the `attachment` (image-to-image) and `image`: negative prompt, width, height, steps, cfg, sampler, sigmas, seed and, with an attachment, strength. Images saved before requests had kinds keep these settings at the top level of `request` and call the attachment `sourceImage`; `GenerationRequest` reads both layouts. |

The chunks are written and read directly by `PNGText`, because ImageIO does not round-trip arbitrary PNG text.

Listing the gallery reads only the chunks before the pixel data of each `.png` file. A PNG without a readable `kiln` chunk is not shown. Items are sorted newest first by `createdAt`. Deleting an item deletes its file.

"Reuse Settings" reads the record back into the Generate screen: the prompt, negative prompt, size, steps, cfg, sampler and exact seed, and the recipe if it is still known. It does not restore an attached image.

### Audio

Generated sound is a 16-bit PCM WAV file in `~/Library/Application Support/Kiln/audio/`, named like a gallery image. A WAV file has no place for settings, so `AudioStore` writes a JSON file of the same name beside it with the `GenerationRecord` and the sound's length. A WAV without a readable JSON file is not listed. Deleting an item deletes both files.

### Chats

`ChatStore` keeps one JSON file per chat, `chats/<uuid>.json`, so a damaged file costs one chat at most. Files that cannot be decoded are skipped. Chats are listed most recently updated first.

A `Chat` has an `id`, a `title`, `createdAt`, `updatedAt`, an `isArchived` flag and a list of turns. The title defaults to the first prompt, shortened to a single line of about 48 characters. A `ChatTurn` stores the prompt, the requested width and height (for an image; absent for other kinds), an optional `attachmentFileName`, and an outcome:

- `image`: the file name of the result inside the gallery folder
- `text`: the text the model wrote, such as a transcript, stored in the chat itself
- `audio`: the file name of the sound inside the audio folder
- `failed`: the error message
- `cancelled`

A turn also stores its `kind` (what it asked the model to make; image when absent).

A turn does not copy the image or its settings; it points at the gallery file by name. When a chat is opened and the file is no longer in the gallery, the turn is shown as failed with "This image is no longer in the Gallery." A turn that is still running is saved as cancelled, which is what it will be if the app quits before it finishes.

The chat is created when its first prompt is sent and saved again when each turn ends. Deleting a chat removes its JSON file only; its images stay in the gallery.

### Attachments

`AttachmentLibrary` (in `App/Stores/`) copies every attached file into `attachments/`, so a chat keeps it after the original file is moved or deleted. An image is stored as `<uuid>.<ext>`; any other file as `<uuid>-<original name>.<ext>`, because it is shown in the thread by name. A file is accepted only as one of the kinds in the selected recipe's `accepts`: an image when ImageIO can open it, another kind when its file type conforms to that kind. Switching to a model that cannot take the attached file removes the attachment from the draft. Chat turns refer to the copy by file name. Kiln does not currently delete attachment copies.

## The app layer

The app target is `App/`. It contains no engine, network or file-format logic of its own beyond what the stores need to connect KilnCore to views.

```
App/
  KilnApp.swift     scene, menu commands, debug launch arguments
  Stores/           observable state, one store per feature
  Features/         Generate/, Speech/, Models/ (+ Hub/), Gallery/, Settings/
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
| `SpeechStore` | The Speech screen: the text, the voice model and voice, what a running generation is doing, the clip being played, each clip's waveform, the playback speed and voice samples. Runs text to speech through `InferenceEngine` and saves results to `AudioLibrary`. |
| `AudioLibrary` | Generated sound; add, delete, reveal in Finder. Wraps `AudioStore`. |
| `GalleryLibrary` | The gallery items; add, delete, copy to the pasteboard, reveal in Finder. Wraps `GalleryStore`. |
| `ChatLibrary` | The saved chats; save, rename, archive, delete. Wraps `ChatStore`. |
| `HubAccount` | Whether a token is saved; save, remove, verify. Wraps `TokenStore` and `HFClient`. |
| `UpdateStore` | Whether a newer version of Kiln exists, the version the user dismissed, and the setting that turns the check off. Wraps `ReleaseCheck`. |

Smaller value types live beside them: `GenerationDraft` and `GenerationPhase`, `GenerationTurn`, `EditStrength` (Subtle 0.35, Balanced 0.6, Strong 0.8, sent as `strength`), `DownloadSpeed`, `SidebarItem` and `AttachmentLibrary`.

The engines hold one model in memory, so only one screen generates at a time: `GenerationStore` and `SpeechStore` each refuse to start while the other is busy (`isEngineBusyElsewhere`, wired in `AppModel`). The Generate menu's commands act on the screen in front.

Some behaviour worth knowing when reading `GenerationStore`:

- Selecting a recipe applies its recommended size, steps, cfg and sampler to the draft.
- A recipe's `sigmas` are sent only when the draft's step count equals the recipe's default step count, because the schedule fits no other count.
- The seed is random per generation unless the user turns that off.
- "Generate again" reruns a turn's prompt and attachment with the current settings.
- The loaded-model indicator is tracked in the app: it is set when the first progress event arrives and cleared on unload or after a failed run.

### Features

Each screen has a folder under `App/Features/` with one primary view per file.

- **Generate:** the thread (`GenerationThread`, `GenerationTurnView`), the composer (`PromptComposer`) with attachment, size menu and advanced settings, the progress placeholder that shows step previews (`GenerationPlaceholder`), and the actions under a finished image.
- **Speech:** a screen for text to speech, laid out like Generate: the model capsule (`SpeechModelMenu`), a centred greeting and composer with starter texts while there are no clips, then the composer at the top with every clip under it, newest first (`SpeechClipList`). Sending empties the composer (`SpeechComposer`), as in a chat; the text comes back if the clip fails or is stopped, and any clip's text can be put back with "Use this text again". Its chips choose the voice (`SpeechVoiceChip`, opening `SpeechVoiceList`) and the playback speed. Each clip is a card (`SpeechClipCard`) with a play button, a waveform to scrub through (`WaveformView`, drawn from `AudioWaveform.peaks`), the text it was made from and its actions; the clip being made is a `SpeechWorkingCard`. A new clip plays as soon as it is ready. In the voice list each voice has a play button: the first time, a short sample is generated and kept in `~/Library/Caches/Kiln/voice-samples/`, so later auditions are instant. Speech models can also be used from the chat thread; both write to the same audio folder.
- **Models:** recipe cards with download controls and the memory-fit label, a "More models" section for the catalogue (folded until opened, with a note that its entries are untested), a search field that filters Kiln's own models by name before showing Hugging Face results, the "Import Recipe" button, and under `Hub/` the Hugging Face list and search. `HubSearchModel` is a view-local observable that holds the debounced search and the file lists of opened repos.
- **Gallery:** the grid, the detail panel and the item actions.
- **Settings:** cards for the Hugging Face token, hardware, storage folders and app information, which holds the switch for the check for new versions.

### Shell

`ContentView` places a floating sidebar beside the selected screen. The sidebar holds the navigation rows, the chat list (`ChatList`, `ChatRow`, with archived chats under a toggle), the notice of a new version (`UpdateNotice`) when there is one and, while there is anything to show, the downloads button (`Shell/Downloads/`), whose popover lists each download with its progress, speed, time left and controls.

`AppDelegate` quits the app when its last window closes, unless a generation or download is running. The helper exits with the app.

### Design system

`App/DesignSystem/` holds what more than one feature uses: `Theme` (colours, radii, widths), `Motion` (animations and transitions that fall back to fades under Reduce Motion), button styles, the card modifier, and small views such as `Pill`, `FitLabel`, `Thumbnail`, `ScreenHeader` and `RoundIconButton`.

### Debug launch arguments

Debug builds accept `--snapshot <folder>`, which saves a PNG of each screen and quits. See [CONTRIBUTING.md](../CONTRIBUTING.md#screenshots-for-a-pull-request).
