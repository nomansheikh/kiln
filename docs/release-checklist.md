# Release checklist

What to check before a release. The core library and the app's stores have unit tests; the views have none, so the second half of this page is done by hand in the running app. Tick each line, and write down the Mac and the macOS version it was done on.

## Run

```sh
swift test
python3 scripts/recipe.py check
./scripts/check-conventions.sh
./scripts/build-engine.sh
xcodegen generate
xcodebuild -scheme Kiln -configuration Debug -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO test
xcodebuild -scheme Kiln -configuration Release -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO build
```

- [ ] All seven end without an error, and `recipe.py check` ends with `OK`.
- [ ] CI is green on the commit being released.

## Click through

Use the build that will be released, not a debug build.

- [ ] Before starting, with Kiln closed, remove the helpers' scratch folders with `rm -rf "$TMPDIR"kiln-*`, so each helper starts as it does on a new Mac. Files left there by an earlier build have hidden a failure before.

### First launch

- [ ] The app opens to the Generate screen with no model, and points to Models.
- [ ] Settings shows the chip, the memory and the folders, and About has a working "View on GitHub" button.

### Models

- [ ] Download a small model (for example Whisper Base). Progress, speed and time left show; pause and resume work.
- [ ] Quit the app during a download, open it again and resume: the download continues instead of starting over.
- [ ] Switch between All, Images, Speech to text and Text to speech: the list changes at once, without jumping.
- [ ] Search by name, and by a Hugging Face repo id such as `owner/name`.
- [ ] Delete a downloaded model: the files are gone and the model shows "Download" again.

### Images

- [ ] Generate an image. A preview appears while it is sampling, the composer's border glows, and the result lands in the Gallery.
- [ ] Stop a generation part-way: it stops, and the next one works.
- [ ] Attach an image and generate from it at each of the three strengths.
- [ ] In the Gallery, "Reuse Settings" fills the composer, and deleting an image moves it to the Trash.

### Speech to text

- [ ] With a Whisper model, press Record: macOS asks for the microphone the first time, the meter moves while you speak, Cancel throws the recording away, and Done attaches it. Refuse the permission once and check the message says where to allow it.
- [ ] Attach an audio file to a Whisper model and send it: the transcript appears as rows, each with the time it starts at.
- [ ] Click a row: the recording plays from there and the row being spoken is highlighted. Switch to one paragraph and back.
- [ ] Save the transcript as text and as subtitles (.srt), and open the subtitles beside the recording in a player.
- [ ] Choose a language, and send again.

### Text to speech

- [ ] Send plain text with PocketTTS. The clip plays, the waveform can be dragged, and the speed chip changes playback.
- [ ] Shift-Return adds a line; Return sends.
- [ ] Click into the composer, then click on empty space: the border goes back to normal. Click a chip or the send button: the composer keeps the keyboard.
- [ ] Write a two-speaker script (`Anna: …` and `John: …`). The names are coloured, the Speakers chip lists both, and each can be given a different voice. The clip has both lines and no names read aloud.
- [ ] With OmniVoice, "Design a voice…": add traits, make a sample, play it, save it. The voice appears under "My voices".
- [ ] With OmniVoice, give each speaker of a script a designed voice and send. With no voice chosen, sending is refused and the composer says who needs one.
- [ ] "Add a voice…" from a recording, with "Write Them for Me". Edit the voice's name and words afterwards.
- [ ] With VibeVoice, send a script with a saved voice for one speaker.
- [ ] Delete a clip and a voice: both go to the Trash, and "Put Back" in the Finder restores them.
- [ ] "Use this text again" on a clip fills the composer and restores its voices.

### 3D

- [ ] Drop a picture of one object on the 3D screen and send it at Standard detail: the stage shows the work, then the object, which turns until it is dragged.
- [ ] Switch between Colour, Clay and Wireframe, pause the turning and reset the view.
- [ ] Describe an object with no picture: an image model draws one, "Draw Another" draws again and "Make It 3D" makes the object.
- [ ] While an object is being made, open an earlier one from the shelf: the work goes on, and the new object is marked when it is ready.
- [ ] Stop an object part-way: the picture returns to the composer, and the next object works.
- [ ] With Pixal3D selected, Standard detail is not offered, and the object stands upright.
- [ ] Save an object as GLB, USDZ and OBJ, and open each in another program.
- [ ] "Make 3D" on a generated image, in a chat and in the gallery, opens the 3D screen with that image.

### When things go wrong

- [ ] Pick a model too large for the Mac and generate: the app says it ran out of memory and stays usable.
- [ ] While an image is being made, end the helper from Activity Monitor (`kiln-engine`): the app reports that the engine stopped, and the next image works.
- [ ] While a clip is being made, end `kiln-audio` the same way: the app takes it for a model that fails on the GPU and makes the clip again on the CPU, which is slower. The clip still arrives.
- [ ] Delete a model while it is selected: the screen falls back to another model or says none is installed.
- [ ] Turn the network off and open Models: the Hugging Face list fails with a readable message, and installed models still work.

### The release build itself

- [ ] On an account that has never run Kiln, open the disk image, drag the app to Applications and open it. Gatekeeper lets it open without a warning about an unidentified developer.
- [ ] Generate with each kind of model once. This is the check that the four helpers start inside their sandbox in a signed build.
- [ ] In Settings, "Check for new versions" is on; with it off, no request goes to `api.github.com`.
