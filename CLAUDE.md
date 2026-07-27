# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Distill.md (product name; `PRODUCT_NAME` and all build settings stay period-free as `Distill`) is a fully native macOS SwiftUI app that converts documents (PDF, DOCX, PPTX, XLSX, CSV, HTML, TXT, …) into clean Markdown for feeding to AI models. See `distill-project-brief.md` for the full roadmap (Phases 1–5), conversion-engine plan, and hard constraints. The developer is a second-year computer engineering student new to Swift: prefer clear, idiomatic, well-commented code, and briefly explain architectural choices.

## Hard constraints (from the brief)

- **No non-native code.** No Python, no bundled interpreters, no Electron. Apple frameworks first; the only pre-approved Swift packages are **ZIPFoundation** and **CoreXLSX**. Ask before adding anything else. (Calling the OS-provided `textutil` CLI for legacy .doc/.rtf is acceptable.)
- The sibling project MarkdownDrop (Python/Tkinter, in a separate folder) must never be touched.
- macOS only, current SDK, light + dark mode support.
- Complete one phase before starting the next; at the end of each phase, summarize what was built and what to manually test.

## Build commands

`xcode-select` points at CommandLineTools and switching it needs sudo, so **always prefix xcodebuild with `DEVELOPER_DIR`**:

```sh
# Build (run after every meaningful change; fix errors before moving on)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme Distill -configuration Debug build

# Built app lands in DerivedData:
# ~/Library/Developer/Xcode/DerivedData/Distill-*/Build/Products/Debug/Distill.app
```

There are no test targets yet. The developer also builds/runs in Xcode (⌘R) to verify UI.

### Two builds from one codebase

| | Direct (daily driver) | Mac App Store |
| --- | --- | --- |
| Scheme / configuration | `Distill` / `Release` | `Distill-MAS` / `Release-MAS` |
| Bundle ID | `com.rakan.Distill` | `com.rakan.Distill.mas` |
| `distill` CLI + MCP helper | embedded in `Contents/Helpers` | **excluded** |
| Entitlements | `Config/Distill.entitlements` | `Config/Distill-MAS.entitlements` |
| Hardened runtime | off | on |
| `#if MAS` | inactive | active (`SWIFT_ACTIVE_COMPILATION_CONDITIONS`) |

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme Distill     -configuration Release     build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme Distill-MAS -configuration Release-MAS build
```

Things that will bite if you don't know them:

- **`Config/Version.xcconfig` is the only place version numbers live.** It's the
  `baseConfigurationReference` of the project-level configurations; no target
  sets `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION`. Bump releases there so the
  two builds can't drift (the App Store requires `CFBundleVersion` to increase).
- **The "Verify helper packaging" script phase fails the build in both
  directions** — MAS aborts if `Contents/Helpers` survives, Direct aborts if the
  helper is missing. A stray helper in an App Store submission is a rejection,
  so don't "fix" a failure by deleting the check.
- **`ENABLE_USER_SCRIPT_SANDBOXING = NO` on the app target is deliberate.** That
  guard phase deletes a file the Embed CLI phase just produced; declaring it as
  a script output instead makes two commands claim the same path
  ("Multiple commands produce…"). The phase only ever touches its own build
  product.
- **Both schemes are shared and committed.** Adding the first shared scheme
  stops Xcode autocreating the rest, which is why `Distill.xcscheme` exists too.
- DistillCore must not diverge between builds: no `#if MAS` in converter logic.
  The flag governs packaging and UI only.

## Project configuration

- Two targets: `Distill` (app) and `DistillQuickAction` (Finder Quick Action .appex under `QuickAction/`, embedded in the app; it hands selected files to the app via `NSWorkspace.open(_:withApplicationAt:)`, which transfers sandbox grants). Building the `Distill` scheme builds both.
- Bundle IDs `com.rakan.Distill` / `com.rakan.Distill.QuickAction`.
- The app has a partial `Distill/Info.plist` (document types) merged into the generated Info.plist via `INFOPLIST_FILE` + `GENERATE_INFOPLIST_FILE = YES`; the extension does the same for its `NSExtension` dict.
- **App Sandbox is enabled** via build settings (no .entitlements file; Info.plist is generated — `GENERATE_INFOPLIST_FILE = YES`). Sandbox-related capabilities are edited in `project.pbxproj` build settings, e.g. `ENABLE_USER_SELECTED_FILES`.
- Sandbox implications that shape the architecture:
  - Drag-and-drop grants access to the dropped files themselves.
  - Writing converted .md files requires `ENABLE_USER_SELECTED_FILES = readwrite` (project was created readonly) and, for "alongside source" output or remembered custom folders, security-scoped bookmarks / explicit folder selection via NSOpenPanel.

## Code organization

- **`DistillCore/`** — local Swift package holding the conversion engine: all converters, `FileType`, `ConversionEngine`, `FrontMatter`, `TokenEstimator`. It owns the ZIPFoundation + CoreXLSX dependencies and builds standalone (`cd DistillCore && swift build`, Swift 6 language mode). Public surface is deliberately small: `ConversionEngine.convert(fileAt:type:)`, `FileType`, `ConversionResult`, `ConversionError`, `FrontMatter`, `TokenEstimator` — converters themselves are internal. The app, the `distill` CLI/MCP helper, and the regression harness all consume this package.
- **`Distill/`** — the app: `Models/` (AppModel, QueuedFile), `Views/`, `Services/` (sandbox folder access, output writing, watch folder, settings). Folder-backed synchronized groups: new .swift files on disk are picked up automatically.
- **`QuickAction/`** — the Finder extension.
- **`convtest/`** — the regression harness (SPM package, committed): `swift run convtest samples` converts every fixture through DistillCore's public API and exits non-zero on failure. `tools/regen-fixtures.sh` rebuilds all fixtures deterministically. Extend it with fixtures for every converter change. (It lived in the session scratchpad before v2.0.1 and was lost to a session reset — keep it in the repo.) After adding files to DistillCore, `rm -rf convtest/.build` if the harness build can't find new symbols; SPM caches by-path package file lists.

## Conversion engine expectations

- Conversion must run off the main thread (Swift concurrency); UI stays responsive with per-file status (pending/converting/done/failed-with-reason).
- Never overwrite outputs: append `-2`, `-3`, … to duplicate names.
- Settings persist via `@AppStorage`: output-folder mode (alongside source vs custom), auto-copy-to-clipboard.
