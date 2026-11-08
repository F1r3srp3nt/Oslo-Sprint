# Presentation Studio: packaged submissions

Packaged builds of Presentation Studio, one folder per operating system. These folders hold uploaded packages only, never source code.

**A folder existing does not mean a build exists or that the platform is supported.** Each folder's README says whether a build has been uploaded and what was verified.

| Operating system | Folder |
|---|---|
| macOS | [`MacOS/`](MacOS/README.md) |
| Windows | [`Windows/`](Windows/README.md) |
| Linux | [`Linux/`](Linux/README.md) |
| Android | [`Android/`](Android/README.md) |
| iOS | [`iOS/`](iOS/README.md) |

## Source

The source in [`presentation-studio/`](../../presentation-studio/README.md) is a React + TypeScript app with a Node/Express backend, packaged as an **Electron desktop app** for macOS (Apple Silicon). [`MacOS/`](MacOS/README.md) explains how to build and install it and what has been verified. No macOS package has been uploaded here yet, because the ZIP and DMG are larger than GitHub's 100 MB file limit; CI builds, verifies and launch-tests them on macOS and keeps them as a downloadable artifact. No Windows, Linux, Android or iOS package exists.

Back to [all submissions](../README.md).
