# Relay

Relay is a technical assistant for three Oslo Sprint side challenges: **Wybe Night Shift**,
**Holio warehouse operations** and **ElevenLabs**. It shows what it heard, what it understood,
what it plans to do, what it attempted, and what succeeded, failed or needs attention.

*Relay* is a working name. The project is self-contained in `relay/`, has no third-party
dependencies, and does not use or touch `token-lab-macos/` (Distil).

> Eligibility for more than one challenge prize has **not** been confirmed. That is a
> question for the organisers.

## Status of the first milestone

| Part | State |
|---|---|
| Core engine (tasks, log, redaction, runner, training) | Builds; 68 XCTests pass on Linux (Swift 6.0.3) |
| `relay-runner` CLI | Builds and runs on Linux; should be identical on macOS |
| Warehouse training (text) | Complete and deterministic, with a **synthetic** procedure in en / nb / pl |
| Wybe Night Shift | **Simulation only.** The live protocol hasn't been obtained, and live mode sends nothing |
| ElevenLabs STT / TTS adapters | Implemented and tested against a fake transport. **Never called the real service** (no key, no network route) |
| macOS SwiftUI app | Source complete. **Not compiled yet** because no macOS machine was available |

## Requirements

- macOS 14 or later with Xcode 15.3+ (Swift 5.9+) for the app.
- Any Swift 5.9+ toolchain (macOS or Linux) for the core, the tests and `relay-runner`.

## Build and run on a Mac

```bash
cd relay
./scripts/test.sh                      # swift build + swift test (also builds the app target)

# Option A: build a proper .app (adds the microphone usage text; signs ad hoc)
./scripts/build-app.sh
open build/Relay.app

# Option B: run straight from SwiftPM in Terminal (mic permission is asked for Terminal)
swift run Relay

# Xcode: opening Package.swift and running the "Relay" scheme works for everything except
# push-to-talk — a bare executable has no Info.plist/NSMicrophoneUsageDescription, and macOS
# terminates apps that request the microphone without one. Use Option A for voice.
```

## Headless runner (macOS or Linux)

```bash
cd relay
swift run relay-runner help
swift run relay-runner wybe-sim --shifts 10 --faults typical      # SIMULATED scores only
swift run relay-runner wybe-sim --seed 7 --faults harsh --verbose --json runs/sim.json
swift run relay-runner wybe-sim --stop-after 5                    # demonstrates the stop control
swift run relay-runner wybe-sim --stop-file /tmp/relay.stop       # touch the file to stop
swift run relay-runner wybe-live                                  # explains what's missing; sends nothing; exit 2
swift run relay-runner warehouse --lang pl                        # interactive text training
./scripts/demo-warehouse.sh                                       # scripted training session
swift run relay-runner export-procedure > my-procedure.json
```

Ctrl-C during `wybe-sim` stops before the next action. Pressing it a second time exits at once.

## Using the app

| Section | What it does |
|---|---|
| **Assistant** | Type, or hold the mic button to talk. A transcript is never acted on until you review it and press *Send transcript*. Each request shows a card with Heard / Understood / Plan / Attempted / Result. *Approve* or *Decline* appear for actions that need approval, and *Speak* / *Stop playback* control spoken replies. |
| **Tasks** | Queue with validated state changes: escalations, approvals and tasks you add. |
| **Warehouse Training** | Step card with critical warnings first, a language switcher, *I understand the safety warning* (required before *Next*), questions answered with the supporting instruction quoted, clarification, and escalation. |
| **Wybe Runner** | Seed, shift count, fault level, Run / Stop. Shows the latest observation, the current decision rationale, the full action history with attempts, and per-shift and average **SIMULATED** scores. Live mode is locked. |
| **Activity** | Redacted, append-only event log with filters and JSON Lines export. |
| **Settings** | ElevenLabs API key (Keychain), connection test, voice ID, models, speech behaviour, plus the status of reasoning and Wybe. |

Text-only fallback: with no ElevenLabs key, everything except push-to-talk and spoken replies
works. The status pills read "Not configured — text only".

## What is simulated, what is real

- **Simulated:** the entire Night Shift environment (`SimulatedNightShift`), including its
  `sim.` command vocabulary, its tasks, its points and its faults. Every score it produces is
  labelled SIMULATED.
- **Synthetic:** the warehouse procedure and its translations. It is demonstration material,
  not Holio documentation.
- **Real but unexercised:** the ElevenLabs HTTP calls. They will run with your key, but have
  not run yet.
- **Not implemented, by design:** the live Wybe adapter, a Holio integration, and any
  language-model reasoning.

## Still needed from outside

1. **Wybe:** the official contract (API, auth, command discovery, observation and action formats,
   idempotency, rate limits, scoring). It probably needs team registration at
   `https://nightshift-board.wybe.me/join`, which is your call. The join page could not be
   read from the build environment because that host is blocked there. See `docs/WYBE.md`.
2. **ElevenLabs:** your API key (entered in Settings → Keychain) and a voice ID. Before the
   demo, check the endpoints and model IDs against https://elevenlabs.io/docs. See
   `docs/ELEVENLABS.md`.
3. **Optional:** a language-model provider, if open-ended question answering is wanted
   (`docs/WAREHOUSE.md`).

## Acceptance checklist (Mac)

- [ ] `./scripts/test.sh` passes: 68 tests, and the `Relay` app target compiles.
- [ ] `./scripts/build-app.sh && open build/Relay.app` opens a dark window with six sections.
- [ ] Assistant, typed `start`: the card shows Heard / Understood / Plan / Attempted / Result, and Step 1/7 has the SAFETY line first.
- [ ] `next` asks for confirmation. `understood` and then `next` show Step 2/7.
- [ ] Training: a Polish question about a leak (`Co zrobić, gdy widzę wyciek?`) is answered in Polish with S3 quoted, after switching the language to Polski.
- [ ] `How do I handle frozen goods?` escalates, and a *Needs attention* task appears with a badge on Tasks.
- [ ] `run the simulation` waits for Approve. Decline cancels the task, and nothing runs.
- [ ] Wybe Runner, Run: the banner says SIMULATION, actions stream in, and Stop (⌘.) halts before the next action. Scores read "SIMULATED … not a challenge result".
- [ ] Settings, no key: speech pills say "Not configured — text only" and the mic button is disabled.
- [ ] Settings, a wrong key → Test connection shows "Failed: ElevenLabs rejected the API key (401)", and the key is not visible anywhere in Activity or an export.
- [ ] Settings, a valid key and voice: Test connection shows "Connected (verified)". Hold the mic, speak, release, edit the transcript and send. The reply is spoken, and *Stop playback* stops it.
- [ ] `./scripts/check-no-secrets.sh` passes.

## Third-party dependencies

None. Relay uses Foundation, SwiftUI, AppKit, AVFoundation, Security (Keychain) and XCTest
only. ElevenLabs is reached over its public REST API with `URLSession`, not through an SDK.

More detail: `docs/ARCHITECTURE.md`, `docs/WYBE.md`, `docs/WAREHOUSE.md`, `docs/ELEVENLABS.md`.
