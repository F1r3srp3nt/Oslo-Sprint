# Handoff to HCG Executable Maker: building Distil and Relay

This is for the **separate** HCG Executable Maker project
(`F1r3srp3nt/HCG-Executable-Maker`). Nothing in Maker was changed from Oslo-Sprint, and Oslo-Sprint
contains no Maker manifest.

## What was checked

Maker's `main` at `8cd38ae` ("Merge feature/swift-macos", 2026-11-08 01:31 UTC) was read, without
building or running it. The files read were `README.md`, `docs/SWIFT-MACOS.md`, `CHANGELOG.md`,
`.github/workflows/build.yml` and the sources under `src/…/Swift/` and `ProjectInspectionService.cs`.

- **SwiftPM support exists on `main`, and only since `8cd38ae`.**
  - Every `Package.swift` is found, nested ones included (`distil/`, `relay/`, or inside a ZIP's
    wrapping folder). Build and cache folders are skipped.
  - Executable products come from `swift package dump-package`, run after the trust confirmation.
    Products declared under `#if os(macOS)` are therefore included.
  - GUI products become an ad-hoc-signed `.app`, optionally also a ZIP or DMG. CLI products become a
    folder or ZIP.
  - Maker never launches what it builds; its own CI does that.
- **Maker has no project configuration file.** Packages, products, names, identifiers and privacy
  texts are chosen in the New Build wizard. CI drives the wizard with `tools/ui-driver` command-line
  flags. With no schema to target, no Maker configuration was generated here.
- **No Maker release contains it.** The repository has no tags or releases. A Swift-capable Maker is
  either a build of `main` at or after `8cd38ae`, or an artifact of Maker's *Build & Release*
  workflow on that branch.

## Why Maker said "Unrecognized"

A Maker build from before `8cd38ae` (for example 0.2.0) has no Swift inspector. For a folder holding
only `Package.swift` projects, it returns `SupportLevel.Unrecognized` with this summary:

> No supported project files were found. M0.1 builds .NET projects (.sln, .slnx, .csproj).

That matches the report for both projects. Which Maker copy was used has **not** been verified. Check
it: a Swift-capable build lists `distil/` and `relay/` as Swift packages in the Inspect step.

Other ways to get "Unrecognized", even with a current Maker:
- importing a folder that does not contain the `Package.swift` (for example `distil/Sources`);
- importing a built `.app`.

## What must change in Maker (stale references)

Maker's docs and CI were written against Oslo-Sprint `4543125` (2026-11-07). At that commit
Distil's executable product was still called `TokenLab`. Since `97b5526` (Distil 0.5) it is `Distil`.
If Maker's pin moves to a current commit while it still asks for `TokenLab`, Maker fails with exactly
`error: no executable product named 'TokenLab'`.

| Where in Maker | Now | Should be |
|---|---|---|
| `.github/workflows/build.yml`, swift-macos job | `--product TokenLab`, `--expect-products TokenLab` | `--product Distil`, `--expect-products Distil` |
| same | `--version 0.4.0 --build-number 4` | `--version 0.5.0 --build-number 5` |
| same | `OSLO_COMMIT: 45431255…` | an Oslo-Sprint commit that contains `docs/BUILDING.md` (after it is merged) |
| `docs/SWIFT-MACOS.md`, `README.md`, `CHANGELOG.md` | "product `TokenLab`, shipped as Distil.app"; "The executable keeps the product name, *TokenLab*" | product `Distil`; the executable is `Distil` |

The package is still *named* `TokenLab`. Never derive the product from the package name.

## The two packages, exactly

| | Distil | Relay |
|---|---|---|
| Package root | `distil/` | `relay/` |
| Manifest | `distil/Package.swift`, tools 5.9, package name `TokenLab` | `relay/Package.swift`, tools 5.9, package name `Relay` |
| Minimum macOS | 14.0 (`.macOS(.v14)`) | 14.0 |
| GUI executable product (macOS only, `#if os(macOS)`) | `Distil` → target `TokenLabApp` (`Sources/TokenLabApp`) | `Relay` → target `RelayApp` (`Sources/RelayApp`) |
| CLI executable product | — | `relay-runner` → target `RelayRunner` (all platforms) |
| Libraries | `TokenLabCore` | `RelayCore`, `RelayAdapters` |
| Test targets | `TokenLabCoreTests` (125 tests, 3 skipped without tokenizer files) | `RelayCoreTests`, `RelayAdaptersTests` (93 tests) |
| Dependencies | none | none |
| SwiftPM resources | none | none |
| App icon | none (system default) | none (system default) |
| Display name | Distil | Relay |
| Bundle identifier (keep; user data belongs to it) | `dev.tokenlab.prototype` | `com.oslosprint.relay` |
| Version (build) | 0.5.0 (5) | 0.2.0 (2) |
| Category | `public.app-category.developer-tools` | `public.app-category.productivity` |
| Privacy keys | none | `NSMicrophoneUsageDescription` (required: push-to-talk records audio), text: "Relay records only while you hold the push-to-talk button, and sends that recording to ElevenLabs for transcription." |
| Optional Info.plist keys read by the app | `DistilGitCommit`, `DistilBuildDate` (Settings › About; shows no commit without them) | `RelayGitCommit`, `RelayBuildDate` |
| Oslo-Sprint's own output | `distil/dist/Distil.app` | `relay/build/Relay.app` |

**Build commands.** Each runs in the package root and compiles no tests, so no XCTest is needed. They
are expected to work with the Command Line Tools alone, but that has not been verified; CI uses
Xcode 16:

```bash
swift build -c release --product Distil      # distil/
swift build -c release --product Relay       # relay/
swift build -c release --product relay-runner
swift build -c release --show-bin-path       # where the executables are
```

Tests (`swift test`) need full Xcode, because the Command Line Tools may lack XCTest. If Maker ever
runs tests, check for XCTest first and report "tests not run" separately from a build failure.

## Launch verification Maker's CI can use

Both apps accept `--self-check <file.json>`. About 3 s after launch, the running app writes what it
sees and quits. The fields are:
- `bundleIdentifier`, `bundlePath`, `executable`;
- `version`, `build`, `commit` (from Info.plist);
- `visibleWindows`, `windows`, `resourceFiles`, `appearance`.

Ordinary launches never pass it. Example:

```bash
open -n Distil.app --args -ApplePersistenceIgnoreState YES --self-check "$PWD/report.json"
```

The reference implementation is `distil/scripts/verify-launch.sh` (and the Relay copy).

## Acceptance tests for the Maker change

1. Import Oslo-Sprint (as a folder, and as a GitHub ZIP). Inspect lists `distil/` and `relay/`, and
   neither is pre-selected.
2. `distil/`: the executable products are exactly `Distil`; the library is `TokenLabCore`; the test
   target is `TokenLabCoreTests`.
3. `relay/`: the executable products are `Relay` and `relay-runner`; `Relay` is GUI, and
   `relay-runner` is CLI.
4. Build `Distil` with the Command Line Tools only (no Xcode) → `Distil.app`. CFBundleExecutable is
   `Distil`, and `codesign --verify --strict` passes.
5. Build `Relay` → `Relay.app`. The build is blocked until the microphone text is entered.
6. Launch both with `--self-check`: `visibleWindows` ≥ 1, and the bundle identifier matches.
