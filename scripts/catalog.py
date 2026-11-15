#!/usr/bin/env python3
"""Generates catalog/: models Kiln can run that nobody wrote a recipe for.

A recipe in recipes/ is written and checked by a person. The catalogue is
generated from what the engines' own projects publish, so that a model does
not need a hand-written recipe to be downloadable:

  catalog/audio.cpp.json    from Vendor/audio.cpp/model_specs/, audio.cpp's
                            list of every model it runs and where its files are
  catalog/whisper.cpp.json  from the files in the ggerganov/whisper.cpp repo

Every file is pinned to a commit, size and SHA-256 looked up on Hugging Face,
exactly as in a recipe. Nothing is downloaded. Entries are not tested: the app
shows them apart from the recipes and says so.

Usage: python3 scripts/catalog.py            regenerate both files
       python3 scripts/catalog.py --check    fail if the files are out of date

Standard library only; works on Python 3.9.
"""

import argparse
import glob
import hashlib
import importlib.util
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
AUDIOCPP = os.path.join(ROOT, "Vendor", "audio.cpp")
OUTPUT = os.path.join(ROOT, "catalog")

# Families that turn text into phonemes with eSpeak-ng, which is GPL-3.0 and is
# not compiled into kiln-audio. Listed in Vendor/audio.cpp/docs/espeak_phonemizer.md
# and on each family's page under docs/models/.
NEEDS_ESPEAK = {"inflect_v2", "kitten_tts", "kokoro_tts", "piper_tts", "sanotts", "zipvoice"}

# Packages that are a part for another setup rather than a model that runs by itself.
NOT_STANDALONE = {
    "vocos_mel_24khz": "a vocoder for the safetensors checkpoints",
}

# What a package's display name says about its precision or format, which the
# catalogue shows as a variant instead.
NAME_NOISE = re.compile(
    r"\s*\(GGUF\)|\s+GGUF\b|\s+(?:Original|Native)-(?:Precision|Dtype)|\s+mixed\s+Q8_0/F16|\s+specialized checkpoint"
    r"|\s+(?:Q\d+_\w+|Q\d+|BF16|F16|F32|FP16|FP32)\b",
    re.I,
)

# Families that take a description of the voice or the delivery (`instruct`) on a
# plain request, as their page under docs/models/ shows. For a family listed with
# words, only the packages whose id contains one of them take it. Other families
# declare the option too, but need a template or a reference recording with it.
TAKES_INSTRUCTION = {
    "maya1": (),
    "qwen3_tts": ("customvoice", "voicedesign"),
}

# Families that need the words spoken in a voice recording although their spec
# marks `reference_text` as optional. OmniVoice refuses a recording without them
# ("native voice clone currently requires reference_text").
NEEDS_REFERENCE_TEXT = {"omnivoice"}

# Families of which only some packages copy a voice: those whose id contains one of the words.
# Qwen3 TTS copies a voice with its Base models only (docs/models/qwen3_tts.md).
COPIES_VOICE_ONLY = {"qwen3_tts": ("base",)}

# Families whose `instruct` is not a free description but words from a fixed
# list, one per group. OmniVoice's are in src/models/omnivoice/prompt_builder.cpp
# (mutually_exclusive_categories); its Chinese spellings and dialects are left out.
STYLES = {
    "omnivoice": [
        {"name": "Gender", "options": ["male", "female"]},
        {"name": "Age", "options": ["child", "teenager", "young adult", "middle-aged", "elderly"]},
        {"name": "Pitch", "options": ["very low pitch", "low pitch", "moderate pitch", "high pitch", "very high pitch"]},
        {"name": "Manner", "options": ["whisper"]},
        {"name": "Accent", "options": [
            "american accent", "british accent", "australian accent", "chinese accent", "canadian accent",
            "indian accent", "korean accent", "portuguese accent", "russian accent", "japanese accent",
        ]},
    ],
}

# Marks a family understands inside the text, copied from its page under docs/models/.
TAGS = {
    "maya1": ["<laugh>", "<whisper>", "<sigh>", "<gasp>"],
    "omnivoice": [
        "[laughter]", "[sigh]", "[confirmation-en]", "[question-en]", "[question-ah]", "[question-oh]", "[question-ei]",
        "[question-yi]", "[surprise-ah]", "[surprise-oh]", "[surprise-wa]", "[surprise-yo]", "[dissatisfaction-hnn]",
    ],
}

# Families that read a text with several speakers, with the most speakers a text
# may have and one speaker's turn as the family writes it. Each takes a recording
# per speaker (`voice_samples`), so it can copy voices even when its tasks do not
# say so. VibeVoice: docs/tts.md and src/models/vibevoice/tokenizer_text.cpp.
SPEAKERS = {
    "vibevoice": {"max": 4, "line": "Speaker {n}: {text}"},
}

# audio.cpp's own maturity labels. "experimental", "testing" and "wip" are left out.
STATUSES = {"supported", "community"}

# A language code as the engines write them: "en", "pt-BR", "yue".
LANGUAGE = re.compile(r"[A-Za-z]{2,3}(?:[-_][A-Za-z]{2,4})?\Z")

WHISPER_REPO = "ggerganov/whisper.cpp"
WHISPER_FILE = re.compile(r"ggml-(?P<name>[a-z0-9.-]+?)(?:-(?P<quant>q[0-9]_[0-9]))?\.bin\Z")

PRECISION_NAMES = {
    "f32": "F32 (full precision)", "f16": "F16", "bf16": "BF16", "orig": "Original precision",
    "q8_0": "Q8", "q6_k": "Q6", "q5_0": "Q5", "q5_1": "Q5", "q4_0": "Q4", "q4_k": "Q4", "q4_k_m": "Q4",
}


def load_recipe_script():
    """scripts/recipe.py as a module, for its Hub client and its validation."""
    spec = importlib.util.spec_from_file_location("recipe", os.path.join(ROOT, "scripts", "recipe.py"))
    module = importlib.util.module_from_spec(spec)
    sys.dont_write_bytecode = True
    spec.loader.exec_module(module)
    return module


def slug(text):
    return re.sub(r"[^a-z0-9._-]+", "-", text.lower()).strip("-.")


def submodule_version(path):
    try:
        return subprocess.run(["git", "-C", path, "describe", "--tags", "--always"], capture_output=True, text=True, check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return "unknown"


def pinned(role, repo, path, info, hub):
    found = hub.file(info, path)
    if not found or not found[1] or not isinstance(found[0], int):
        return None
    return {"role": role, "repo": repo, "file": path, "revision": info.get("sha"), "size_bytes": found[0], "sha256": found[1]}


# The most a file may weigh for this script to fetch it and work out its checksum.
# Model weights are far larger and always come with one from the Hub.
SMALL_FILE_LIMIT = 1 << 20


def small_file(role, repo, path, info, hub):
    """A file too small for LFS has no SHA-256 on the Hub, so it is fetched to work one out.

    The app refuses a download it cannot check, so a file whose checksum cannot be
    had leaves its model out of the catalogue.
    """
    found = hub.file(info, path)
    if not found or not isinstance(found[0], int) or found[0] <= 0:
        return None
    checksum = found[1] or fetched_sha256(repo, path, info.get("sha"), found[0])
    if not checksum:
        return None
    return {"role": role, "repo": repo, "file": path, "revision": info.get("sha"), "size_bytes": found[0], "sha256": checksum}


def fetched_sha256(repo, path, revision, size):
    """SHA-256 of a small text file on the Hub at a commit, or None when it cannot be read."""
    if not revision or size > SMALL_FILE_LIMIT:
        return None
    url = "https://huggingface.co/%s/resolve/%s/%s" % (
        urllib.parse.quote(repo, safe="/"), urllib.parse.quote(revision, safe=""), urllib.parse.quote(path, safe="/"))
    request = urllib.request.Request(url, headers={"User-Agent": "kiln-recipe-script"})
    token = os.environ.get("HF_TOKEN", "").strip()
    if token:
        request.add_header("Authorization", "Bearer " + token)
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            content = response.read(SMALL_FILE_LIMIT + 1)
    except (urllib.error.URLError, OSError, ValueError):
        return None
    return hashlib.sha256(content).hexdigest() if len(content) == size else None


# ---------------------------------------------------------------------------
# audio.cpp
# ---------------------------------------------------------------------------

def audiocpp_licenses():
    """family -> (licence, commercial use, notes), from audio.cpp's own table."""
    licenses = {}
    path = os.path.join(AUDIOCPP, "docs", "model_licenses.md")
    link = re.compile(r"\[([^\]]+)\]\([^)]*\)")
    with open(path, encoding="utf-8") as file:
        for line in file:
            cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
            if len(cells) < 5 or not cells[0].startswith("`"):
                continue
            licenses[cells[0].strip("`")] = tuple(link.sub(r"\1", cell).replace("<br>", ", ") for cell in cells[2:5])
    return licenses


def license_note(family, licenses):
    if family not in licenses:
        return "audio.cpp does not record a licence for this model. Check the model's page before using it."
    name, commercial, notes = licenses[family]
    use = {"Yes": "Commercial use is allowed.", "No": "Research or non-commercial use only.",
           "Conditional": "Commercial use is allowed only under conditions."}.get(commercial, "")
    return " ".join(part for part in ["License: %s." % name.rstrip("."), use, notes,
                                      "As recorded by audio.cpp (docs/model_licenses.md); check the model's page."] if part)


def audiocpp_recipes(hub):
    licenses = audiocpp_licenses()
    recipes, skipped = [], []
    for path in sorted(glob.glob(os.path.join(AUDIOCPP, "model_specs", "*.json"))):
        with open(path, encoding="utf-8") as file:
            spec = json.load(file)
        family = spec.get("family", "")
        if spec.get("category") != "tts" or spec.get("status") not in STATUSES or family in NEEDS_ESPEAK:
            continue
        defaults = (spec.get("package_defaults") or {}).get("download") or {}
        ui = spec.get("ui") or {}
        # A language can only be chosen for a family that declares the option;
        # the others refuse a language they did not ask for.
        takes_language = any(option.get("name") == "language" for option in (spec.get("options") or {}).get("request") or [])
        languages = [code for code in spec.get("languages") or [] if isinstance(code, str) and LANGUAGE.match(code)]
        languages = languages if takes_language and len(languages) > 1 else []
        instruct = next((option for option in (spec.get("options") or {}).get("request") or []
                         if option.get("name") == "instruct"), None)
        # A family with a clone task can speak in a voice copied from a recording.
        copies = "clone" in (spec.get("tasks") or [])
        words = next((option for option in (spec.get("options") or {}).get("request") or []
                      if option.get("name") == "reference_text"), None)
        groups = {}
        for package in spec.get("packages") or []:
            download = package.get("download") or defaults
            files = package.get("files") or []
            weights = [name for name in files if name.endswith(".gguf")]
            # A model split over several weight files is loaded as a folder, which
            # the helper does not do yet.
            if (package.get("format") != "gguf" or len(weights) != 1 or download.get("gated") or not download.get("repo")
                    or package.get("id") in NOT_STANDALONE):
                skipped.append(package.get("id", "?"))
                continue
            # Packages whose names differ only in precision are one model.
            key = (download["repo"], download.get("revision") or "main", title_of(package, family))
            groups.setdefault(key, []).append(package)

        for (repo, revision, title), packages in groups.items():
            # Two packages of one name and one precision are different builds of the
            # model; the first is kept as the variant and the rest stand alone.
            batch, extras, seen = [], [], set()
            for package in packages:
                (extras if package.get("precision") in seen else batch).append(package)
                seen.add(package.get("precision"))
            for group in [batch] + [[package] for package in extras]:
                recipe = audiocpp_recipe(family, ui, languages, repo, revision, title, group, group is not batch, licenses, hub)
                if recipe is None:
                    skipped.extend(package.get("id", "?") for package in group)
                    continue
                limited = COPIES_VOICE_ONLY.get(family)
                if copies and (limited is None or all(any(word in package.get("id", "") for word in limited) for package in group)):
                    recipe["speech"]["reference"] = "optional"
                    if words:
                        needed = words.get("required") or family in NEEDS_REFERENCE_TEXT
                        recipe["speech"]["reference_text"] = "required" if needed else "optional"
                only = TAKES_INSTRUCTION.get(family)
                if instruct and only is not None and all(
                        not only or any(word in package.get("id", "") for word in only) for package in group):
                    recipe["speech"]["instruction"] = "required" if instruct.get("required") else "optional"
                if family in STYLES:
                    recipe["speech"]["styles"] = STYLES[family]
                if family in TAGS:
                    recipe["speech"]["tags"] = TAGS[family]
                if family in SPEAKERS:
                    recipe["speech"]["speakers"] = SPEAKERS[family]
                    recipe["speech"].setdefault("reference", "optional")
                recipes.append(recipe)
    return recipes, skipped


def title_of(package, family):
    return NAME_NOISE.sub("", package.get("display_name") or family).strip() or family


def audiocpp_recipe(family, ui, languages, repo, revision, title, packages, is_extra, licenses, hub):
    try:
        info = hub.repo(repo, None if revision == "main" else revision)
    except Exception:
        return None

    def components(package):
        result = []
        for name in package.get("files") or []:
            if name.endswith(".gguf"):
                component = pinned("model", repo, name, info, hub)
            elif "/embeddings/" in name and name.endswith(".safetensors"):
                component = pinned("voice", repo, name, info, hub)
            else:
                component = small_file("support", repo, name, info, hub)
            if component is None:
                return None
            result.append(component)
        return result

    built = [(package, components(package)) for package in packages]
    if any(parts is None for _, parts in built):
        return None

    # An extra build of a model is told apart by its package id.
    identity = packages[0].get("id") if is_extra else title
    name = "%s (%s)" % (title, packages[0].get("id")) if is_extra else title
    recipe = {"id": "audio.cpp-" + slug(identity or family), "name": name, "engine": "audio.cpp", "output": "audio"}

    speech = {"family": family}
    voices = [voice for voice in ui.get("builtin_voices") or [] if isinstance(voice, str)]
    files_have_voices = any(part["role"] == "voice" for _, parts in built for part in parts)
    if voices and not files_have_voices:
        speech["voices"] = voices
        if ui.get("default_voice") in voices:
            speech["voice"] = ui["default_voice"]
    elif ui.get("default_voice"):
        speech["voice"] = ui["default_voice"]

    if len(built) == 1:
        recipe["components"] = built[0][1]
    else:
        # Files every precision shares are listed once.
        shared = [part for part in built[0][1] if part["role"] != "model" and all(part in parts for _, parts in built)]
        recipe["components"] = shared
        # Largest first, as in the hand-written recipes.
        built.sort(key=lambda pair: -sum(part["size_bytes"] for part in pair[1]))
        recipe["variants"] = [
            {"id": slug(package.get("precision") or package.get("id") or "default"),
             "name": PRECISION_NAMES.get(package.get("precision"), (package.get("precision") or "Default").upper()),
             "components": [part for part in parts if part not in shared]}
            for package, parts in built
        ]
    recipe["speech"] = speech
    if languages:
        recipe["languages"] = languages
    recipe["license_note"] = license_note(family, licenses)
    return recipe


# ---------------------------------------------------------------------------
# whisper.cpp
# ---------------------------------------------------------------------------

def whisper_languages():
    """The language codes whisper.cpp knows, in its own order, read from its source."""
    path = os.path.join(ROOT, "Vendor", "whisper.cpp", "src", "whisper.cpp")
    with open(path, encoding="utf-8") as file:
        return re.findall(r'^\s*\{ "([a-z]{2,3})",\s*\{ \d+,\s*"', file.read(), flags=re.M)


def whisper_recipes(hub):
    languages = whisper_languages()
    info = hub.repo(WHISPER_REPO)
    models = {}
    for sibling in info["siblings"]:
        match = WHISPER_FILE.match(sibling.get("rfilename") or "")
        if match:
            models.setdefault(match.group("name"), []).append((match.group("quant"), sibling["rfilename"]))

    recipes = []
    for name, files in sorted(models.items()):
        built = []
        for quant, path in files:
            component = pinned("model", WHISPER_REPO, path, info, hub)
            if component:
                built.append((quant, component))
        if not built:
            continue
        built.sort(key=lambda pair: -pair[1]["size_bytes"])
        title = "Whisper " + " ".join(part.capitalize() if not part.startswith("v") and part != "en" else part for part in name.split("-"))
        title = title.replace(".en", " (English only)")
        recipe = {"id": "whisper.cpp-" + slug(name), "name": title, "engine": "whisper.cpp"}
        if len(built) == 1:
            recipe["components"] = [built[0][1]]
        else:
            recipe["components"] = []
            recipe["variants"] = [
                {"id": quant or "full", "name": PRECISION_NAMES.get(quant, "Full precision (best quality)"), "components": [component]}
                for quant, component in built
            ]
        recipe["output"] = "text"
        recipe["accepts"] = ["audio"]
        # A model named ".en" only knows English.
        if not name.endswith(".en") and languages:
            recipe["languages"] = languages
        recipe["license_note"] = (
            "Converted files: MIT License (ggerganov/whisper.cpp). The original Whisper models are by OpenAI; "
            "check the original model's page for its licence."
        )
        recipes.append(recipe)
    return recipes


# ---------------------------------------------------------------------------

def render(source, recipes):
    return json.dumps({"source": source, "recipes": recipes}, indent=2, ensure_ascii=False) + "\n"


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--check", action="store_true", help="fail if the committed files differ from what would be generated")
    args = parser.parse_args(argv)

    recipe = load_recipe_script()
    hub = recipe.Hub()
    try:
        audio, skipped = audiocpp_recipes(hub)
        whisper = whisper_recipes(hub)
    except recipe.NetworkError as error:
        print("Hugging Face could not be reached: %s" % error, file=sys.stderr)
        return 3

    outputs = {
        "audio.cpp.json": render("audio.cpp %s, model_specs/" % submodule_version(AUDIOCPP), audio),
        "whisper.cpp.json": render("files of %s on Hugging Face" % WHISPER_REPO, whisper),
    }

    problems = 0
    seen = set()
    for entry in audio + whisper:
        for problem in recipe.validate_recipe(entry, curated=False):
            print("%s: %s" % (entry.get("id"), problem), file=sys.stderr)
            problems += 1
        if entry["id"] in seen:
            print("%s: duplicate id" % entry["id"], file=sys.stderr)
            problems += 1
        seen.add(entry["id"])
    if problems:
        return 1

    stale = []
    for name, text in outputs.items():
        path = os.path.join(OUTPUT, name)
        current = open(path, encoding="utf-8").read() if os.path.exists(path) else None
        if current == text:
            continue
        if args.check:
            stale.append(name)
        else:
            os.makedirs(OUTPUT, exist_ok=True)
            with open(path, "w", encoding="utf-8") as file:
                file.write(text)
    if stale:
        print("Out of date: %s. Run: python3 scripts/catalog.py" % ", ".join(stale), file=sys.stderr)
        return 1

    print("audio.cpp: %d models (%d packages left out)" % (len(audio), len(skipped)))
    print("whisper.cpp: %d models" % len(whisper))
    print("OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
