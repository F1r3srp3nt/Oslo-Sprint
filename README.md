![HCG × Oslo Sprint 2026 banner: "Distil + Relay — one weekend, two builds", over the Oslo waterfront at night](docs/assets/hcg-oslo-sprint-2026.png)

# Oslo-Sprint

Programs made during Oslo Sprint 2026. Each product is self-contained in its own folder, and the products share no code. Distil and Relay are Swift packages; Presentation Studio is a TypeScript web app.

| Folder | Product | What it is |
|---|---|---|
| [`distil/`](distil/README.md) | **Distil** | macOS app that selects the context a model needs for a task. It shows every decision and compares answers from the full and the reduced prompt. [Read the Distil README](distil/README.md) · [screenshots](distil/README.md#screenshots) |
| [`relay/`](relay/README.md) | **Relay** | macOS technical assistant for the Wybe Night Shift, Holio warehouse and ElevenLabs side challenges, with a headless runner. [Read the Relay README](relay/README.md) · [screenshots](relay/README.md#screenshots) |
| [`presentation-studio/`](presentation-studio/README.md) | **Presentation Studio** | Web app that turns uploaded images and a brief into an editable PowerPoint deck, with an optional spoken brief and slide narration through ElevenLabs. [Read the Presentation Studio README](presentation-studio/README.md) |

All names are working names.

## Requirements

- macOS 14 or later and Xcode 15 or later (Swift 5.9+) for the macOS apps.
- The core libraries and tests of Distil and Relay also build with any Swift 5.9+ toolchain on Linux.
- Distil and Relay use no third-party packages.
- Presentation Studio needs Node.js 22.12 or newer and npm. Its dependencies are listed in `presentation-studio/package.json`.

## Build and test

**Distil**

```sh
cd distil
swift test                       # core tests
bash scripts/run-latest.sh       # build dist/Distil.app, quit any running copy, open the new one
swift run Distil                 # run from SwiftPM (macOS)
```

In Xcode, open `distil/Package.swift` and run the **Distil** scheme. The internal package and module names are still `TokenLab*`; the bundle identifier is unchanged.

**Relay**

```sh
cd relay
./scripts/test.sh                # swift build + swift test
./scripts/build-app.sh           # local build/Relay.app with microphone usage text
swift run Relay                  # run the app from Terminal (macOS)
swift run relay-runner help      # headless runner (macOS or Linux)
```

**Presentation Studio**

```sh
cd presentation-studio
npm install
cp .env.example .env              # optional: add provider keys
npm run dev                       # open http://127.0.0.1:5173
npm test                          # unit and API tests
npm run test:e2e                  # browser end-to-end test (Playwright + Chromium)
```

Each product's README has full instructions, its verification status, its limitations and a first-launch checklist.

## Status

- **Linux:** the core libraries and tests of both products build and pass on Linux.
- **macOS:** GitHub Actions also builds both macOS apps on a macOS 15 runner, launches them and saves window screenshots ([`.github/workflows/`](.github/workflows/)). The screenshots in each product README come from those runs.
- **Not yet tested on a Mac:** interaction, speech, and accessibility have not been checked by a person on a Mac.
- **Presentation Studio:** unit, API and browser end-to-end tests pass on Linux against mock providers. Real Anthropic and ElevenLabs calls, and opening exports in Microsoft PowerPoint, have not been verified yet.

See each product's README for details.

## Working here

- All Distil work goes in `distil/`, all Relay work goes in `relay/`, and all Presentation Studio work goes in `presentation-studio/`.
- Keep each product's source, tests, scripts and documentation inside its folder. Shared repository files belong at the root.
- Never commit credentials, build output (`.build/`, `build/`, `dist/`, `node_modules/`) or local settings (such as `presentation-studio/.env`). For Relay, run `relay/scripts/check-no-secrets.sh` before committing.
