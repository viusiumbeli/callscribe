# CallScribe manual smoke test

Audio capture and TCC prompts can't be verified in CI — run this by hand.

## One-time setup

```sh
make cert       # create the "CallScribe Dev" signing identity (dedicated keychain)
make setup 2>/dev/null || .build/release/callscribe setup   # download + prewarm the model (~1.5 GB, minutes)
```

## Fresh-permission onboarding

```sh
tccutil reset Microphone com.slavayus.callscribe
tccutil reset SystemAudioCapture com.slavayus.callscribe   # (or AudioCapture on older macOS)
make run
```

- Menubar shows the waveform icon, no Dock icon.
- Start Recording → macOS prompts for **Microphone** and **System Audio Recording**. Click Allow.
  (This one-time prompt is expected whenever the signing certificate changes.)

## End-to-end call

1. Join or play a call with at least two remote voices (Zoom/Meet/YouTube).
2. Menubar → **Start Recording**. Icon fills in; status shows elapsed time.
3. Talk for ~2 minutes (mix Russian + English to exercise language detection).
4. **Stop & Transcribe** → processing runs in the background (recording again is
   possible immediately); the call's row in the list walks through the stages
   ("Cleaning audio…" → "Transcribing…" → "Detecting speakers…" → "Merging…" →
   "Summarizing…").
5. In the main window (tray → **Open Window**), select the call:
   - Transcript shows interleaved `Me` / `Speaker N` turns with `[HH:MM:SS]` timecodes.
   - Summary shows Summary / Topics / Agreements / My tasks; topics expand.
   - Rename a `Speaker N` → transcript re-renders with the name.
   - Copy Transcript / Open Folder both work.

## Dictation

The gesture logic is unit-tested; the keyboard, the overlay and the paste are not.

```sh
tccutil reset Accessibility com.slavayus.callscribe
defaults delete com.slavayus.callscribe dictation.didPromptForAccessibility
make run
```

- Launch prompts for **Accessibility** and opens System Settings → enable CallScribe.
- Tray menu shows **Dictation — hold Right Shift**, checked. With the grant
  missing it also shows **Grant Accessibility Access…**.
- `.build/release/callscribe dictate --seconds 5` → prints what you said.
  Say nothing → `(nothing heard)`, *not* a lone `.` (Whisper renders silence as
  punctuation).
- In TextEdit: hold Right Shift, say a sentence, release. Overlay shows
  "Listening…" with a level bar that moves, then "Transcribing…", then the text
  appears at the cursor. `dictations.md` gains an entry, and the clipboard still
  holds whatever it held before.
- Repeat in Chrome, Slack and Terminal — the places `kAXSelectedTextAttribute`
  would have failed silently.
- **Focus is not stolen**: the frontmost app's title bar stays active the whole
  time the overlay is up. If it doesn't, the paste goes into CallScribe.
- **The typing guards** — the part that would be felt on every keystroke:
  - Type `Hello World` using Right Shift for both capitals → no overlay, no text.
  - Hold Right Shift ~1 s and release without speaking → "Too short." / "Nothing
    heard.", nothing pasted.
  - Hold ⌘ then Right Shift → nothing arms.
- Start recording a call, then hold Right Shift → "Recording a call — dictation
  is paused."
- Focus a password field and dictate → text is copied, not pasted, and says so.

### Regression guard: the app still takes input

Dictation once broke the *entire* UI (a global `NSEvent` monitor stopped the app
receiving mouse clicks on macOS 26 — see DESIGN.md 8b). Check both, every time
anything about the hotkey changes:

- With dictation **on**, click a project button in the main window: it responds.
- With dictation **on**, click the menu bar icon: the menu opens.

Both worked while dictation was off, so testing only with it disabled proves nothing.

### Dictations window

Tray → **Dictations…**, or the main window's toolbar button.

- Entries appear grouped by day, newest first; Russian renders correctly.
- Per-row copy → the icon flips to a checkmark for ~1.5 s; paste elsewhere matches.
- Search filters as you type (`localizedStandardContains`, so `план` matches
  regardless of case or accents). No matches → the search empty state.
- **Delete rewrites the file**, so check it doesn't take neighbours with it:
  ```sh
  cp ~/Library/Application\ Support/CallScribe/dictations.md /tmp/before.md
  # delete one entry in the window, then:
  diff /tmp/before.md ~/Library/Application\ Support/CallScribe/dictations.md
  ```
  Exactly four lines should go (heading, blank, body, blank) and nothing else.
- Dictate into another app with the window open → the new entry appears at the
  top without touching the window, carrying a language chip. Older entries have
  none, and must still list.
- Delete every entry → the "No dictations yet" state, and the file is left as
  just its `# Dictations` preamble.

## Persistence check (TCC survives rebuilds)

```sh
# after granting permissions once:
touch Sources/callscribe/Commands/VersionCommand.swift
make run          # rebuilds a new binary, same certificate
# Start Recording → should NOT re-prompt for permissions.
```

## Crash safety

```sh
.build/release/callscribe record &
sleep 20; kill -9 %1
afplay ~/Documents/CallNotes/<latest>/mic.wav   # still plays: header patched every ~5 s
```
