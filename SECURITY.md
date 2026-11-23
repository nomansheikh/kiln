# Security Policy

## Supported versions

Kiln is pre-1.0. Only the latest release and the `main` branch receive security fixes.

## Reporting a vulnerability

Report privately through GitHub: open the repository's **Security** tab and choose **Report a vulnerability** ([direct link](https://github.com/nomansheikh/kiln/security/advisories/new)). Please do not open a public issue for a suspected vulnerability.

Include:

- the Kiln version or commit, and the macOS version
- what the problem is and what an attacker could do with it
- steps to reproduce, with a recipe file, model file or request that triggers it if there is one
- any logs or crash reports, with access tokens removed

This is a volunteer-maintained project, so there is no guaranteed response time. Reports are acknowledged as soon as possible, and fixes are released together with an advisory that credits the reporter unless they ask otherwise.

## How Kiln is built, and what is in scope

Kiln is a macOS app with three local helper processes, one per engine. The app is not sandboxed and runs with the user's privileges; each helper confines itself when it starts (see "Model files are untrusted data").

- **Downloads.** Model files are downloaded from `https://huggingface.co` over HTTPS. Every downloaded file is checked against its expected size and SHA-256 checksum, and a file that has no checksum is not downloaded at all. Curated recipes and the generated catalogue pin a revision, size and checksum for every file; for a file picked from the Hub list, the checksum is the one the Hub API states.
- **Access token.** A Hugging Face access token is optional. It is stored as a generic password in the login Keychain and is sent only on `https` requests whose host is exactly `huggingface.co`. The check is repeated on every redirect, so the token is not forwarded to another host.
- **Recipe files.** Recipes can be imported from anywhere, so they are validated before use: the id is limited to lowercase letters, digits, dots, dashes and underscores, the repository must have the form `owner/name`, and file paths may not be absolute, contain backslashes, or contain empty, `.` or `..` segments, so that a recipe cannot write outside the model folder.
- **Recipe updates.** At most once a day the app fetches the list of curated recipes from this repository (`https://raw.githubusercontent.com/nomansheikh/kiln/main/recipes/index.json`, then each listed file) and caches the ones that pass the same validation as imported recipes. The request carries no token and no information about the user. A fetched recipe can change which files a model downloads and its settings, so every file it names is still verified against its SHA-256.
- **New versions.** At most once a day the app asks GitHub for the latest release of this repository (`https://api.github.com/repos/nomansheikh/kiln/releases/latest`) and, when its version is newer than the running app's, shows a notice in the sidebar. The request carries no token and no information about the user, and can be turned off in Settings. Nothing is downloaded or installed: the notice only opens the release page in the browser, and only when that page is an `https` address on `github.com`.
- **Helper processes.** Generation runs in `kiln-engine`, `kiln-whisper`, `kiln-audio` and `kiln-trellis`, bundled helpers that the app launches and talks to over stdin and stdout with line-delimited JSON. They do not listen on the network. A helper is started with a short list of environment variables (`HOME`, `TMPDIR`, `USER`, `LOGNAME`, `LANG` and a fixed `PATH`), not the app's own environment, so an access token in the environment such as `HF_TOKEN` does not reach it. The app reads only the files it asked a helper to write: a result that names any other file is refused and the helper is stopped.

In scope, for example: a way to make the token leave the device or reach a host other than huggingface.co; a recipe or Hub response that causes a file to be written or deleted outside Kiln's folders; a download that is accepted despite a checksum mismatch; a flaw in the app-to-helper protocol; a way for a helper to read or write outside the folders listed below, or to reach the network.

## Model files are untrusted data

Model weights are third-party files that Kiln does not author, review or distribute. They are parsed by [stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp), [whisper.cpp](https://github.com/ggml-org/whisper.cpp), [audio.cpp](https://github.com/0xShug0/audio.cpp) and [trellis.cpp](https://github.com/pwilkin/trellis.cpp) inside the helper processes. A generated 3D object is a file too: the app reads it with its own reader (`MeshFile`), which checks every offset against the file's length, and not with a general model importer. A checksum confirms that a file is the one the recipe names; it does not make the file safe.

So that a file built to exploit a parser bug gains as little as possible, each helper enters a sandbox before it reads anything ([`Engine/sandbox.h`](Engine/sandbox.h)). Inside it, a helper:

- cannot use the network
- cannot start another program or fork
- cannot read anything under `/Users` or `/Volumes` except the models folder and its own scratch folder (it can still see that a path exists)
- cannot write anywhere except its scratch folder in the temporary directory and the system's per-user cache folder, where Metal keeps compiled shaders
- cannot send Apple events or reach the pasteboard

If the sandbox cannot be entered, the helper exits instead of running without it.

What this does not cover, so that it is not mistaken for more than it is:

- The sandbox removes rights from a list; it is not a list of the few things a helper may do. System files outside `/Users` and `/Volumes` stay readable, and most system services stay reachable. Metal's needs are not documented and change between macOS versions, which is why the stricter form was not used.
- A helper can read every downloaded model, not only the one it is running.
- The app itself is not sandboxed. It does not parse model files, but it does read what a helper wrote: raw pixels, raw samples or text, each checked for the expected size.
- It relies on `sandbox_init`, which Apple has deprecated without a replacement for command-line tools.

Only download models from sources you trust. Memory-safety bugs in model parsing belong to the engine projects or ggml and are best reported there. Report them here as well if Kiln makes them easier to reach or worse in effect.

## Out of scope

- The content or licence of models downloaded by the user.
- Issues that require an attacker to already control the user's account or machine.
- Vulnerabilities in macOS or in Hugging Face's services.
