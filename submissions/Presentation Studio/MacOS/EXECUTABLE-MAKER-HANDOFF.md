# HCG Executable Maker and Presentation Studio (Electron)

A handoff for the separate [HCG-Executable-Maker](https://github.com/F1r3srp3nt/HCG-Executable-Maker) repository. Nothing here changes Maker.

**Finding:** Maker at commit `8cd38ae` ("Merge feature/swift-macos", 2026-11-08) **cannot import, build or package Presentation Studio.** It has no Electron or Node adapter. It only *recognises* Electron projects and reports them as unsupported. Presentation Studio is therefore built with its own scripts (see [README.md](README.md)).

The repository was read, not run (Maker is a .NET/Avalonia app and this environment had no Mac). Paths and line numbers below are from that commit.

## What Maker does today

| Stage | Maker today | Evidence |
|---|---|---|
| Detect | Matches any `package.json` containing `"electron"` with score **42** and returns `SupportLevel.Unsupported`: "HCG Executable Maker M0.1 does not build Electron projects; support is planned for a later milestone." Node (`package.json` only) scores 30, also unsupported. | `src/HCG.ExecutableMaker.ProjectInspection/Ecosystems/EcosystemSignatureInspector.cs:7-8, 100-101, 129-131`; tests `tests/HCG.ExecutableMaker.Tests/InspectionTests.cs:197-198` |
| Which project wins in Oslo-Sprint | `ProjectInspectionService` runs only the highest-scoring inspector for the whole import. Oslo-Sprint has `distil/Package.swift` and `relay/Package.swift`, so the **Swift inspector (102) wins**. Presentation Studio appears only as an "Also found files for: Electron … not part of this build" note. | `ProjectInspection/ProjectInspectionService.cs:13-17, 38-41`; `Swift/SwiftProjectInspector.cs:19-29` |
| Build | `BuildService.RunAsync` branches only between .NET and Swift (`isSwift`). There is no Node/npm toolchain ID or detector. | `BuildEngine/BuildService.cs:121, 176-183, 240-258`; `Domain/Toolchains.cs:38-74`; `Infrastructure/Toolchains/ToolchainDetector.cs:26-40` |
| Package (macOS) | `SwiftAppBundlePackager` builds a bundle from one SwiftPM executable, and `MacAppBundlePackager` from a .NET publish folder. Neither handles an Electron bundle (helper apps, frameworks, symlinks). `UnixZip` and `FileOps.CopyDirectory` drop symlinks, which Electron's frameworks need. Only the `ditto` code paths keep them. | `Packaging/Packagers/SwiftAppPackagers.cs:15-111, 230-304`; `MacAppBundlePackager.cs:11-92`; `UnixZip.cs:15-38`; `FileOps.cs:7-20` |
| Project config file | None. Maker reads no configuration from the project repository; everything is chosen in the wizard. | the only `.hcg-build.json` is an output marker (`BuildService.cs:49`) |

So `package.json` recognition is **not** packaging support. Nothing in this repository pretends otherwise: no fake `.csproj` or `Package.swift`, and no web output renamed to `.app`.

## Adapter changes Maker would need

The extension points follow Maker's Swift adapter. Electron works best as a *prebuilt-bundle* adapter, because electron-builder already produces a signed, verified `.app`, and re-implementing Electron bundling in C# would duplicate it.

1. **Inspection: `ElectronProjectInspector : IProjectInspector`**
   - Match a `package.json` that has `electron` and `electron-builder` in its dependencies, plus an electron-builder config (`electron-builder.yml`/`.json`, or a `build` key).
   - For Presentation Studio: `presentation-studio/package.json` and `presentation-studio/electron-builder.yml`.
   - Read statically, without running code: `productName`, `version`, `appId`, the `mac.target` list, `mac.minimumSystemVersion`, the `extendInfo` privacy keys (`NSMicrophoneUsageDescription`), `mac.icon`, and the npm scripts `desktop:dist:mac` and `test:desktop`.
   - Selection: the Swift inspector currently wins for the whole repository. Either let one import offer several projects of different ecosystems (as Swift already does for several packages), or score the Electron inspector above 102 when the user picks the `presentation-studio/` folder.
   - Register in `App/Composition.cs:44-49`.
2. **Toolchains:** add `ToolchainIds.Node` and `ToolchainIds.Npm` (`Domain/Toolchains.cs`), and a detector partial like `SwiftToolchains.cs`, probing `node --version` (needs at least 22.12) and `npm --version`. Report `RequiresDifferentHost` off macOS for Mac targets, like Swift does.
3. **Build options:** add an `ElectronBuildOptions` record on `BuildSettings` (like `SwiftBuildOptions`, `Domain/Swift.cs:107-121`) holding the package directory, npm script name, target architecture (arm64) and expected bundle ID.
4. **Build plan (`ElectronBuildPlanner`):**
   - `npm ci` in the package directory, then `npm run desktop:dist:mac`. Running these executes project scripts, which Maker's trust gate already covers (`docs/SECURITY.md:9, 76`).
   - Maker's environment scrubbing drops `NPM_*` variables (`Security/BuildEnvironmentPolicy.cs:20-25`). That is fine: no npm auth is needed for public packages.
   - electron-builder downloads Electron from GitHub releases, so the build host needs network access.
   - Expected outputs:
     - `release/mac-arm64/Presentation Studio.app`
     - `release/Presentation-Studio-<version>-mac-arm64.zip`
     - `release/Presentation-Studio-<version>-arm64.dmg`
   - Add a third branch in `BuildService.RunAsync` (`:121/:176/:183/:240`).
5. **Packaging: `ElectronAppPackager : IPackager`.** Adopt the `.app`, ZIP and DMG that electron-builder produced instead of rebuilding them.
   - Copy with `ditto` so symlinks survive.
   - Do not repackage with `UnixZip`, which drops symlinks.
   - Register in `Composition.cs:55-61` and add a catalog branch in `PackagingCatalog.Evaluate`.
6. **Verification: `ElectronBundleVerifier`.** Reuse the Swift verifier's checks (`SwiftAppPackagers.cs:132-223`):
   - Info.plist keys, `codesign --verify --deep --strict`, and arm64 from `lipo`.
   - Unlike Swift, allow `Contents/Frameworks/*` and the four `… Helper*.app` bundles.
   - Check `CFBundleExecutable` = `Presentation Studio` and `NSMicrophoneUsageDescription`.
   - Optionally launch with `open -n` and run the project's `npm run test:desktop` against the bundle.
7. **Wizard:** add a `BuildWizardViewModel.Electron.cs` partial (like `BuildWizardViewModel.Swift.cs`). Prefill the name, version and bundle ID from the inspected config, and show the trust notice that npm scripts will run.
8. **Tests:** add an Electron fixture written inline like `WriteOsloSprint` (`tests/.../SwiftTests.cs:70-85`), with tests mirroring the Swift ones:
   - "finds the Electron project next to Swift packages"
   - "off-Mac needs a different host"
   - "plan runs npm ci and the dist script"
   - "verifier accepts helper apps and frameworks"
9. **Docs and UI text:** update `README.md:27`, `docs/STATUS.md:124` and the Unsupported summary when this lands.

## Acceptance check for that Maker work

On a Mac with Node 22.12+:
1. Import Oslo-Sprint `main` into Maker built with the adapter.
2. Choose `presentation-studio/` and confirm the inspection shows Electron, Presentation Studio 0.1.0 and `com.oslosprint.presentationstudio`.
3. Build for macOS arm64.
4. Expect an ad-hoc-signed `Presentation Studio.app` that passes `codesign --verify --deep --strict`, plus the ZIP and DMG.
5. The app launches with `open` and passes `npm run test:desktop` with `STUDIO_APP` pointing at the bundle's executable.
