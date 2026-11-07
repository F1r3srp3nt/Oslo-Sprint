# Distil — native macOS prototype 0.4

Distil is the working product name of an unbranded SwiftUI desktop app. It helps you send a model less unnecessary context while keeping what a task needs, and then check whether the answer is still useful. Internal identifiers are unchanged: the package `TokenLab`, the modules `TokenLabCore`/`TokenLabApp`, the executable `TokenLab` and the bundle id `dev.tokenlab.prototype`. All source is newly written for this project; no company code, logos, assets, accounts or third-party packages are included.

A smaller prompt is not automatically a better prompt. Every number names the counter that produced it. Estimated reductions are never presented as cost savings, and keyword matches are never presented as understanding or as evidence of correctness.

## Build and run on your Mac

Requirements: macOS 14 or later and Xcode 15 or later (Swift 5.9+). No dependencies, API keys or network access are needed.

**Xcode**
1. `open Package.swift` (or File → Open… in Xcode).
2. Choose the **TokenLab** scheme and **My Mac** as the destination.
3. Product → Test (⌘U) runs the core tests. Product → Run (⌘R) starts Distil.

**Terminal** (inside this folder)

```sh
swift test
swift run TokenLab
```

With `swift run`, the menu bar shows the process name “TokenLab”; the window title says Distil.

**Local app bundle**: `bash scripts/build-macos.sh`, then `open dist/Distil.app`. The script runs the tests, builds, bundles and ad-hoc signs the app. It does not notarize, publish or install anything.

**Optional model tokenizer files**: download `o200k_base.tiktoken` or `cl100k_base.tiktoken` yourself from the addresses shown in Settings, then import the file there. A file is accepted only if its SHA-256 matches the published value. To run the reference tokenizer tests as well:

```sh
TOKENLAB_ENCODINGS_DIR=/folder/with/tiktoken/files swift test
```

## Demonstration sequence (about 5 minutes)

All three demonstrations are synthetic and labelled as such. They show behaviour, including failures. They are not benchmark evidence.

1. Choose File → Load Demonstration → **Coding task with duplicates and noise**. Distil opens the Comparison view and runs all four configurations.
   - **Manual-priority budget** keeps the unrelated high-priority “Release checklist” and drops the bug discussion.
   - **Task-relevance budget** keeps the discussion and the source, but drops “Parser requirements”, which states three of the four expected facts.
   - The lunch thread scores on “date” and “test”: a keyword trap.
   - Click any block row to read each configuration's reason.
2. Choose **Save as Experiments**. Four linked snapshots appear in Experiments, each marked **Not evaluated**, with the task's expected facts and checks copied in.
3. In one experiment, open Evaluation, paste a full-context answer, and use **Copy Full-Context Answer to Linked Experiments**. This only fills experiments that are still empty.
4. Load **Constraint that must be marked required**. The approval rule is kept in every column. In the Workspace, untick Required on “Approval rule” and set the budget to 110: the rule is dropped, and an unrelated carrier notice is kept instead.
5. Load **Paraphrased task (keyword-ranking weakness)**. Task relevance keeps the newsletter, which repeats the task's words, and drops both blocks that actually explain the problem. Manual priority keeps those two blocks.
6. Open Prompt Workspace → strategy **Relevance** → “How task relevance works and where it fails” to see the method, the task terms and the method's limitations.

## What changed in 0.4

- **Explicit task field.** The draft now has three separate parts:
  - **Current task or question**: protected and verbatim, placed last in the prompt.
  - **Protected instructions and constraints**: protected and verbatim, placed first.
  - **Context blocks**: optional unless marked required, kept in their original order.

  The assembled prompt is the instructions, then the retained blocks in original order, then the task. Parts are joined by a blank line and nothing is rewritten.
- **Schema 3 with migration.**
  - Schema 2 files get an empty task. Their previous instructions are kept exactly as they were, with no attempt to split out a request.
  - Experiments keep their snapshots, answers, checks, notes and verdicts.
  - Migrated files open as untitled, so the original file is never overwritten.
  - Schema 1 files still migrate. Unknown and newer versions are refused.
- **Task-relevance strategy**, alongside Full context, Exact deduplication and Manual-priority budget.
  - **Ranking** (`RelevanceRanker` protocol, `KeywordOverlapRanker`): a deterministic local keyword-overlap score with IDF weights. Every block shows the task terms that contributed to its score and their weights.
  - **Selection**: required blocks are always kept. Optional blocks are considered by score, then manual priority, then prompt order, and added while the **whole assembled prompt** fits the budget.
  - **Zero matches**: blocks with no matching terms aren't removed for that reason. They're considered after every matching block.
  - **Ties**: equal scores are resolved by priority, then position, and the reason says so.
  - **No shortening**: blocks are never shortened, and the method's limitations are shown next to every ranking.
  - **Separation**: ranking, counting and selection are separate, injected components, so a stronger ranker can replace this one. The ranker's id and version are recorded in each report.
- **Comparison view.** The four configurations run on the same input, budget and counter. It shows input tokens, the counter's identity, the estimated change from full context, retained/excluded counts, budget overflow, and a block-by-configuration decision matrix with reasons. Every column says “Not evaluated” until real answers are reviewed. **Save as Experiments** stores four linked, reproducible snapshots.
- **Review criteria per task.** Expected facts and correctness checks are copied as unchecked items into each new experiment. They have no effect on selection.
- **Slow work kept off the UI thread.**
  - Previews and comparisons run on background tasks and are debounced (400 ms).
  - Superseded runs are cancelled cooperatively; the engine checks for cancellation between blocks.
  - Every run carries a ticket from `LatestResultGate`, so an older calculation can never replace a newer result. Editing inputs invalidates in-flight work immediately.
  - Model-tokenizer counts are no longer computed on the main thread: editors show the count from the latest background preview.
- **Distil naming** in the window title, bundle display name and interface. There is no logo.

## Verification status

| Check | Where | Result |
|---|---|---|
| `TokenLabCore` + tests compile | Linux, Swift 5.10.1 (official toolchain image) | Pass, no warnings |
| `swift test` with official encoding files | Linux, Swift 5.10.1 | **84 passed, 0 failed** |
| `swift test` without encoding files | Linux, Swift 5.10.1 | 81 passed, 3 skipped |
| BPE tokenizer vs tiktoken 0.14.0 (0.3; tokenizer unchanged since) | Linux | 0 mismatches on 8,000 comparisons |
| **SwiftUI app compiles** | — | **Not verified. Needs a Mac.** Reviewed by reading the code only. |
| **Launch, windows, menus, dialogs, layout, responsiveness** | — | **Not verified. Needs a Mac.** |
| Core tests on macOS (Foundation and the ICU regex library differ there) | — | Not verified |

## Known limitations

- **Keyword ranking.** It matches exact words only: no synonyms, paraphrases, stemming (“date” ≠ “dates”) or translation. The paraphrase demonstration fails by design, so you can see this.
- **Greedy budget filling.** A smaller, lower-ranked block can fill space that a larger, more relevant block couldn't use. Every reason states this.
- **English stop words only.** Text in other languages is still matched word for word.
- **Main-thread file handling.** Opening and saving projects is still done on the main thread, which may pause for very large (20 MB) files.
- **Manual answers only.** Answers and provider usage are entered by hand; no model is called.
- **Demonstration budgets.** These were chosen before results were known and are deliberately small. They aren't a measurement of anything.

## First-launch acceptance checklist (on your Mac)

1. `swift test` passes; only the 3 reference tests skip if no encoding files are present. Xcode builds and runs with no errors. The window title reads **Distil**.
2. The sidebar has six sections, switched with ⌘1–⌘6. Settings also opens with ⌘,.
3. Follow the demonstration sequence above; each outcome should match what it describes.
4. Workspace: edit the task. The preview hides at once and refreshes after a short pause. Typing quickly in a long block never shows an older result.
5. Set the budget to 1 with the Relevance strategy. The task, the instructions and the required blocks remain verbatim (check the tab characters in code), and the banner reports the overflow.
6. Save, quit, relaunch and reopen the project: the task, review criteria, comparison groups and evaluations all round-trip.
7. Open a 0.3 (schema 2) project. It opens as untitled with an empty task and unchanged instructions and experiments.
8. With unsaved changes, New, Open, Load Demonstration, the close button, ⌘W and ⌘Q each ask Save / Don't Save / Cancel.
9. VoiceOver reads the strategy picker, decision rows and keyword scores. Shrink the window to about 760×520 and drag both split dividers.

## Layout

- **`Sources/TokenLabCore`**: no UI.
  - `Models`: draft (task, instructions, blocks), strategies, settings, review template.
  - `SelectionEngine`, plus `LatestResultGate`.
  - `Relevance`: the ranker protocol and keyword ranker.
  - `Comparison`
  - `TokenCounting`, `BPETokenizer`, `SHA256`
  - `Evaluation`
  - `ProjectDocument`: schema 3 and the 2→3 and 1→3 migrations.
  - `ProjectSession`
  - `DemoDataset`, `SampleProject`
  - `SecretScanner`, `ProviderAdapter`
- **`Sources/TokenLabApp`**: SwiftUI views and the store. Built on macOS only.
- **`Tests/TokenLabCoreTests`**: 84 tests covering the engine, ranking, ties, zero matches, protected content, assembly order, comparison, migrations, stale and cancelled results, demonstrations, the tokenizer, project files, sessions, evaluation and secret scanning.
