# Distil: macOS

No build uploaded yet.

This folder is reserved for a packaged Distil build for macOS. Its existence does not mean that such a build exists or that Distil supports macOS.

Upload a `.app` bundle as a ZIP archive, so its bundle structure, executable permissions and signature survive. `ditto` does this; Finder's *Compress* does too:

```bash
ditto -c -k --keepParent "Distil.app" "<name>-<version>-<arch>.zip"
```

When you add a build, replace "No build uploaded yet." with one row per file:

| File | Version | Architecture | Build date | Source commit | Verification status |
|---|---|---|---|---|---|
| `<file name>` | `<x.y.z (build)>` | `<arm64 / x86_64 / universal / …>` | `<YYYY-MM-DD>` | `<commit SHA, or "unknown">` | `<what was checked, e.g. "launched on macOS 15.3 (arm64)", or "not verified">` |

Only list what was actually checked; write "not verified" otherwise.

Back to [Distil submissions](../README.md).
