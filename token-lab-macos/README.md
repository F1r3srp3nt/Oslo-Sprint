# Token Lab — native macOS skeleton 0.2

Unbranded SwiftUI desktop app. Token Lab is a temporary descriptive name. This project contains newly written source and standard system UI; no existing company code, logos, assets or account integrations are included.

## Open on your Mac

Requirements: macOS 14+ and Xcode 15+ (Swift 5.9+). No third-party dependencies, API keys or Node.js are required.

1. Extract the archive.
2. Open `Package.swift` in Xcode.
3. Choose the TokenLab executable scheme and My Mac destination.
4. Build and Run (Command-R).

Or use Terminal inside this folder:

```sh
swift test
swift run TokenLab
```

To produce a local development `.app`:

```sh
bash scripts/build-macos.sh
open "dist/Token Lab.app"
```

The script runs tests, builds, bundles and ad-hoc signs for local use. It does not notarize, publish, upload or install anything. It is not a distribution build.

## Categories

- **Overview**: workspace, library and experiment counts; new-user entry points.
- **Prompt Workspace**: protected request, editable context blocks, required flags, priorities, estimated budget, selection report and export.
- **Context Library**: reusable blocks with text search and Reference / Conversation / Code / Tool output filtering. Copies inserted into the workspace are independent.
- **Experiments**: saved input/output snapshots, estimated reductions, manual quality labels and notes. No model benchmark runs yet.
- **Settings**: system/light/dark appearance, token-counter limits and local data behaviour.

## Local files

File → Save Project (Command-S) explicitly writes a versioned JSON file including the workspace, library and experiments. File → Open Project validates before replacing current state and asks before discarding unsaved edits. Reports can be exported separately. Appearance is remembered locally; projects are not autosaved or uploaded. Quit prompts when there are unsaved changes. Plain JSON exports contain the prompt text.

## Engineering layout

`Sources/TokenLabCore` holds Codable models, validation and the deterministic selection engine. `Sources/TokenLabApp` holds SwiftUI views, navigation and native file dialogs. `Tests/TokenLabCoreTests` contains ten tests for protected content, budgets, exact duplicates, project round-trips and invalid reports. The engine is independent of SwiftUI so a real tokenizer and model evaluation can be added later.

Required text stays verbatim even if over budget. Optional blocks are selected by user priority, with original retained order. Exact deduplication compares UTF-8 bytes. No text rewriting, model calls or account integration is performed.

## Verification status

This source was created in a Linux environment with no Swift compiler or macOS SDK. **The native app has not been compiled, its Swift tests have not been executed, and its windows have not been visually checked.** Shell syntax, archive contents and source-reference checks were performed. First Mac build and the acceptance checks below remain required.

## First Mac acceptance pass

1. `swift test` passes all ten tests and Xcode builds the app.
2. All five sidebar categories open; appearance follows System or the explicit setting.
3. Load the example; preview shows explicit kept/excluded reasons. Edit input; old results disappear.
4. Set budget to 1: protected instructions/required blocks remain and overflow is reported.
5. Copy context to the library; search/filter it; use it in the workspace; edit the copy independently.
6. Save an experiment; change its manual quality label and notes. Expand both prompts.
7. Save and reopen the project; content, categories and experiments round-trip.
8. Try malformed JSON/unsupported versions: an error appears and the current project remains intact.
9. Quit with unsaved changes: Cancel preserves the session; Save Project retains it between launches.
10. Check keyboard navigation, text selection, narrow-window layout and exported reports.

## Next

Add a model-specific tokenizer, relevance selection, and a quality/cost evaluation harness. Current counts are UTF-8 bytes divided by four, excluding message overhead. Savings are estimated input reductions only; no claimed money savings or preservation of answer quality.
