# Token Lab — native macOS prototype 0.3

Unbranded SwiftUI desktop app for reducing unnecessary model input while keeping what a task needs, and for checking whether the answer is still useful. “Token Lab” is a temporary descriptive name. All source is newly written for this project; no company code, logos, assets, accounts or third-party packages are included.

A smaller prompt is not automatically a better prompt. Every number in the app names the counter that produced it. Estimated reductions are never presented as cost savings or as preserved answer quality.

## Open, build and run on your Mac

Requirements: macOS 14 or later and Xcode 15 or later (Swift 5.9+). No dependencies, API keys or network access are needed.

**Xcode**

1. Open `Package.swift` in Xcode (File → Open…, or `open Package.swift`).
2. Choose the **TokenLab** scheme and **My Mac** as the destination.
3. Product → Test (⌘U) runs the core tests. Product → Run (⌘R) starts the app.

**Terminal** (inside this folder)

```sh
swift test
swift run TokenLab
```

**Local `.app` bundle** (runs the tests, then builds and ad-hoc signs; it does not notarize, publish or install anything):

```sh
bash scripts/build-macos.sh
open "dist/Token Lab.app"
```

### Optional: model-specific token counting

The app counts with a clearly labelled approximation by default. To count `cl100k_base` or `o200k_base` text tokens:

1. Download the official file yourself:
   - `https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken` (3.6 MB)
   - `https://openaipublic.blob.core.windows.net/encodings/cl100k_base.tiktoken` (1.7 MB)
2. In the app, go to Settings → Model tokenizer files → Import File….
3. The file is accepted only if its SHA-256 matches the value published in tiktoken (shown in Settings). It is copied to `~/Library/Application Support/TokenLab/Encodings/`.
4. Switch the project counter in Settings → Token counting for this project.

To run the reference-tokenizer tests too, either import the files in the app first, or run:

```sh
TOKENLAB_ENCODINGS_DIR=/path/to/folder/with/tiktoken/files swift test
```

## What works

**Five sections** in a sidebar (⌘1–⌘5): Overview, Prompt Workspace, Context Library, Experiments, Settings (also ⌘,).

- **Overview**: project name, file location, saved/unsaved state, counts (required blocks, library items in use, evaluated experiments), current settings, current-preview summary, recent experiments and entry points.
- **Prompt Workspace**: a resizable split view.
  - The left column holds the protected instructions and current request, the strategy picker, budget, deduplication toggle and counter, and the context blocks. Each block has a title, category, required flag, priority, reorder, duplicate, copy-to-library and delete actions.
  - The right column is the preview. It shows the full-context and selected token counts, the budget status, one decision per block with its reason, the selected prompt, the full-context prompt, Copy, Save as Experiment and Export.
  - Previews update automatically after edits; you can turn this off. Results are hidden the moment any input, setting or counter changes.
- **Context Library**: toolbar search, category filter, editor, duplicate, delete and insert into the workspace. Inserted copies are independent and remember which library item they came from.
- **Experiments**: complete snapshots of inputs, settings, counter descriptor, engine version and both prompts, with three tabs:
  - **Snapshot**: recorded settings, decisions, and the full and selected prompts side by side.
  - **Evaluation**: answers for both variants, entered manually, plus provider-reported usage, kept separate from estimates. It has expected facts and correctness checks judged per variant, a reviewer, notes and a verdict. The verdict stays “Not evaluated” until a selected-context answer exists.
  - **Reproducibility**: re-runs the snapshot and lists any differences.

  You can also restore an experiment's inputs to the workspace and export an experiment.
- **Settings**: appearance, the project counter (approximate with configurable bytes per token, or an imported model tokenizer), tokenizer file import, removal and verification, auto-preview, local-data summary with reset and reveal actions, and build information.

**Engine** (`TokenLabCore`, no UI dependencies):

- **Strategies**:
  - **A. Baseline** keeps everything.
  - **B. Exact deduplication** removes only optional blocks that are byte-identical to the instructions, a required block, or a higher-priority or earlier copy.
  - **C. Budget selection** adds optional blocks by priority, with ties broken by prompt order, while the total stays within the budget. Exact deduplication runs first only if you enable it.
- **Protected content**: instructions and required blocks are always kept verbatim and never truncated. If they exceed the budget, the report says so and shows by how much. Strategies A and B report the budget but do not apply it.
- **Order and formatting**: retained blocks keep their original order. Text is never rewritten, and whitespace, tabs and CRLF are preserved.
- **Explanations**: every block gets a reason. Duplicates name the block they duplicate.
- **Determinism**: the same inputs, settings and counter always produce the same report.

**Token counting** through a replaceable `TokenCounter` protocol:

- `ApproximateCounter`: UTF-8 bytes ÷ N, labelled as an approximation.
- `BPETokenizer`: a tiktoken-compatible byte-pair encoder written for this project, equivalent to `encode_ordinary`. It's verified against the official tiktoken package; see Verification.
- Every report records the counter's id, encoding, version (including the vocabulary hash) and scope. Counts are never called “exact”: they exclude chat message formatting and provider overhead.

**Project files** (versioned JSON, schema 2):

- Save writes to the current file and Save As asks for a location. The app warns before saving or exporting text that looks like a credential.
- Open validates the whole file before anything is replaced. A bad file leaves the current project untouched, with an error naming the problem.
- Schema 1 files from the 0.2 skeleton are migrated and opened as untitled, so the original file isn't overwritten. Newer or unknown schemas are refused.
- Unsaved changes prompt Save / Don't Save / Cancel before New, Open, Load Example, closing the window and Quit. A cancelled or failed save never discards work. The window's close button shows the “edited” dot.
- Experiment snapshots load even after the engine changes, because reproducibility is checked on request rather than at load time.

**Provider adapter interface**: `ModelProviderAdapter`, `ProviderRequest`/`ProviderResponse` and `CredentialSource` are defined. No adapter is implemented, no network calls are made and no keys are requested.

## Verification status

| Check | Where | Result |
|---|---|---|
| `TokenLabCore` + tests compile | Linux, Swift 5.10.1 (official toolchain image) | Pass, no warnings |
| `swift test` (60 tests) with official encoding files | Linux, Swift 5.10.1 | 60 passed, 0 failed |
| `swift test` without encoding files | Linux, Swift 5.10.1 | 57 passed, 3 skipped (reference tests) |
| BPE tokenizer vs official tiktoken 0.14.0, 4,000 random strings × 2 encodings | Linux | 0 mismatches |
| Encoding files' SHA-256 vs values in tiktoken source | Linux | Match |
| **SwiftUI app compiles** | — | **Not verified (needs macOS)** |
| **App launches, windows, dialogs, menus, layout** | — | **Not verified (needs macOS)** |
| Core tests on macOS (Foundation/ICU there differ from Linux) | — | Not verified |

## Defaults chosen (all reversible)

- **Tokenizer files are imported, not bundled.** The app makes no network requests and the repository contains no third-party data files. The SHA-256 check ensures only official files are used.
- **No deduplication inside budget selection by default.** This keeps the strategies separate. The sample project enables it to demonstrate both behaviours.
- **Approximate counter is 4 bytes per token by default.** It's configurable from 1 to 8.
- **Greedy budget selection.** A smaller lower-priority block can be kept after a larger higher-priority block didn't fit, and the reason says so.
- **Empty blocks are skipped under every strategy**, including empty required blocks, because they add no text.
- **Copying a block to the library clears its required flag.**
- **Model names appear only in Settings**, as factual tokenizer mappings from tiktoken 0.14.0. Remove them if the competition rules prefer no vendor names at all.

## First-launch acceptance checklist (on your Mac)

1. `swift test` passes, or skips only the three reference tests if no encoding files are present. Xcode builds and runs the TokenLab scheme with no errors.
2. The window opens with five sidebar sections, and ⌘1–⌘5 switch between them. Theme follows System, Light and Dark in Settings.
3. Overview → Load Example Project. The workspace preview shows:
   - Safety rules and Shift helper as **Required**.
   - Current status as **Kept**.
   - Status (pasted again) as **Duplicate** of “Current status”.
   - Timer log as **Over budget**.
   - Volunteer chat as **Kept**.

   Reasons are shown on each row.
4. Type in any block, then change the strategy, the budget and the dedupe toggle. The old result disappears straight away and the new one appears; with Auto-update off it shows “Preview out of date”.
5. Set the budget to 1. Protected instructions and both required blocks remain verbatim (check the tab in the code block), and the banner says protected content is over budget and was not truncated.
6. Switch to Baseline, then to Exact deduplication. The budget is shown as “Reported only” and the summary says the budget is not applied.
7. Library: create, search, filter by category, Insert into Workspace. Edit the workspace copy and confirm the library item is unchanged.
8. Save as Experiment (⇧⌘E). Then edit the workspace and confirm the experiment's Snapshot is unchanged. Evaluation: the verdict is disabled until you paste a selected-context answer. Enter provider input tokens for both variants and the provider-reported reduction appears separately from the estimate. Reproducibility → Re-run shows “Reproduced exactly”.
9. Save (⌘S), quit, relaunch, Open (⌘O). Everything round-trips, including the experiment evaluation.
10. Open a non-JSON file, `{}`, and a file with `"schemaVersion": 99`. Each shows an error and the current project is unchanged.
11. With unsaved changes, try New, Open, Load Example, the red close button, ⌘W and ⌘Q. Each asks Save / Don't Save / Cancel. Cancel keeps everything, and cancelling the Save panel also keeps everything.
12. Optional: import `o200k_base.tiktoken` (a wrong file should be rejected), switch the counter, and confirm metrics say “o200k_base text tokens” and the experiment records the encoding and version.
13. Accessibility and layout: navigate with Tab and VoiceOver. Shrink the window to about 760×520 and drag both split dividers.

## Layout

- `Sources/TokenLabCore`:
  - `Models`: blocks, draft, strategies, settings, errors.
  - `SelectionEngine`
  - `TokenCounting`, `BPETokenizer`, `SHA256`
  - `Evaluation`: experiments, review checks, provider usage, reproduction.
  - `ProjectDocument`: schema, codec, v1 migration.
  - `ProjectSession`: unsaved-change rules.
  - `SecretScanner`, `ProviderAdapter`, `SampleProject`
- `Sources/TokenLabApp`: SwiftUI views, `AppStore`, `EncodingStore`, native dialogs and the window-close guard. This target is built only on macOS.
- `Tests/TokenLabCoreTests`: engine, tokenizer, project-file, session, evaluation and secret-scanner tests. All examples are synthetic.
