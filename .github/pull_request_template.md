## What changed and why

<!-- A short summary of the change and the problem it solves. Link the issue if there is one. -->

## How it was checked

<!-- Say what you actually ran. Delete the lines that do not apply and add anything else you did. -->

- [ ] `swift test` passes
- [ ] Built and ran the app
- [ ] Screenshots attached (for changes to what the app looks like)

Mac used (chip and memory), if you generated an image:

## Recipe checklist

<!-- Only for pull requests that add or change a file in recipes/. Delete this section otherwise. -->

- [ ] The description links the model card (or other primary source) the settings come from
- [ ] The file is `recipes/<id>.json` and its name equals the recipe `id`
- [ ] `engine` is `sd.cpp`
- [ ] Every component has `revision`, `size_bytes` and `sha256`, taken from the Hub API for that repo and file
- [ ] `license_note` is accurate: it names the license of each component and any restriction such as non-commercial use
- [ ] `min_memory_gb` is a value I tested, or a conservative one and I have said so above
