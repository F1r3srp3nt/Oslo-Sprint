# Presentation Studio: macOS

No build uploaded yet.

macOS (Apple Silicon) builds exist, but none is **in this folder**: the ZIP (about 118 MB) and the DMG (about 122 MB) are both larger than the 100 MB GitHub accepts in a normal push (see [Adding a build](../../README.md#adding-a-build)). You can get them in two ways:
- **CI artifact:** the `desktop-macos` job of the [Presentation Studio workflow](../../../.github/workflows/presentation-studio.yml) uploads the `.app` ZIP, the DMG, screenshots and test results as the artifact `presentation-studio-macos`. Artifacts are kept for 14 days.
- **Build it yourself** with the commands under [Build it yourself](#build-it-yourself).

Builds and their status (**not uploaded here**):

| File | Version | Architecture | Build date | Source commit | Verification status |
|---|---|---|---|---|---|
| `Presentation-Studio-0.1.0-mac-arm64.zip` and `Presentation-Studio-0.1.0-arm64.dmg` from the CI artifact of [run 42483506768](https://github.com/F1r3srp3nt/Oslo-Sprint/actions/runs/42483506768) | 0.1.0 | arm64 | 2026-11-08 | `7502a0b` | Built and ad-hoc signed on macOS 15.8 (Apple Silicon, GitHub Actions). `codesign --verify --deep --strict` passed, `hdiutil verify` passed, and the ZIP tested intact. Launched with `open` (LaunchServices) and still running after 10 s with no crash report; no processes left afterwards. Packaged-app end-to-end test passed 15/15, including the macOS Keychain. |
| `Presentation-Studio-0.1.0-mac-arm64.zip` cross-built in the development session (SHA-256 `523ef8033843425c44702435fd75300a901d9101caf0fa4072af0cd522b733b8`) | 0.1.0 | arm64 | 2026-11-08 | `3209380` | Cross-built on Linux and ad-hoc signed with rcodesign; bundle structure checked. **Not launched on a Mac: not verified.** It predates the minimum-window-size layout fix (`7502a0b`). Prefer the CI build. |

The Linux-built ZIP was made with `zip -y`, which keeps the framework symlinks. Builds made on a Mac (`npm run desktop:dist:mac`, or the CI job) use electron-builder's own ZIP and DMG.

**About the app.** Presentation Studio is a desktop app that turns your images and a brief into an editable PowerPoint deck. It is a standalone Electron app. Double-click it in Finder and it opens its own window. It needs no Terminal, browser tab, development server or separate Node/npm install. Source: [`presentation-studio/`](../../../presentation-studio/).

<img src="app-icon.png" width="96" alt="Presentation Studio icon: a cyan diamond on a midnight-navy rounded square">

## Status at a glance

| | Result |
|---|---|
| macOS arm64 `.app`, ZIP and DMG built and signed | **Yes**, on macOS 15.8 Apple Silicon in CI ([run 42483506768](https://github.com/F1r3srp3nt/Oslo-Sprint/actions/runs/42483506768)). Apple's `codesign --verify --deep --strict` passed and `hdiutil verify` passed. |
| Launched on a real Mac | **Yes**, in CI: opened with `open` (LaunchServices, as Finder does), still running after 10 s with no crash report, and no processes left afterwards. |
| Packaged app tested end to end on macOS | **Yes**: 15/15 checks in CI, including keys stored in the macOS Keychain and a layout check at the 1100×700 minimum window size. |
| Same test on Linux | **Yes**: 15/15, both locally and in CI, with and without a secure key store. |
| Checked by a person on a Mac | **No.** No one has yet double-clicked a *downloaded* copy in Finder (Gatekeeper's quarantine prompt), answered the microphone prompt, or used the menus by hand. |

## Install and launch

**Requires** macOS 12 Monterey or later on Apple Silicon (M1 or newer).

1. Unzip `Presentation-Studio-0.1.0-mac-arm64.zip`, or open the DMG, and move **Presentation Studio.app** to **Applications**.
2. The app is ad-hoc signed and **not notarized**. The first time, Control-click (right-click) it in Finder and choose **Open**, then **Open** again. After that, double-click works as usual.
   - If macOS says the app "is damaged and can't be opened", the download was quarantined. Remove the flag once: `xattr -dr com.apple.quarantine "/Applications/Presentation Studio.app"`
3. Presentation Studio opens its own window. Everything works offline except AI generation and voice, which call their providers.

**Optional providers.** Open **Setup** (the *AI · Voice* button in the top bar, or **Presentation Studio › Setup & Providers…**, ⌘,). Paste an Anthropic key (AI slide writing) and/or an ElevenLabs key (spoken brief and narration), then click **Verify connection**. Without keys you can still import images, build a deck from a template, edit, present, save, reopen and export PowerPoint. Setup explains what each key enables and links to the official key pages.

## What the app does

- **Images:** File › Import Images… (⌘I) opens the native picker, or drag images onto the window. PNG, JPEG and WebP are accepted; files are checked by content, not by extension. Originals are kept byte-for-byte.
- **Brief and generation:** AI generation (Anthropic) when a key is saved, or template mode without AI.
- **Editor:** reorder, duplicate and delete slides; seven layouts; fit/fill/crop images; speaker notes; overflow warnings.
- **Projects:** File › Save Project (⌘S) uses the native save dialog the first time, then saves in place. Save Project As… is ⇧⌘S. Open Project… is ⌘O. Projects are `.pstudio` files and include images and narration audio.
- **Export:** File › Export PowerPoint… (⌘E) writes an editable `.pptx` through the native save dialog. *Export › PowerPoint + narration (.zip)* appears once slides have narration.
- **Present:** ⌘↵ or **▶ Present**, with optional narration playback.
- **Voice (ElevenLabs):** spoken brief (records only while you choose to; macOS asks for microphone permission the first time) and per-slide narration.

## Where things are stored

| What | Where |
|---|---|
| Settings (model names, encrypted keys) | `~/Library/Application Support/Presentation Studio/settings.json` |
| Encryption key protecting the API keys | macOS Keychain item **"Presentation Studio Safe Storage"** (Electron `safeStorage`) |
| Diagnostic log (no keys, no content) | `~/Library/Application Support/Presentation Studio/logs/main.log` |
| Your projects and exports | Wherever you choose in the save dialog (Documents by default) |

**To uninstall:** delete the app, the `~/Library/Application Support/Presentation Studio` folder, and the Keychain item above.

## How it is built

| | |
|---|---|
| Runtime | Electron 45.2.3 (bundled Chromium and Node; nothing else to install) |
| Backend | The project's Express API runs **inside the app process** on `127.0.0.1`, on a port the OS picks at each launch. It starts with the app and stops when the app quits, so there is no separate process to orphan and no fixed port to conflict. |
| API protection | Every API call needs a per-launch random token. The app's main process adds it to requests from its own window, so other programs and web pages cannot use the local API or spend your provider credits. |
| Renderer | Sandboxed, context-isolated, no Node integration, strict Content Security Policy, navigation locked to the app. External links open in your browser only for the provider setup sites. |
| Desktop operations | Exposed through a small preload bridge: open/save/export dialogs, image import, credentials, menu commands. Every request is checked to come from the app's own page and is validated, and file paths always come from a native dialog. |
| Keys | Entered in Setup; encrypted with `safeStorage` (Keychain) before being written. The page can set or remove a key but never read it back. Keys are never bundled, logged, or written into projects or exports. No `.env` file is read. |
| Single instance | Opening the app a second time focuses the running window instead of starting another backend. |
| Unsaved changes | Closing the window with unsaved changes asks first. |
| Startup errors | If the built-in server can't start, the window shows the error with **Try again**, **Show log** and **Quit**. |
| Packaging | electron-builder 26.18.0. Everything is pre-bundled with esbuild (`desktop-dist/main.mjs`) and Vite (`dist/`), so the app ships no `node_modules`. |
| Electron fuses | RunAsNode off, NODE_OPTIONS off, only loads its own `app.asar`, cookie encryption on. Inspector flags stay enabled so the automated test can drive the packaged app. |
| Bundle | `com.oslosprint.presentationstudio`, version 0.1.0, `LSMinimumSystemVersion` 12.0, category Productivity, `NSMicrophoneUsageDescription` set, icon `icon.icns`. |
| Signing | Ad hoc (no Apple Developer ID). Not notarized. |

**Icon.** No Presentation Studio icon was supplied anywhere in this repository or on this machine. `app-icon.png` was drawn to match the in-app ◆ logo by `presentation-studio/scripts/make-icon.py`. To use another icon, replace `presentation-studio/desktop/build/icon.icns` and `icon.png`, then rebuild.

## Build it yourself

From `presentation-studio/`:

| Goal | Command | Output |
|---|---|---|
| Run the desktop app from source | `npm install`, then `npm run desktop:start` | Opens the app window |
| Build `.app` + ZIP + DMG **on a Mac** | `npm run desktop:dist:mac` | `release/mac-arm64/Presentation Studio.app`, `release/Presentation-Studio-0.1.0-mac-arm64.zip`, `release/Presentation-Studio-0.1.0-arm64.dmg` |
| Build `.app` + ZIP **on Linux** (no DMG) | `cargo install apple-codesign --locked`, then `npm run desktop:dist:mac-on-linux` | `.app` and ZIP, ad-hoc signed with rcodesign |
| Package for the current OS (test build) | `npm run desktop:pack` | `release/<os>-unpacked/` |
| Test the packaged app | `npm run test:desktop` (Linux: `xvfb-run -a npm run test:desktop`) | `test-output/desktop/` (results and screenshots) |

The build artifacts are not committed (the ZIP is 117 MB). This session's build produced `presentation-studio/release/Presentation-Studio-0.1.0-mac-arm64.zip`, SHA-256 `523ef8033843425c44702435fd75300a901d9101caf0fa4072af0cd522b733b8`.

## Verification

### Verified on macOS (GitHub Actions `desktop-macos`, macOS 15.8, Apple Silicon)

[Run 42483506768](https://github.com/F1r3srp3nt/Oslo-Sprint/actions/runs/42483506768) at `7502a0b`. Every step of the job passed:
1. `npm run desktop:dist:mac` built `Presentation Studio.app`, the ZIP and the DMG, ad-hoc signed by electron-builder with Apple's `codesign`.
2. `codesign --verify --deep --strict --verbose=2`: "valid on disk" and "satisfies its Designated Requirement", with every helper app validated.
3. The Info.plist shows `com.oslosprint.presentationstudio`, 0.1.0, `LSMinimumSystemVersion` 12.0 and the microphone usage text. `lipo` reports arm64.
4. The DMG checksum is **VALID** (`hdiutil verify`). The ZIP shows "No errors detected" (`unzip -t`).
5. The repository's `launch-check.sh` (also used for Distil and Relay) opened the app through LaunchServices: "PASS: Presentation Studio launched with open and was still running after 10 s; no crash report."
6. No `Presentation Studio.app` processes remained afterwards.
7. `npm run test:desktop` against the Mac build passed **15/15**. The checks are listed below. Key storage was the macOS Keychain, keys survived a restart encrypted, and the layout check passed at 1100×700 (no sideways overflow; title field 210 px).
8. A native window screenshot was captured with the title bar. It is in the run's artifact, not in this folder: this development session's network policy blocks the storage host that serves that run's artifacts.

An earlier run on `4acf9cb` passed the same steps. Its screenshots showed the top bar's title field collapsed and the slide list overflowing at the 1100×700 minimum window size, which `7502a0b` fixed and now tests.

### Verified in the development environment (Linux container, Electron 45.2.3, Xvfb)

The packaged app (electron-builder `--dir`, with the same `app.asar` and fuses as the Mac build) was driven by `e2e/desktop-e2e.mjs`: **15/15 passed** without a secure key store, and **15/15 passed** with a Secret Service keyring.

1. No development server running (ports 5173 and 8787 free, no app process running).
2. Launches, opens its own window titled *Presentation Studio*, served from `127.0.0.1` on an OS-chosen port. `app.isPackaged` is true.
3. The renderer has no `require` or `process`. The bridge exposes exactly its 13 documented members. The API returns **403** to a caller outside the window, and 200 inside it.
4. **No keys:** Setup shows the guidance and key fields with no `.env` instructions. AI generation is disabled, the spoken brief says it is not configured, and manual work continues.
5. **Import images** through the native open dialog: PNG, JPEG and WebP accepted; a text file named `.png` rejected with a message.
6. Template deck built, then edited, a slide added and slides reordered.
7. **Save** through the native save dialog produces a valid `.pstudio`. A second **Save** writes in place without a dialog.
8. **New**, then **Open** the saved project through the native open dialog: title, slide order, text and notes restored.
9. **Export PPTX** through the native save dialog. The file opens in python-pptx (6 slides, edited text, notes, WebP exported as PNG) and LibreOffice converts it to PDF.
10. Presentation mode opens, navigates and closes.
11. **In-app keys** (against local **mock** Anthropic and ElevenLabs servers): an invalid key is rejected with a message; valid keys are saved and both connections verify. The page cannot read a key, and `settings.json` contains no plain-text key.
12. The startup-error page renders inside the app, and its CSP-hashed script runs.
13. A second launch exits and hands over to the running window, so there is one backend.
14. **Quit:** the backend port closes, no app processes remain, and the log records "backend stopped" with no keys in it.
15. **Relaunch:** with the keyring, keys persist encrypted. Without secure storage, keys are gone after quit, as designed.

Also verified here:
- 47 unit and API tests, including the token gate, CSP and runtime key changes.
- The web-mode browser e2e (25/25).
- The macOS bundle structure: arm64 Mach-O, Info.plist keys, icon, helper apps, fuses, and an ad-hoc code directory with the right identifier.
- The `app.asar` contains only the bundles (no `node_modules`, no source, no keys).
- The ZIP keeps symlinks.

Screenshots in [`screenshots/`](screenshots/) are from the **Linux** packaged build of the same app, captured before the minimum-window-size fix at a larger window. The window contents are the same on macOS; only the window frame differs. Native macOS captures are in the CI artifact (see above).

### Still not verified

- **A person using the app on a Mac:**
  - Gatekeeper's prompt when opening a *downloaded* (quarantined) copy (CI opened a locally built copy);
  - the microphone permission prompt;
  - native menus and dialogs used by hand (the test answers dialogs programmatically).
- **The Linux-cross-built ZIP** from the development session on a Mac. The CI-built ZIP and DMG were checked instead.
- **Real Anthropic and ElevenLabs calls** (no keys; tested against mock servers).
- **Opening the export in Microsoft PowerPoint.**

### What the macOS CI job does

The `desktop-macos` job in `.github/workflows/presentation-studio.yml` runs on every pull request and push to `main` that touches `presentation-studio/`, on a macOS 15 Apple Silicon runner. It:
1. builds the `.app`, ZIP and DMG with Apple's `codesign`;
2. checks them with `codesign --verify --deep --strict`, `plutil`, `lipo`, `hdiutil verify` and `unzip -t`;
3. opens the app through LaunchServices with `open`, as Finder does, using the repository's existing `launch-check.sh`, and checks that it stays up with no crash report;
4. checks that no processes remain;
5. runs the same 15-step end-to-end test against the Mac build;
6. saves a window screenshot;
7. uploads the DMG, ZIP, screenshots and results.

A `desktop-linux` job repeats the Linux results above.

## HCG Executable Maker

Maker cannot build this app yet: it recognises Electron projects but reports them as unsupported. See [EXECUTABLE-MAKER-HANDOFF.md](EXECUTABLE-MAKER-HANDOFF.md) for the evidence and the exact adapter changes Maker would need.

Back to [Presentation Studio submissions](../README.md).
