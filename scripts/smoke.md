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
4. **Stop & Transcribe** → status walks through transcribe → diarize → merge → summarize.
5. **History…** → select the call:
   - Transcript shows interleaved `Me` / `Speaker N` turns with `[HH:MM:SS]` timecodes.
   - Summary shows Summary / Agreements / My tasks.
   - Rename a `Speaker N` → transcript re-renders with the name.
   - Copy / Export… / Open Folder all work.

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
