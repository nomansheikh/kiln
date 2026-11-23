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
| `engine` | string | yes | Inference engine: `sd.cpp` (stable-diffusion.cpp, makes images), `whisper.cpp` (speech to text), `audio.cpp` (text to speech) or `trellis.cpp` (3D objects from a picture). |
| `components` | array of [component](#components) | yes | Files to download. At least one, unless the recipe has [variants](#variants), in which case these are the files shared by every variant and the array may be empty. The key must be present either way. |
| `output` | string | no | What the model produces: `image`, `audio`, `text` or `mesh` (a 3D object). `image` when absent. See [kinds](#kinds-of-model). |
| `accepts` | array of strings | no | Kinds of file the model takes as an attachment, from the same values. See [kinds](#kinds-of-model). |
| `defaults` | [defaults](#defaults) object | for image models | Recommended generation settings of an image model. Required when `output` is `image`. |
| `speech` | object | for audio.cpp | How a model that speaks is run: `family`, and optionally `voices` and `voice`. See [speech](#speech). |
| `languages` | array of strings | no | Codes of the languages the user may choose between, such as `en`, for a speech model that works in several. The app offers them in a language menu with "Auto" first. Leave it out for a model that works in one language or decides by itself. |
| `license_note` | string | no | Short, human-readable summary of the model's licence terms. |
| `min_memory_gb` | number | no | Smallest amount of system RAM the recipe is expected to run on. |
| `base_model` | string | no | Hugging Face repo of the original model the `diffusion_model` file was made from, for example `black-forest-labs/FLUX.1-dev`. Lets files from other repos of the same model run with this recipe. See [family recipes](#family-recipes). |
| `variants` | array of [variant](#variants) | no | Alternative sets of files for the same model, usually different quantizations. |

A recipe with an `engine` Kiln does not include still loads, but generating with it fails with an "unsupported engine" error.

### Kinds of model

`output` and `accepts` describe what goes in and what comes out. The app derives the Generate screen from them: the composer offers an attach button only for the kinds in `accepts` and shows size and step controls only for image models, and the model menu groups models by `output` once more than one kind is installed.

| `output` | `accepts` when absent | Can run without a prompt |
| --- | --- | --- |
| `image` | `["image"]`, an image to rework | No |
| `audio`, `text` | `[]`, no attachment | When it takes an attachment and one is attached, as speech to text does |
| `mesh` | `[]`; a curated recipe states `["image"]` | Only with a picture attached. The 3D screen runs these models, not Generate. |

Each engine makes one kind, and a curated recipe must state it:

| `engine` | `output` | `accepts` | `defaults` | Components |
| --- | --- | --- | --- | --- |
| `sd.cpp` | `image` (or absent) | absent | required | the roles in [Roles](#roles) |
| `whisper.cpp` | `text` | `["audio"]` | not allowed | one `model` file in whisper.cpp's ggml format |
| `audio.cpp` | `audio` | absent | not allowed | one `model` file in audio.cpp's GGUF format, any number of `voice` files, and `speech` |
| `trellis.cpp` | `mesh` | `["image"]` | not allowed | one `model` file and the model's other files as `support`, each under the name trellis.cpp opens it by. See [3D models](#3d-models). |

A speech-to-text recipe looks like this:

```json
{
  "$schema": "./schema.json",
  "id": "whisper-large-v3-turbo",
  "name": "Whisper Large v3 Turbo",
  "engine": "whisper.cpp",
  "components": [],
  "output": "text",
  "accepts": ["audio"],
  "variants": [ … one `model` file each … ]
}
```

In the app, the user attaches an audio file and sends it, with or without a prompt. The prompt, if any, is given to the model as words to expect (names, jargon); it is not an instruction.

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

Each role may appear at most once in a list of components, except `voice` and `support`. Any other value is rejected when the file is decoded.

| `role` | Meaning | Key in the helper's `model` object | stable-diffusion.cpp context parameter |
| --- | --- | --- | --- |
| `checkpoint` | A single-file checkpoint that carries everything (SD 1.x, SDXL) | `checkpoint` | `model_path` |
| `diffusion_model` | A standalone denoiser | `diffusion_model` | `diffusion_model_path` |
| `llm` | A language model used as the text encoder (Qwen-Image and similar) | `llm` | `llm_path` |
| `vae` | A standalone VAE | `vae` | `vae_path` |
| `clip_l` | CLIP-L text encoder (Flux and SD3 families) | `clip_l` | `clip_l_path` |
| `clip_g` | CLIP-G text encoder (SD3 family) | `clip_g` | `clip_g_path` |
| `t5xxl` | T5-XXL text encoder (Flux and SD3 families) | `t5xxl` | `t5xxl_path` |
| `model` | The main file of a model whose engine needs no other kind of file. Used by `whisper.cpp`, `audio.cpp` and `trellis.cpp` recipes, not by `sd.cpp`. | (the `model` field of `transcribe` and `speak`) | none |
| `voice` | A voice a speech model can speak in, named after the file. Used by `audio.cpp` recipes. May repeat. | (found by the engine beside the model file) | none |
| `support` | Another file the engine finds beside the model, such as a tokenizer or a configuration. Used by `audio.cpp` and `trellis.cpp`. May repeat; no two may share a path. | (found by the engine beside the model file) | none |

Roles a recipe does not use are left unset. There is no role for a LoRA or a vision projector, so a model that needs one of those cannot be described yet. The mapping lives in `generateCommand` in [`EngineProtocol.swift`](../Sources/KilnCore/Engine/EngineProtocol.swift) and `load_model` in [`Engine/main.cpp`](../Engine/main.cpp).

To decide which roles a model needs, read its page under [`Vendor/stable-diffusion.cpp/docs/`](https://github.com/leejet/stable-diffusion.cpp/tree/master/docs) (for example `flux.md`, `sd3.md`, `qwen_image.md`). The command lines there use the flags `-m`, `--diffusion-model`, `--llm`, `--vae`, `--clip_l`, `--clip_g` and `--t5xxl`, which correspond to the first seven roles in the order of the table.

## Speech

A recipe for the `audio.cpp` engine has a `speech` object:

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `family` | string | yes | audio.cpp's name for the kind of model, for example `pocket_tts`. It must be one of the families compiled into the helper (`AUDIOCPP_MODELS` in `Engine/audio/CMakeLists.txt`). |
| `voices` | array of strings | no | Names of voices built into the model file. Leave it out when the voices are separate files. |
| `voice` | string | no | The voice used until the user picks one. The first voice when absent. |
| `instruction` | string | no | `optional` when the model takes a free description of the voice or the delivery, such as "Very happy."; `required` when it cannot speak without one. Leave it out for a model that takes none. |
| `styles` | array of objects | no | For a model that takes fixed words instead of a free description: groups of `{"name", "options"}`, such as `{"name": "Age", "options": ["child", "elderly"]}`. The user may choose one word per group. Cannot be combined with `instruction`. |
| `tags` | array of strings | no | Marks the model understands inside the text, written as they are typed, such as `[laughter]`. |
| `reference` | string | no | `optional` when the model can speak in a voice copied from a recording; `required` when it has no voice of its own and cannot speak without one. Leave it out for a model that cannot copy a voice. |
| `reference_text` | string | no | `optional` or `required`: whether the model also wants the words spoken in that recording. Needs `reference`. |
| `speakers` | object | no | For a model that reads a whole script in one take: `max`, the most speakers one text may have, and `line`, one speaker's turn as the model reads it. See [Several speakers](#several-speakers). |

Voices come from one of two places. A model with voices inside its file lists them in `speech.voices`. A model that loads each voice from its own file lists those files as components with the role `voice`; each is a voice named after its file, so `embeddings/alba.safetensors` is the voice `alba`. `voice` is the only role that may appear more than once, and no two voice files may share a name.

`family` and every voice name may use only letters, digits, dots, dashes and underscores, and may not start with a dot: the engine builds a file path from a voice name.

#### Copying a voice

A recipe with `reference` lets the user speak in a voice of their own. The Speech screen's voice list gets a "My voices" section and "Add a voice…", which saves a recording with a name and, optionally, the words spoken in it, in `~/Library/Application Support/Kiln/voices`. A chosen voice of the user's own takes the place of the model's named voice: the app decodes the first fifteen seconds of the recording to mono at 24 kHz and hands the samples to the helper, with the words as audio.cpp's `reference_text` option when the recipe has `reference_text`.

The sheet can write the words itself by running an installed speech-to-text model on exactly the part of the recording that is used.

Set `reference_text` to `required` when the model refuses a recording without its words; the app then says so before sending. A recipe needs no named voices when it says another way the model gets a voice: copying one (`reference`), a description (`instruction` or `styles`), or a script's speakers (`speakers`).

A voice can also be designed. "Design a voice…" asks an installed model that can make up a voice (one with `styles`, or with `instruction` set to `required`) to speak a sample from a description, and saves the sample with its words as one of the user's voices. Any model with `reference` can then speak in it.

#### Several speakers

The user can write any text as a script. A line that starts with a short name and a colon (`Anna: Did you hear that?`) begins that speaker's turn, the lines after it belong to the same turn, and text before the first name is spoken by "Speaker 1". A note in brackets after the name says how the turn is said: `Anna (whispering): …`. The names are the user's to choose. A text is a script once it has more than one speaker; the app then colours the names and lists the speakers under the composer's "Speakers" chip, where each is given a voice.

How a script is read depends on the recipe:

- **Without `speakers`**, which is most models, the app reads the script turn by turn, each turn as a request of its own in its speaker's voice, and joins the sound with a quarter of a second between turns. A speaker keeps the voice chosen for them. Otherwise they get the model's voice of the same name, or the model's named voices in turn. A model with no named voices needs a voice of the user's own for every speaker, because it would make up a new one for each line; the app says which speakers are missing one. A turn's note is sent as the instruction for that turn to a model with `instruction`, and added to the chosen words for a model with `styles`.
- **With `speakers`**, the model reads the whole script in one take:

  ```json
  "speakers": { "max": 4, "line": "Speaker {n}: {text}" }
  ```

  Each turn is rewritten with `line`: `{n}` becomes the speaker's number, counted from 1, and `{text}` what they say, one turn per line. So `Anna: Hi.` followed by `Ben: Yo.` reaches VibeVoice as `Speaker 1: Hi.` and `Speaker 2: Yo.`. Take `line` and `max` from the model's page in `Vendor/audio.cpp/docs/`. A text with more speakers than `max` is not sent, and notes are left out. When the recipe also has `reference`, the recordings of the speakers' voices are handed over as WAV files named in audio.cpp's `voice_samples` option, in the order of the speakers' numbers. A model takes recordings for its first speakers only, so the speakers with a voice are numbered before the ones without. `reference_text` is not used.

#### Expression

Models differ in how a voice can be directed, so a recipe states what its model takes and the Speech screen shows only those controls:

- `instruction`: a Style chip opens a field for a free description. The text is sent to the engine as its `instruct` option.
- `styles`: the Style chip is a menu of the listed words, one per group. The chosen words are sent as `instruct`, joined with commas, in the recipe's order. Words the recipe does not list are never sent.
- `tags`: a Sounds menu adds a tag where the cursor is. A tag can also be typed anywhere in the text.

A mark can be written the same way for every model: one word in square or angle brackets, such as `[laughs]`. Before the text is sent, `SpeechMarks` rewrites it to the model's own tag when the recipe lists one that is the same word (`[laughs]` becomes `[laughter]` or `<laugh>`), and leaves it out otherwise, because a model that does not know a mark reads the word aloud. Brackets around anything else (`[1]`, `[citation needed]`, `[S1]`) are ordinary text. The saved clip keeps the text as it was written. On the Speech screen a mark the model has is shown in the accent colour, and one that will be left out is struck through and named under the text.

Take every value from the model's page in `Vendor/audio.cpp/docs/models/`, its source under `Vendor/audio.cpp/src/models/` or its model card. A model that only follows an instruction together with a template or a reference recording has none of these fields: Kiln does not pass those yet.

Each voice has its own licence, which may differ from the model's. Include only voices whose source states a licence, and name each source in `license_note`.

```json
{
  "id": "pocket-tts-english",
  "name": "PocketTTS English",
  "engine": "audio.cpp",
  "output": "audio",
  "speech": { "family": "pocket_tts", "voice": "alba" },
  "components": [
    { "role": "voice", "repo": "audio-cpp/audio.cpp-gguf", "file": "PocketTTS-GGUF/english/embeddings/alba.safetensors", … }
  ],
  "variants": [ … one `model` file each … ]
}
```

## 3D models

A recipe for the `trellis.cpp` engine makes a 3D object from one picture. It has no settings block: the settings are the engine's own, the same for every model, and the user changes them on the 3D screen.

trellis.cpp opens every file by a fixed name inside one folder, so the names of a recipe's files are part of the recipe:

| File name | What it is |
| --- | --- |
| `ss_flow.gguf` | The flow that lays out the rough structure. Give it the role `model`. |
| `shape_flow_512.gguf`, `shape_flow_1024.gguf` | The flows that work out the shape. |
| `tex_flow_512.gguf`, `tex_flow_1024.gguf` | The flows that colour it. |
| `ss_dec.gguf`, `shape_dec.gguf`, `tex_dec.gguf` | The decoders. |
| `dinov3.gguf` | The image encoder. |
| `birefnet.gguf` | The background remover. |

Every file but the first has the role `support`. The files may sit in a folder of a repo (`q4/ss_flow.gguf`): only the last part of the path is the name. They may also come from several repos, in which case the app links them into one folder when it runs the model, so no two may have the same name.

The app reads two things from the names, and a recipe has no field for either:

- **The family.** A recipe whose `model` file is named with the `pixal3d_` prefix is run as Pixal3D, a fine-tune of TRELLIS.2 whose flow files carry that prefix (`pixal3d_ss_flow.gguf` and so on, plus `pixal3d_naf.gguf`); its decoders, image encoder and background remover are TRELLIS.2's, under their plain names. Any other recipe is run as TRELLIS.2.
- **The levels of detail.** Standard (512) is offered only when the recipe has a `tex_flow_512.gguf`. Pixal3D publishes none, so it starts at Fine (1024).

```sh
python3 scripts/recipe.py new \
  --id trellis-2 --name "TRELLIS.2" --engine trellis.cpp \
  --variant q4 "Q4 (smallest)" min_memory_gb=16 \
    model=ilintar/trellis2-gguf:q4/ss_flow.gguf \
    support=ilintar/trellis2-gguf:q4/shape_flow_512.gguf \
    ... \
  --license-note "..."
```

The script writes `"output": "mesh"` and `"accepts": ["image"]` itself and rejects the image settings. State the licence of every part in `license_note`: the model, the decoders it reuses, the background remover and the image encoder each have their own.

## The catalogue

Not every model has a recipe. `catalog/` holds entries generated by `scripts/catalog.py` from what the engines' own projects publish:

| File | Generated from | Entries |
| --- | --- | --- |
| `catalog/audio.cpp.json` | `Vendor/audio.cpp/model_specs/`, audio.cpp's list of the models it runs and where their files are, with licences from its `docs/model_licenses.md` | Text-to-speech models |
| `catalog/whisper.cpp.json` | The files of the `ggerganov/whisper.cpp` repo on Hugging Face | Whisper models |

Each file is `{"source": …, "recipes": [ … ]}`, and each entry is a recipe in every respect: the same fields, every file pinned to a commit and size, and a SHA-256 for every file large enough for the Hub to hash. What differs is where it comes from. Nobody ran it, so the app lists these under "More models" with a note saying so, and an entry may fail to load or need a setting Kiln does not offer, such as a reference recording of a voice.

How the app treats them (`RecipeStore+Catalog.swift`):

- A curated recipe wins. An entry is dropped when a curated recipe downloads the same main file, and an entry with variants loses only the variants that are covered.
- An entry this version cannot read or that fails validation is skipped without an error.
- Entries sort after curated recipes and before the user's own.

What the generator leaves out, and why: model families that need eSpeak (GPL-3.0, not shipped); families audio.cpp marks `experimental`, `testing` or `wip`; packages that are not GGUF; models split over several weight files, which the helper does not load yet; and packages that are a part for another setup rather than a model.

Run `python3 scripts/catalog.py` after updating a vendored engine and commit the result. `--check` fails when the committed files differ from what would be generated; it is not part of CI, because the Hub's `main` moves independently of this repository.

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
4. No two components share a `role`, except `voice` and `support`; no two `voice` files share a name and no two `support` files share a path.

Each component:

5. `repo` is exactly two non-empty parts separated by one `/`, and neither part is `.` or `..`.
6. `file` is not empty, contains no backslash, and no path segment is empty, `.` or `..`. This rules out absolute paths, `//` and anything that would escape the model folder.
7. `sha256`, when present, is exactly 64 hexadecimal characters.
8. `size_bytes`, when present, is greater than zero.

Defaults:

9. An image recipe (no `output`, or `output` set to `image`) has `defaults`. For any recipe that has them:
   `steps` is greater than zero.
10. `cfg` is not negative.
11. `sampler` is not empty.
12. `width` and `height` are greater than zero.
13. `sigmas`, when present, has exactly `steps + 1` values.

Speech (these rules are not numbered, so the numbers below stay as they were):

- A recipe whose `output` is `audio` has `speech` with a `family`.
- `family` and every voice name are safe names (see [speech](#speech)).
- `speech.voices`, when present, is not empty and has no repeats.
- `speech.instruction`, when present, is `optional` or `required`.
- `speech.styles`, when present, has named groups, each with at least one word; no word repeats or contains a comma; and `instruction` is absent.
- `speech.reference` and `speech.reference_text`, when present, are `optional` or `required`, and `reference_text` is only given with `reference`.
- `speech.speakers`, when present, has a `max` of at least 2 and a `line` that contains `{n}` and `{text}`.
- A curated speech recipe has at least one voice, or `speech.reference` set to `required`.
- `speech.tags`, when present, is not empty, has no repeats, and every tag is one line of at most 40 characters.

Languages: `languages`, when present, is not empty, has no repeats, and every entry is 2 to 12 letters, dashes or underscores.

Each variant:

14. `id` follows rule 1 and is unique within the recipe; `name` follows rule 2.
15. `components` has at least one entry, no two share a `role`, and each follows rules 5 to 8.
16. The merged list (shared components with this variant's files replacing those of the same role) has no duplicate role.

Decoding adds the structural checks: every required field must be present with the right type, `role` must be one of the values above, and `output` and `accepts` may hold only `image`, `audio` and `text`. Unknown extra fields are ignored by the app, which is why `$schema` is safe, and also why a misspelt optional field goes unnoticed; `scripts/recipe.py check` reports unknown fields for that reason.

`index.json` and `schema.json` are reserved file names. The app does not load them as recipes.

When recipes are loaded, a recipe whose `id` was already seen is skipped as a duplicate. Bundled recipes are read before user recipes, so a curated recipe wins over a user recipe with the same id. Within a folder, files are read in file-name order.

Files that fail to decode or validate, and skipped duplicates, do not stop the others from loading. The Models screen lists them in a "recipes could not be loaded" card with the file name and the reason.

### Extra rules for curated recipes

Two things check every file in `recipes/` on each push: the test `everyCuratedRecipeIsValid` in [`ModelRecipeTests.swift`](../Tests/KilnCoreTests/ModelRecipeTests.swift), and `python3 scripts/recipe.py check` in CI.

The test requires:

- the file name without `.json` equals the recipe `id`
- `engine` is `sd.cpp`, `whisper.cpp`, `audio.cpp` or `trellis.cpp`
- every component of every variant (or of the recipe, when it has no variants) has `revision`, `size_bytes` and `sha256`
- `recipes/index.json` lists exactly the recipe files

The script requires all of that, and also:

- `revision` is a full 40-character commit sha, not a branch name
- the file exists on Hugging Face at that revision, with that size and that SHA-256
- `sampler` and `scheduler` are names the vendored stable-diffusion.cpp accepts
- `base_model`, when set, is the model the Hub tags every `diffusion_model` repo of the recipe as made from (or is that repo itself), and the recipe has a `diffusion_model` component
- `output`, `accepts` and `defaults` match the engine, as in the table under [kinds](#kinds-of-model)
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
| `--engine NAME` | `sd.cpp` (the default), `whisper.cpp`, `audio.cpp` or `trellis.cpp`. For the last three the script writes `output` (and `accepts`) itself and takes none of the image settings below. |
| `--instruction optional\|required`, `--style NAME=WORD,WORD`, `--tags TAG ...` | For `audio.cpp`: `speech.instruction`, one group of `speech.styles` (repeat for each group) and `speech.tags`. See [Expression](#expression). |
| `--reference optional\|required`, `--reference-text optional\|required` | For `audio.cpp`: `speech.reference` and `speech.reference_text`. See [Copying a voice](#copying-a-voice). |
| `--speakers MAX`, `--speaker-line LINE` | For `audio.cpp`: `speech.speakers`, given together. See [Several speakers](#several-speakers). |
| `--family NAME`, `--voice NAME`, `--voices NAME ...` | For `audio.cpp`: `speech.family` (required), `speech.voice` and `speech.voices`. Voice files are given as `--component voice=OWNER/REPO:PATH`, once per voice. |
| `--steps`, `--cfg`, `--sampler`, `--width`, `--height` | The defaults, required for an image recipe. There are no built-in values: take them from the model card. |
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

The script cannot pin a file the Hub has no SHA-256 for (a file not stored with Git LFS). Model weights are stored with LFS, so this only happens when the path points at something else. The app does not download a file without a checksum, so a recipe written by hand must give `sha256` for every file.

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
