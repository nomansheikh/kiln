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

Kiln is a macOS app with a separate local helper process. The app is not sandboxed; it and its helper run with the user's privileges.

- **Downloads.** Model files are downloaded from `https://huggingface.co` over HTTPS. A downloaded file is checked against the expected size and SHA-256 checksum when the recipe or the Hub API provides them; curated recipes always pin a revision, size and checksum for every file.
- **Access token.** A Hugging Face access token is optional. It is stored as a generic password in the login Keychain and is sent only on `https` requests whose host is exactly `huggingface.co`. The check is repeated on every redirect, so the token is not forwarded to another host.
- **Recipe files.** Recipes can be imported from anywhere, so they are validated before use: the id is limited to lowercase letters, digits, dots, dashes and underscores, the repository must have the form `owner/name`, and file paths may not be absolute, contain backslashes, or contain empty, `.` or `..` segments, so that a recipe cannot write outside the model folder.
- **Recipe updates.** At most once a day the app fetches the list of curated recipes from this repository (`https://raw.githubusercontent.com/nomansheikh/kiln/main/recipes/index.json`, then each listed file) and caches the ones that pass the same validation as imported recipes. The request carries no token and no information about the user. A fetched recipe can change which files a model downloads and its settings, so every file it names is still verified against its SHA-256.
- **Helper process.** Generation runs in `kiln-engine`, a bundled helper that the app launches and talks to over stdin and stdout with line-delimited JSON. It does not listen on the network.

In scope, for example: a way to make the token leave the device or reach a host other than huggingface.co; a recipe or Hub response that causes a file to be written or deleted outside Kiln's folders; a download that is accepted despite a checksum mismatch; a flaw in the app-to-helper protocol.

## Model files are untrusted data

Model weights are third-party files that Kiln does not author, review or distribute. They are parsed by [stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp) inside the helper process. A checksum confirms that a file is the one the recipe names; it does not make the file safe. Running the parser in a separate process contains crashes, but the helper is not sandboxed, so only download models from sources you trust.

Memory-safety bugs in model parsing belong to stable-diffusion.cpp or ggml and are best reported to those projects. Report them here as well if Kiln makes them easier to reach or worse in effect.

## Out of scope

- The content or licence of models downloaded by the user.
- Issues that require an attacker to already control the user's account or machine.
- Vulnerabilities in macOS or in Hugging Face's services.
