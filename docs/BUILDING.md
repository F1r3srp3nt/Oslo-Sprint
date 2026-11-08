# Building, packaging and launching Distil and Relay on a Mac

Both apps are Swift packages with a macOS-only SwiftUI app product. They are built with SwiftPM
scripts, not Xcode projects. Each package has the same five commands, run from its own folder
(`distil/` or `relay/`). The scripts locate their package from their own path, so they also work from
any other directory: `distil/scripts/run-latest.sh`.

| Command | What it does | Needs |
|---|---|---|
| `scripts/check-prerequisites.sh [test]` | Checks macOS, the selected developer directory, Swift, the macOS SDK, codesign, and (with `test`) XCTest. Prints the exact fix for anything missing. **Changes nothing.** | — |
| `scripts/test.sh` | Builds the sources, compiles the tests, runs them; says which of those failed. Never packages or launches. | Full Xcode (XCTest) on macOS; any Swift 5.9+ on Linux |
| `scripts/package.sh` | Compiles **only** the app product (no test targets) and assembles, signs and verifies the `.app`. | Command Line Tools or Xcode |
| `scripts/verify-launch.sh` | Opens the packaged `.app` with `--self-check`; the app reports what it loaded, then quits. | A packaged app |
| `scripts/run-latest.sh` | **One command:** package, then open exactly the new bundle and confirm it is running. Opens nothing if packaging failed. | Command Line Tools or Xcode |

| App | Product | Bundle | Bundle identifier | Version |
|---|---|---|---|---|
| Distil | `Distil` (target `TokenLabApp`, package `TokenLab`) | `distil/dist/Distil.app` | `dev.tokenlab.prototype` | 0.5.0 (5) |
| Relay | `Relay` (also the CLI product `relay-runner`) | `relay/build/Relay.app` | `com.oslosprint.relay` | 0.2.0 (2) |

"Command Line Tools or Xcode" for packaging: neither app uses macros or XCTest in its app code, so
the Command Line Tools should be enough. CI uses Xcode 16, though, so a Command Line Tools–only Mac
has **not** been verified yet.

Older names keep working: `distil/scripts/build-macos.sh` and `relay/scripts/build-app.sh` now call
`package.sh` (and no longer run the tests; `SKIP_TESTS` is ignored).

## Quick start

```bash
cd distil                                   # or: cd relay
scripts/check-prerequisites.sh test         # what this Mac has, and what is missing
scripts/run-latest.sh                       # build Distil.app and open it
scripts/test.sh                             # the tests (needs full Xcode)
```

## Telling failures apart

Every script names the stage that failed and says when nothing ran:

| Message | Meaning |
|---|---|
| `Not ready: … Nothing was built` | Setup problem. Follow the printed `fix:` lines. |
| `RESULT: tests NOT RUN. A prerequisite is missing` (exit 3) | Usually XCTest: Command Line Tools are selected. |
| `RESULT: tests NOT RUN. The package's own sources failed to compile` (exit 2) | A compile error in the libraries or app. |
| `RESULT: tests NOT RUN. The test targets failed to compile` (exit 2) | A compile error in the tests. The app never ran. |
| `RESULT: tests FAILED … Failing tests:` (exit 1) | Tests ran; the listed ones failed. |
| `RESULT: tests DID NOT COMPLETE` (exit 1) | The test process stopped before its summary, for example a crash inside a test. |
| `PACKAGING FAILED at stage: …` (exit 2) | App compilation, bundle assembly, signing or verification. The app was not launched. |
| `LAUNCH FAILED` (exit 4) | Packaging succeeded; the app did not start or did not report. Crash reports are listed. |
| `LAUNCH CHECK FAILED` (exit 5) | The app started, but what it reported does not match the bundle. |
| `LAUNCHED` / `LAUNCH VERIFIED` | The new bundle is running. |

Logs: `distil/dist/logs/` and `relay/build/logs/` (`test.log`, `launch-report.json`).

## The errors seen so far

- **`no such module 'XCTest'`.** A **test compilation** failure, not an app crash. XCTest ships with
  Xcode; the selected developer directory was the Command Line Tools
  (`/Library/Developer/CommandLineTools`). Earlier, `distil/scripts/build-macos.sh` ran `swift test`
  before packaging, so packaging failed with it too. Packaging no longer compiles tests. To run the
  tests, choose one of these. The scripts never change the selection themselves.
  ```bash
  sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer        # all tools, permanently
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer scripts/test.sh     # this command only
  ```
  `check-prerequisites.sh test` prints these with the path of the Xcode it finds.
  If Xcode was never opened: `sudo xcodebuild -license accept` and `sudo xcodebuild -runFirstLaunch`.
- **`fatalError` after the XCTest error.** Neither package's sources nor tests call `fatalError`, and
  Distil was never launched in that run: it stopped at test compilation. The message most likely came
  from SwiftPM's test step after the failed test build. Without the full log this is not certain. If
  it appears again, run `scripts/test.sh` and send `dist/logs/test.log`.
- **`no executable product named 'TokenLab'`.** Distil's executable product has been `Distil` since
  0.5. The package itself is still named `TokenLab`, so any tool that derives the product from the
  package name, or was written for 0.4, asks for a product that no longer exists. Use
  `--product Distil`; the scripts read the names from the current manifests.
- **HCG Executable Maker reports "Unrecognized".** See [`MAKER-HANDOFF.md`](MAKER-HANDOFF.md).

## What packaging puts in the bundle

- `Contents/MacOS/<product>`: the release executable, for the host architecture.
- `Contents/Info.plist`: name, identifier, version and build number, `LSMinimumSystemVersion` 14.0,
  category, `NSHighResolutionCapable`, and the git commit and build time. The app shows the commit in
  Settings › About this build, and in the sidebar for Relay. Relay also gets
  `NSMicrophoneUsageDescription`; macOS terminates an app that records without it.
- `Contents/PkgInfo` and `Contents/Resources/`. Neither package declares SwiftPM resources today. Its
  background, grid and colours are drawn in code. If a target gains resources, its `.bundle` is
  copied into `Contents/Resources` automatically.
- An ad hoc signature (`codesign --sign -`), verified with `codesign --verify --strict`. It is not a
  Developer ID signature and is not notarized. A copy downloaded from CI needs right-click → Open the
  first time.

Only the script's own output (`dist/Distil.app`, `build/Relay.app`) is replaced. Older copies
(`dist/Token Lab.app`, copies in Applications or Downloads), saved projects, preferences and
Keychain items are never touched. Bundle identifiers are unchanged, so settings carry over.

## CI

`.github/workflows/distil.yml` and `relay.yml`, macOS job (macos-15). Separate steps, each with its
own outcome in the run summary:

1. Prerequisites.
2. Tests.
3. Package. Runs even if tests failed, because packaging does not depend on them.
4. Launch check, using `--self-check`. The app's own report is printed.
5. Zip. `ditto` with a re-extract and signature check.
6. Upload artifacts:
   - `distil-app-macos` / `relay-app-macos`: `<App>-<commit>-macos-arm64.zip`, `SHA256SUMS.txt` and
     `launch-report.json`;
   - `distil-screenshots` / `relay-screenshots`: window captures.

Artifacts are kept 14 days. Nothing is published as a release.
