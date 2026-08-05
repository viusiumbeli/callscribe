# CallScribe

Local, on-device call transcription for macOS (Apple Silicon). Records your
microphone and the system audio of a call on two separate tracks, transcribes
both fully offline with WhisperKit, diarizes remote participants with FluidAudio,
merges everything into a timecoded per-speaker transcript, and produces a
summary + action-item checklist via the local `claude -p` CLI.

See [DESIGN.md](DESIGN.md) for the full design.

## Build (command-line only — no Xcode required)

Needs the Command Line Tools toolchain (Swift 6+), macOS 15+.

```sh
make cert     # one-time: self-signed "CallScribe Dev" signing identity
.build/release/callscribe setup   # optional: fetch the model (~1.5 GB) up front
make run      # build, bundle, sign, and launch the menubar app
```

Other targets: `make build` (compile), `make test` (unit suite), `make app`
(assemble+sign the `.app`), `make install` (copy to ~/Applications),
`make golden` (opt-in pipeline regression test).

### Why a self-signed certificate?

macOS ties TCC permission grants (Microphone, System Audio) to a signed app's
*designated requirement*. Ad-hoc signing pins the binary's hash, so every
rebuild would re-prompt. `make cert` creates a self-signed identity in a
dedicated keychain; signing with it yields a certificate-based designated
requirement that stays constant across rebuilds, so grants persist. The cert
is untrusted (no Gatekeeper), which is fine for a local unnotarized build.

## CLI

The same binary is also a CLI, so every pipeline stage is testable without the UI:

```sh
callscribe record [--duration N] [--language ru|en]   # record a call
callscribe pipeline <call-folder>                     # transcribe→diarize→merge→summarize (resumable)
callscribe transcribe|diarize|merge|summarize <folder>  # individual stages
callscribe probe [--seconds N]                        # capture/permission smoke test
```

Calls are stored as plain folders under `~/Documents/CallNotes/<timestamp>/`
(`mic.wav`, `system.wav`, `transcript.md`, `summary.md`, `meta.json`).

## Architecture

- **CallScribeCore** — pure, dependency-free: the merge algorithm, transcript
  model, Markdown rendering, summary-prompt parsing, storage. Fast to unit-test.
- **CallScribeEngine** — audio capture (AVAudioEngine mic + Core Audio process
  tap for system audio), WhisperKit, FluidAudio, the `claude -p` summarizer,
  and the resumable `PipelineRunner`.
- **callscribe** — the executable: ArgumentParser CLI + SwiftUI menubar app.

## Status

MVP (design Phase 1). No live draft yet. See `scripts/smoke.md` for manual QA.
Known limitation: if the system output device changes mid-call (e.g. AirPods
connect), the tap can go silent; the stall watchdog ends the session cleanly.
