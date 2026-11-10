#!/usr/bin/env python3
"""Create, check and index Kiln model recipes.

Standard library only; runs on the python3 that ships with Xcode's tools (3.9).
The only network access is the Hugging Face model API, for file metadata.
Model files are never downloaded.

    python3 scripts/recipe.py new --help
    python3 scripts/recipe.py check
    python3 scripts/recipe.py index

The format is defined by Sources/KilnCore/Recipes/ and documented in docs/recipes.md.
"""

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_DIRECTORY = os.path.join(ROOT, "recipes")
VENDOR_SOURCE = os.path.join(ROOT, "Vendor", "stable-diffusion.cpp", "src", "stable-diffusion.cpp")

HUB_HOST = "huggingface.co"
ENGINE = "sd.cpp"
SCHEMA_REFERENCE = "./schema.json"
INDEX_NAME = "index.json"
# RecipeStore.reservedFileNames: files beside the recipes that are not recipes.
RESERVED_NAMES = {"index.json", "schema.json"}

# ModelRecipe.ComponentRole
ROLES = ["checkpoint", "diffusion_model", "llm", "vae", "clip_l", "clip_g", "t5xxl"]

RECIPE_KEYS = {"$schema", "id", "name", "engine", "components", "defaults", "license_note", "min_memory_gb", "variants"}
COMPONENT_KEYS = {"role", "repo", "file", "revision", "size_bytes", "sha256"}
DEFAULTS_KEYS = {
    "steps", "cfg", "sampler", "width", "height",
    "sigmas", "flash_attention", "scheduler", "guidance", "flow_shift",
}
VARIANT_KEYS = {"id", "name", "components", "min_memory_gb"}

# Used only when the stable-diffusion.cpp submodule is not checked out.
# Otherwise the names are read from sample_method_to_str and scheduler_to_str.
FALLBACK_SAMPLERS = [
    "euler", "euler_a", "heun", "dpm2", "dpm++2s_a", "dpm++2m", "dpm++2mv2", "ipndm", "ipndm_v",
    "lcm", "ddim_trailing", "tcd", "res_multistep", "res_2s", "er_sde", "euler_cfg_pp",
    "euler_a_cfg_pp", "euler_ge", "dpm++2m_sde", "dpm++2m_sde_bt", "lms",
]
FALLBACK_SCHEDULERS = [
    "discrete", "karras", "exponential", "ays", "gits", "sgm_uniform", "simple", "smoothstep",
    "kl_optimal", "lcm", "bong_tangent", "ltx2", "logit_normal", "flux2", "flux", "beta", "llada_image",
]

SLUG = re.compile(r"[a-z0-9._-]+\Z")
SHA256 = re.compile(r"[0-9a-fA-F]{64}\Z")
COMMIT = re.compile(r"[0-9a-f]{40}\Z")

EXIT_OK, EXIT_FAILED, EXIT_NETWORK = 0, 1, 3


class UsageError(Exception):
    """A problem with the arguments or the files the user pointed at."""


class NotOnHub(Exception):
    """The Hub answered, and the repo or revision is not there (or not public)."""


class NetworkError(Exception):
    """The Hub could not be reached or did not give a usable answer."""


# ---------------------------------------------------------------------------
# Validation: the rules of ModelRecipe.validate() and of the decoder.
# ---------------------------------------------------------------------------

def is_slug(text):
    return isinstance(text, str) and bool(SLUG.match(text)) and not text.startswith(".")


def is_int(value):
    return isinstance(value, int) and not isinstance(value, bool)


def is_number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def is_blank(text):
    return text.strip(" \t") == ""


def engine_names():
    """Sampler and scheduler names accepted by the vendored stable-diffusion.cpp."""
    def read(source, array):
        match = re.search(r"const char\*\s*%s\[\]\s*=\s*\{(.*?)\};" % array, source, re.S)
        return re.findall(r'"([^"]+)"', match.group(1)) if match else []

    try:
        with open(VENDOR_SOURCE, encoding="utf-8") as handle:
            source = handle.read()
    except OSError:
        return FALLBACK_SAMPLERS, FALLBACK_SCHEDULERS
    samplers = read(source, "sample_method_to_str") or FALLBACK_SAMPLERS
    schedulers = read(source, "scheduler_to_str") or FALLBACK_SCHEDULERS
    return samplers, schedulers


def unknown_keys(obj, allowed, where, problems):
    for key in obj:
        if key not in allowed:
            problems.append(
                '%sunknown field "%s". The app would silently ignore it; allowed: %s.'
                % (where, key, ", ".join(sorted(allowed)))
            )


def validate_component(component, where, problems, curated):
    if not isinstance(component, dict):
        problems.append("%smust be an object." % where)
        return None
    if curated:
        unknown_keys(component, COMPONENT_KEYS, where, problems)

    role = component.get("role")
    if role not in ROLES:
        problems.append('%srole "%s" is not one of: %s.' % (where, role, ", ".join(ROLES)))
        role = None

    repo = component.get("repo")
    parts = repo.split("/") if isinstance(repo, str) else []
    if len(parts) != 2 or any(part in ("", ".", "..") for part in parts):
        problems.append('%srepo "%s" is not a Hugging Face repo id (expected owner/name).' % (where, repo))

    path = component.get("file")
    segments = path.split("/") if isinstance(path, str) else [""]
    if not isinstance(path, str) or "\\" in path or any(part in ("", ".", "..") for part in segments):
        problems.append(
            '%sfile "%s" is not allowed. Use the path inside the repo, such as "vae/model.safetensors": '
            'no leading slash, no backslash, no empty, "." or ".." segment.' % (where, path)
        )

    revision = component.get("revision")
    if revision is not None and not isinstance(revision, str):
        problems.append("%srevision must be a string." % where)
    elif curated and (revision is None or not COMMIT.match(revision)):
        problems.append(
            "%srevision must be a full 40-character commit sha so the download is pinned (found %s)."
            % (where, json.dumps(revision))
        )

    size = component.get("size_bytes")
    if size is not None and (not is_int(size) or size <= 0):
        problems.append("%ssize_bytes must be a whole number greater than zero." % where)
    elif curated and size is None:
        problems.append("%ssize_bytes is missing." % where)

    sha256 = component.get("sha256")
    if sha256 is not None and not (isinstance(sha256, str) and SHA256.match(sha256)):
        problems.append("%ssha256 is not 64 hexadecimal characters." % where)
    elif curated and sha256 is None:
        problems.append("%ssha256 is missing." % where)
    return role


def validate_components(components, where, problems, curated, allow_empty=False):
    """Returns the roles in the list, or None when the list itself is unusable."""
    if not isinstance(components, list):
        problems.append('%s must be an array (it may be empty only when "variants" is used).' % where)
        return None
    if not components and not allow_empty:
        problems.append("%s lists no files to download." % where)
    roles = []
    for index, component in enumerate(components):
        role = validate_component(component, "%s[%d]: " % (where, index), problems, curated)
        if role is None:
            continue
        if role in roles:
            problems.append('%s lists more than one "%s" component. Each role may appear once.' % (where, role))
        roles.append(role)
    return roles


def validate_defaults(defaults, problems, curated):
    if not isinstance(defaults, dict):
        problems.append("defaults is missing or is not an object.")
        return
    if curated:
        unknown_keys(defaults, DEFAULTS_KEYS, "defaults: ", problems)

    steps = defaults.get("steps")
    if not is_int(steps) or steps <= 0:
        problems.append("defaults.steps must be a whole number greater than zero.")
        steps = None
    cfg = defaults.get("cfg")
    if not is_number(cfg) or cfg < 0:
        problems.append("defaults.cfg must be a number and cannot be negative.")
    sampler = defaults.get("sampler")
    if not isinstance(sampler, str) or sampler == "":
        problems.append("defaults.sampler is missing.")
    for key in ("width", "height"):
        if not is_int(defaults.get(key)) or defaults[key] <= 0:
            problems.append("defaults.%s must be a whole number greater than zero." % key)

    sigmas = defaults.get("sigmas")
    if sigmas is not None:
        if not isinstance(sigmas, list) or not all(is_number(value) for value in sigmas):
            problems.append("defaults.sigmas must be an array of numbers.")
        elif steps is not None and len(sigmas) != steps + 1:
            problems.append(
                "defaults.sigmas: %d steps need %d sigmas (steps + 1), found %d." % (steps, steps + 1, len(sigmas))
            )
    if "flash_attention" in defaults and not isinstance(defaults["flash_attention"], bool):
        problems.append("defaults.flash_attention must be true or false.")
    scheduler = defaults.get("scheduler")
    if scheduler is not None and not isinstance(scheduler, str):
        problems.append("defaults.scheduler must be a string.")
    for key in ("guidance", "flow_shift"):
        if defaults.get(key) is not None and not is_number(defaults[key]):
            problems.append("defaults.%s must be a number." % key)

    if curated:
        samplers, schedulers = engine_names()
        if isinstance(sampler, str) and sampler and sampler not in samplers:
            problems.append(
                'defaults.sampler "%s" is not a stable-diffusion.cpp sampler. Known: %s.'
                % (sampler, ", ".join(samplers))
            )
        # The engine also reads "normal" as "discrete".
        if isinstance(scheduler, str) and scheduler not in schedulers + ["normal"]:
            problems.append(
                'defaults.scheduler "%s" is not a stable-diffusion.cpp scheduler. Known: %s.'
                % (scheduler, ", ".join(schedulers))
            )


def validate_recipe(recipe, curated=True, file_name=None):
    """Returns a list of problems; empty when the recipe is valid.

    With curated=False these are the app's own rules. curated=True adds what
    recipes/ requires: pinned files, the sd.cpp engine, known sampler and
    scheduler names, no unknown fields, and a file name equal to the id.
    """
    problems = []
    if not isinstance(recipe, dict):
        return ["The file must contain one JSON object."]
    if curated:
        unknown_keys(recipe, RECIPE_KEYS, "", problems)

    recipe_id = recipe.get("id")
    if not is_slug(recipe_id):
        problems.append(
            "id %s must use only lowercase letters, digits, dots, dashes and underscores, and not start with a dot."
            % json.dumps(recipe_id)
        )
    elif file_name is not None and file_name != recipe_id + ".json":
        problems.append('The file must be named "%s.json" to match its id (found "%s").' % (recipe_id, file_name))

    name = recipe.get("name")
    if not isinstance(name, str) or is_blank(name):
        problems.append("name is missing or empty.")
    engine = recipe.get("engine")
    if not isinstance(engine, str):
        problems.append("engine is missing.")
    elif curated and engine != ENGINE:
        problems.append('engine must be "%s" (found "%s").' % (ENGINE, engine))
    if recipe.get("license_note") is not None and not isinstance(recipe["license_note"], str):
        problems.append("license_note must be a string.")
    if recipe.get("min_memory_gb") is not None and not is_number(recipe["min_memory_gb"]):
        problems.append("min_memory_gb must be a number.")

    validate_defaults(recipe.get("defaults"), problems, curated)

    variants = recipe.get("variants")
    if variants is not None and not isinstance(variants, list):
        problems.append("variants must be an array.")
        variants = None
    validate_components(recipe.get("components"), "components", problems, curated, allow_empty=bool(variants))

    seen = set()
    for index, variant in enumerate(variants or []):
        where = "variants[%d]" % index
        if not isinstance(variant, dict):
            problems.append("%s must be an object." % where)
            continue
        if curated:
            unknown_keys(variant, VARIANT_KEYS, where + ": ", problems)
        variant_id, variant_name = variant.get("id"), variant.get("name")
        if not is_slug(variant_id) or variant_id in seen or not isinstance(variant_name, str) or is_blank(variant_name):
            problems.append(
                "%s (%s) needs a unique id of lowercase letters, digits, dots, dashes and underscores, and a name."
                % (where, json.dumps(variant_id))
            )
        if isinstance(variant_id, str):
            seen.add(variant_id)
        if variant.get("min_memory_gb") is not None and not is_number(variant["min_memory_gb"]):
            problems.append("%s.min_memory_gb must be a number." % where)
        validate_components(variant.get("components"), where + ".components", problems, curated)
    # A variant's file replaces the shared file with the same role, so merging
    # cannot produce a duplicate role once both lists are valid on their own.
    return problems


def installs(recipe):
    """(label, component) for every file the recipe can download, without repeats."""
    result = [("shared" if recipe.get("variants") else "", c) for c in recipe.get("components") or []]
    for variant in recipe.get("variants") or []:
        result += [(variant.get("id", "?"), c) for c in variant.get("components") or []]
    return result


# ---------------------------------------------------------------------------
# Hugging Face metadata
# ---------------------------------------------------------------------------

class HubOnlyRedirects(urllib.request.HTTPRedirectHandler):
    """Refuses to follow a redirect to another host, so the token never leaves the Hub."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        target = urllib.parse.urlsplit(newurl)
        if target.scheme != "https" or target.hostname != HUB_HOST:
            raise urllib.error.HTTPError(req.full_url, code, "redirect to another host refused: " + newurl, headers, fp)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


class Hub:
    def __init__(self):
        self.opener = urllib.request.build_opener(HubOnlyRedirects)
        self.cache = {}

    def repo(self, repo, revision=None):
        """Model info with file sizes and LFS checksums, at a revision or at the default branch."""
        key = (repo, revision)
        if key not in self.cache:
            try:
                self.cache[key] = self.fetch(repo, revision)
            except (NotOnHub, NetworkError) as error:
                self.cache[key] = error
        if isinstance(self.cache[key], Exception):
            raise self.cache[key]
        return self.cache[key]

    def fetch(self, repo, revision):
        url = "https://%s/api/models/%s" % (HUB_HOST, urllib.parse.quote(repo, safe="/"))
        if revision:
            url += "/revision/" + urllib.parse.quote(revision, safe="")
        url += "?blobs=true"
        request = urllib.request.Request(url, headers={"User-Agent": "kiln-recipe-script", "Accept": "application/json"})
        token = os.environ.get("HF_TOKEN", "").strip()
        if token:
            request.add_header("Authorization", "Bearer " + token)
        what = repo + (" at revision " + revision if revision else "")
        try:
            with self.opener.open(request, timeout=30) as response:
                info = json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as error:
            if error.code in (401, 403, 404):
                hint = "" if token else " If the repo is private or gated, set HF_TOKEN."
                raise NotOnHub("Hugging Face has no %s (HTTP %d).%s" % (what, error.code, hint))
            raise NetworkError("Hugging Face answered HTTP %d for %s." % (error.code, what))
        except (urllib.error.URLError, OSError, ValueError) as error:
            raise NetworkError("could not reach Hugging Face for %s: %s" % (what, getattr(error, "reason", error)))
        if not isinstance(info, dict) or not isinstance(info.get("siblings"), list):
            raise NetworkError("unexpected answer from Hugging Face for %s." % what)
        return info

    @staticmethod
    def file(info, path):
        """(size, sha256) of a file in a model info answer; None when the file is absent."""
        for sibling in info["siblings"]:
            if sibling.get("rfilename") == path:
                return sibling.get("size"), (sibling.get("lfs") or {}).get("sha256")
        return None


# ---------------------------------------------------------------------------
# Files
# ---------------------------------------------------------------------------

def display(path):
    relative = os.path.relpath(path)
    return path if relative.startswith("..") else relative


def recipe_files(directory):
    try:
        names = os.listdir(directory)
    except OSError as error:
        raise UsageError("cannot read %s: %s" % (display(directory), error.strerror))
    return sorted(name for name in names if name.lower().endswith(".json") and name not in RESERVED_NAMES)


def index_text(directory):
    return json.dumps({"version": 1, "recipes": recipe_files(directory)}, indent=2) + "\n"


def write_index(directory):
    path = os.path.join(directory, INDEX_NAME)
    text = index_text(directory)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(text)
    return path, json.loads(text)["recipes"]


def gigabytes(size):
    return "%.2f GB" % (size / 1073741824.0)


# ---------------------------------------------------------------------------
# new
# ---------------------------------------------------------------------------

COMPONENT_SPEC = re.compile(r"(?P<role>[^=]+)=(?P<repo>[^:@]+)(?:@(?P<revision>[^:]+))?:(?P<file>.+)\Z")
SPEC_HELP = "ROLE=OWNER/REPO:PATH (or ROLE=OWNER/REPO@REVISION:PATH)"


def parse_component(spec):
    match = COMPONENT_SPEC.match(spec)
    if not match:
        raise UsageError('"%s" is not a component. Write it as %s.' % (spec, SPEC_HELP))
    if match.group("role") not in ROLES:
        raise UsageError('"%s": unknown role "%s". Roles: %s.' % (spec, match.group("role"), ", ".join(ROLES)))
    component = {"role": match.group("role"), "repo": match.group("repo"), "file": match.group("file")}
    return component, match.group("revision")


def parse_variant(values):
    if len(values) < 3:
        raise UsageError('--variant needs an id, a name and at least one component: --variant q8 "Q8 (best quality)" %s' % SPEC_HELP)
    variant = {"id": values[0], "name": values[1]}
    components = []
    for value in values[2:]:
        if value.startswith("min_memory_gb="):
            variant["min_memory_gb"] = parse_memory(value.split("=", 1)[1])
        else:
            components.append(parse_component(value))
    variant["components"] = components
    return variant


def parse_memory(text):
    try:
        value = float(text)
    except ValueError:
        raise UsageError('min_memory_gb "%s" is not a number.' % text)
    return int(value) if value.is_integer() else value


def parse_sigmas(values):
    try:
        return [float(part) for value in values for part in re.split(r"[,\s]+", value) if part]
    except ValueError:
        raise UsageError("--sigmas takes numbers separated by commas or spaces.")


def pin(component, revision, hub):
    """Fills revision, size_bytes and sha256 from the Hub. Returns an error message or None."""
    info = hub.repo(component["repo"], revision)
    found = Hub.file(info, component["file"])
    where = "%s:%s" % (component["repo"], component["file"])
    if found is None:
        weights = [s.get("rfilename", "") for s in info["siblings"] if s.get("rfilename", "").endswith((".gguf", ".safetensors"))]
        listing = "\n".join("      " + name for name in weights[:40]) or "      (none)"
        return "%s: no such file in the repo. Weight files there:\n%s" % (where, listing)
    size, sha256 = found
    if not sha256 or not is_int(size):
        return "%s: the Hub reports no LFS sha256 for this file, so it cannot be pinned." % where
    component["revision"] = info.get("sha")
    component["size_bytes"] = size
    component["sha256"] = sha256
    return None


def command_new(args):
    directory = os.path.abspath(args.directory)
    path = os.path.join(directory, "%s.json" % args.id)

    shared = [parse_component(spec) for spec in args.component or []]
    variants = [parse_variant(values) for values in args.variant or []]
    if not shared and not variants:
        raise UsageError("Give at least one --component or --variant.")

    defaults = {"steps": args.steps, "cfg": args.cfg, "sampler": args.sampler, "width": args.width, "height": args.height}
    if args.sigmas:
        defaults["sigmas"] = parse_sigmas(args.sigmas)
    if args.flash_attention:
        defaults["flash_attention"] = True
    if args.scheduler:
        defaults["scheduler"] = args.scheduler
    if args.guidance is not None:
        defaults["guidance"] = args.guidance
    if args.flow_shift is not None:
        defaults["flow_shift"] = args.flow_shift

    recipe = {"$schema": SCHEMA_REFERENCE, "id": args.id, "name": args.name, "engine": ENGINE}
    recipe["components"] = [component for component, _ in shared]
    recipe["defaults"] = defaults
    if args.license_note:
        recipe["license_note"] = args.license_note
    if args.min_memory_gb is not None:
        recipe["min_memory_gb"] = parse_memory(args.min_memory_gb)
    if variants:
        recipe["variants"] = [dict(variant, components=[c for c, _ in variant["components"]]) for variant in variants]

    # Everything that can be wrong without asking the Hub is reported first.
    problems = [p for p in validate_recipe(recipe, curated=True) if not re.search(r"(revision|size_bytes|sha256) (must be a full|is missing)", p)]
    if is_slug(args.id) and args.id + ".json" in RESERVED_NAMES:
        problems.append('"%s" is a reserved file name.' % (args.id + ".json"))
    if problems:
        return report_problems("The recipe was not written:", problems)
    if os.path.exists(path) and not args.force:
        raise UsageError("%s already exists. Pass --force to replace it." % display(path))
    if not os.path.isdir(directory):
        raise UsageError("%s is not a directory." % display(directory))

    hub = Hub()
    targets = shared + [pair for variant in variants for pair in variant["components"]]
    errors = []
    for component, revision in targets:
        try:
            error = pin(component, revision, hub)
        except NotOnHub as failure:
            error = str(failure)
        except NetworkError as failure:
            print("error: %s" % failure, file=sys.stderr)
            print("Nothing was written. This is a network problem, not a problem with the recipe.", file=sys.stderr)
            return EXIT_NETWORK
        if error and error not in errors:
            errors.append(error)
    if errors:
        return report_problems("The recipe was not written:", errors)

    problems = validate_recipe(recipe, curated=True, file_name=os.path.basename(path))
    if problems:
        return report_problems("The recipe was not written:", problems)

    with open(path, "w", encoding="utf-8") as handle:
        handle.write(json.dumps(recipe, indent=2, ensure_ascii=False) + "\n")
    index_path, _ = write_index(directory)

    print("Wrote %s" % display(path))
    print("Updated %s" % display(index_path))
    shared_size = sum(component["size_bytes"] for component, _ in shared)
    if variants:
        for variant in variants:
            replaced = {component["role"] for component, _ in variant["components"]}
            size = sum(c["size_bytes"] for c, _ in shared if c["role"] not in replaced)
            size += sum(c["size_bytes"] for c, _ in variant["components"])
            print("  variant %-12s %s to download" % (variant["id"], gigabytes(size)))
    else:
        print("  %s to download" % gigabytes(shared_size))
    print("Next: python3 scripts/recipe.py check %s" % display(path))
    return EXIT_OK


def report_problems(heading, problems):
    print(heading, file=sys.stderr)
    for problem in problems:
        print("  - %s" % problem, file=sys.stderr)
    return EXIT_FAILED


# ---------------------------------------------------------------------------
# check
# ---------------------------------------------------------------------------

def verify(component, hub):
    """Returns (status, detail) with status one of "ok", "FAIL", "SKIP"."""
    try:
        info = hub.repo(component["repo"], component["revision"])
    except NotOnHub as error:
        return "FAIL", str(error)
    except NetworkError as error:
        return "SKIP", "network error: %s" % error
    found = Hub.file(info, component["file"])
    if found is None:
        return "FAIL", "the file does not exist in %s at revision %s" % (component["repo"], component["revision"])
    size, sha256 = found
    if size != component["size_bytes"]:
        return "FAIL", "size_bytes is %s, Hugging Face reports %s" % (component["size_bytes"], size)
    if not sha256:
        return "FAIL", "Hugging Face reports no LFS sha256 for this file, so it cannot be verified"
    if sha256.lower() != component["sha256"].lower():
        return "FAIL", "sha256 is %s, Hugging Face reports %s" % (component["sha256"], sha256)
    return "ok", "%d bytes" % size


def command_check(args):
    directory = os.path.abspath(args.directory)
    if args.files:
        paths = [os.path.abspath(path) for path in args.files]
    else:
        paths = [os.path.join(directory, name) for name in recipe_files(directory)]
        if not paths:
            raise UsageError("No recipes found in %s." % display(directory))

    hub = Hub()
    counts = {"ok": 0, "FAIL": 0, "SKIP": 0}
    invalid = 0
    for path in paths:
        print(display(path))
        name = os.path.basename(path)
        if name in RESERVED_NAMES:
            problems = ['"%s" is a reserved name, not a recipe.' % name]
        else:
            try:
                with open(path, encoding="utf-8") as handle:
                    recipe = json.load(handle)
                problems = validate_recipe(recipe, curated=True, file_name=name)
            except OSError as error:
                problems = ["cannot read the file: %s" % error.strerror]
            except ValueError as error:
                problems = ["not valid JSON: %s" % error]
        if problems:
            invalid += 1
            for problem in problems:
                print("  FAIL  %s" % problem)
            continue
        if args.offline:
            print("  ok    structure is valid (files not verified: --offline)")
            continue
        seen = set()
        for label, component in installs(recipe):
            key = (component["repo"], component["revision"], component["file"])
            if key in seen:
                continue
            seen.add(key)
            status, detail = verify(component, hub)
            counts[status] += 1
            tag = "%s/%s" % (label, component["role"]) if label else component["role"]
            print("  %-4s  %-22s %s:%s  (%s)" % (status, tag, component["repo"], component["file"], detail))

    index_ok = True
    if not args.files:
        index_path = os.path.join(directory, INDEX_NAME)
        try:
            with open(index_path, encoding="utf-8") as handle:
                index = json.load(handle)
            listed = index.get("recipes") if isinstance(index, dict) else None
            index_ok = isinstance(listed, list) and sorted(listed) == recipe_files(directory) and index.get("version") == 1
        except (OSError, ValueError):
            index_ok = False
        print(display(index_path))
        print("  ok    lists exactly the recipe files" if index_ok
              else "  FAIL  does not list exactly the recipe files. Run: python3 scripts/recipe.py index")

    print()
    summary = "%d recipe%s checked" % (len(paths), "" if len(paths) == 1 else "s")
    if args.offline:
        summary += ", %d invalid, files not verified (--offline)" % invalid
    else:
        summary += ": %d file%s verified, %d failed, %d not checked (network), %d invalid recipe%s" % (
            counts["ok"], "" if counts["ok"] == 1 else "s", counts["FAIL"], counts["SKIP"],
            invalid, "" if invalid == 1 else "s")
    print(summary)

    if invalid or counts["FAIL"] or not index_ok:
        print("FAILED")
        return EXIT_FAILED
    if counts["SKIP"]:
        print("INCOMPLETE: Hugging Face could not be reached for some files. Nothing was found wrong; run it again.")
        return EXIT_NETWORK
    print("OK")
    return EXIT_OK


# ---------------------------------------------------------------------------
# index
# ---------------------------------------------------------------------------

def command_index(args):
    directory = os.path.abspath(args.directory)
    path, names = write_index(directory)
    print("Wrote %s (%d recipe%s)" % (display(path), len(names), "" if len(names) == 1 else "s"))
    return EXIT_OK


# ---------------------------------------------------------------------------
# Command line
# ---------------------------------------------------------------------------

NEW_EXAMPLES = """\
components:
  Each file is written as ROLE=OWNER/REPO:PATH, where PATH is the file's path
  inside the Hugging Face repo. The script looks up the repo's current commit,
  the file's size and its SHA-256 and writes them into the recipe.
  To pin an older commit or another branch: ROLE=OWNER/REPO@REVISION:PATH.
  Roles: checkpoint, diffusion_model, llm, vae, clip_l, clip_g, t5xxl.

example 1, a single-file checkpoint:
  python3 scripts/recipe.py new \\
    --id sdxl-base-1.0 \\
    --name "Stable Diffusion XL Base 1.0" \\
    --component checkpoint=stabilityai/stable-diffusion-xl-base-1.0:sd_xl_base_1.0.safetensors \\
    --steps 30 --cfg 7.0 --sampler euler --width 1024 --height 1024 \\
    --license-note "CreativeML Open RAIL++-M License." \\
    --min-memory-gb 16

example 2, a split model offered in two quantizations (variants):
  python3 scripts/recipe.py new \\
    --id qwen-image-2.1-turbo \\
    --name "Qwen-Image 2.1 Turbo" \\
    --component vae=Comfy-Org/Qwen-Image-2.1:vae/qwen_image_2.1_vae_bf16.safetensors \\
    --variant q8 "Q8 (best quality)" min_memory_gb=24 \\
        llm=Qwen/Qwen3-VL-8B-Instruct-GGUF:Qwen3VL-8B-Instruct-Q8_0.gguf \\
        diffusion_model=AtomicChat/Qwen-Image-2.1-Turbo-GGUF:Qwen-Image-2.1-Turbo-Q8_0.gguf \\
    --variant q4 "Q4 (smaller)" min_memory_gb=16 \\
        llm=Qwen/Qwen3-VL-8B-Instruct-GGUF:Qwen3VL-8B-Instruct-Q4_K_M.gguf \\
        diffusion_model=AtomicChat/Qwen-Image-2.1-Turbo-GGUF:Qwen-Image-2.1-Turbo-AD-Q4_K.gguf \\
    --steps 8 --cfg 1.0 --sampler euler --width 1024 --height 1024 \\
    --sigmas 1.0,0.978453,0.95418,0.926626,0.89508,0.845148,0.704534,0.414568,0.0 \\
    --flash-attention \\
    --license-note "Denoiser and VAE: Qwen Research License (non-commercial). Text encoder: Apache-2.0."

  --component files are shared by every variant. A variant lists the files that
  differ; one with the same role as a shared file replaces it.

environment:
  HF_TOKEN  optional Hugging Face access token for private or gated repos.
            It is sent only to huggingface.co.
"""


def build_parser():
    parser = argparse.ArgumentParser(
        prog="recipe.py",
        description="Create, check and index Kiln model recipes. See docs/recipes.md.",
    )
    commands = parser.add_subparsers(dest="command", metavar="{new,check,index}")
    commands.required = True

    def directory_option(sub):
        sub.add_argument("--directory", default=DEFAULT_DIRECTORY, metavar="DIR",
                         help="recipes folder (default: recipes/ in this repository)")

    new = commands.add_parser(
        "new", help="create recipes/<id>.json, looking up revision, size and SHA-256 on Hugging Face",
        description="Create recipes/<id>.json. File metadata comes from the Hugging Face API; nothing is downloaded.",
        epilog=NEW_EXAMPLES, formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    new.add_argument("--id", required=True, help="recipe id and file name: lowercase letters, digits, dots, dashes, underscores")
    new.add_argument("--name", required=True, help="display name shown in the app")
    new.add_argument("--component", action="append", metavar="ROLE=OWNER/REPO:PATH",
                     help="a file every install needs; repeat for each file")
    new.add_argument("--variant", action="append", nargs="+", metavar="ARG",
                     help='ID "NAME" [min_memory_gb=N] ROLE=OWNER/REPO:PATH ...; repeat for each variant')
    settings = new.add_argument_group("default settings (take them from the model card)")
    settings.add_argument("--steps", required=True, type=int, help="sampling steps")
    settings.add_argument("--cfg", required=True, type=float, help="classifier-free guidance scale")
    settings.add_argument("--sampler", required=True, help="stable-diffusion.cpp sampler name, for example euler")
    settings.add_argument("--width", required=True, type=int, help="image width in pixels")
    settings.add_argument("--height", required=True, type=int, help="image height in pixels")
    settings.add_argument("--sigmas", nargs="+", metavar="N", help="explicit noise schedule, steps + 1 numbers, comma or space separated")
    settings.add_argument("--flash-attention", action="store_true", help="enable flash attention for the diffusion model")
    settings.add_argument("--scheduler", help="stable-diffusion.cpp scheduler name (default: the engine's choice)")
    settings.add_argument("--guidance", type=float, help="distilled guidance, for guidance-distilled models")
    settings.add_argument("--flow-shift", type=float, help="flow shift, for flow-matching models")
    new.add_argument("--license-note", help="short, accurate summary of the licence of every file")
    new.add_argument("--min-memory-gb", metavar="GB", help="smallest system RAM the recipe is expected to run on")
    new.add_argument("--force", action="store_true", help="replace an existing recipe file")
    directory_option(new)
    new.set_defaults(run=command_new)

    check = commands.add_parser(
        "check", help="validate recipes and verify every file against Hugging Face",
        description="Validate the structure of each recipe, then verify that every file of every variant exists on "
                    "Hugging Face at its pinned revision with the recorded size and SHA-256. "
                    "Exit status: 0 all good, 1 something is wrong, 3 Hugging Face could not be reached.",
    )
    check.add_argument("files", nargs="*", metavar="FILE", help="recipe files to check (default: every recipe)")
    check.add_argument("--offline", action="store_true", help="validate structure only; do not contact Hugging Face")
    directory_option(check)
    check.set_defaults(run=command_check)

    index = commands.add_parser(
        "index", help="rewrite index.json from the recipe files present",
        description="Rewrite index.json so it lists every recipe file in the folder, sorted.",
    )
    directory_option(index)
    index.set_defaults(run=command_index)
    return parser


def main(argv=None):
    args = build_parser().parse_args(argv)
    try:
        return args.run(args)
    except UsageError as error:
        print("error: %s" % error, file=sys.stderr)
        return EXIT_FAILED
    except KeyboardInterrupt:
        return 130


if __name__ == "__main__":
    sys.exit(main())
