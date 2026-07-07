# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Distill is a fully native macOS SwiftUI app that converts documents (PDF, DOCX, PPTX, XLSX, CSV, HTML, TXT, …) into clean Markdown for feeding to AI models. See `distill-project-brief.md` for the full roadmap (Phases 1–5), conversion-engine plan, and hard constraints. The developer is a second-year computer engineering student new to Swift: prefer clear, idiomatic, well-commented code, and briefly explain architectural choices.

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

## Project configuration

- Single target `Distill`, scheme `Distill`, bundle ID `com.rakan.Distill`.
- **App Sandbox is enabled** via build settings (no .entitlements file; Info.plist is generated — `GENERATE_INFOPLIST_FILE = YES`). Sandbox-related capabilities are edited in `project.pbxproj` build settings, e.g. `ENABLE_USER_SELECTED_FILES`.
- Sandbox implications that shape the architecture:
  - Drag-and-drop grants access to the dropped files themselves.
  - Writing converted .md files requires `ENABLE_USER_SELECTED_FILES = readwrite` (project was created readonly) and, for "alongside source" output or remembered custom folders, security-scoped bookmarks / explicit folder selection via NSOpenPanel.

## Code organization

Keep sources in `Distill/` grouped as `Models/`, `Views/`, `Converters/`, `Services/` (folder-backed groups; new .swift files added under `Distill/` are picked up via Xcode's file-system-synchronized groups). Converters should share a common protocol so new formats slot in per the phase plan.

## Conversion engine expectations

- Conversion must run off the main thread (Swift concurrency); UI stays responsive with per-file status (pending/converting/done/failed-with-reason).
- Never overwrite outputs: append `-2`, `-3`, … to duplicate names.
- Settings persist via `@AppStorage`: output-folder mode (alongside source vs custom), auto-copy-to-clipboard.
