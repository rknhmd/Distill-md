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

```sh
# Release build. Use `clean build` before a release: incremental builds
# don't recompile untouched files, so they hide warnings.
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme Distill -configuration Release clean build
```

### Versioning

`Config/Version.xcconfig` is the only place version numbers live. It's the
`baseConfigurationReference` of the project-level configurations, so the app
inherits `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION`, and the `distill` CLI
reads them back from the Info.plist embedded in its binary
(`CREATE_INFOPLIST_SECTION_IN_BINARY`) — so `distill --version` and the MCP
`serverInfo` can't drift from the app. Bump releases there and nowhere else.

### Releasing

1. Bump `Config/Version.xcconfig`; close the CHANGELOG section.
2. Clean Release build (above); confirm zero warnings and a green harness.
3. `ditto -c -k --keepParent <DerivedData>/Build/Products/Release/Distill.app dist/Distill.md-<version>.zip`
4. Tag `v<version>`, push, then `gh release create` with the zip attached.

The repo is `rknhmd/Distill-md`, but git and `gh` on this machine default to
the `rakanhmd` account, which can't push there. Push with the owner's
credential — resetting the helper list first, since `-c credential.helper=…`
otherwise *appends* to the keychain helper and loses to it:

```sh
git -c credential.helper= -c credential.helper='!f(){ echo username=rknhmd; echo "password=$(gh auth token -u rknhmd)"; };f' push
GH_TOKEN=$(gh auth token -u rknhmd) gh release create …
```

### Mac App Store build: parked

A sandbox-clean MAS variant (`Release-MAS` configuration, `Distill-MAS` scheme,
`com.rakan.Distill.mas`, CLI/MCP helper excluded, packaging guard phase) was
built and verified in commit `9f590e2`, then removed when the App Store was
shelved. The GitHub build — app, Quick Action, watch folder, CLI, and MCP — is
the only product. To revive MAS, start from that commit. The constraint it
encodes: a helper inside a sandboxed bundle inherits the sandbox, so the CLI and
MCP server can't ship in a MAS build in their current form.

## Project configuration

- Two targets: `Distill` (app) and `DistillQuickAction` (Finder Quick Action .appex under `QuickAction/`, embedded in the app; it hands selected files to the app via `NSWorkspace.open(_:withApplicationAt:)`, which transfers sandbox grants). Building the `Distill` scheme builds both.
- Bundle IDs `com.rakan.Distill` / `com.rakan.Distill.QuickAction`.
- The app has a partial `Distill/Info.plist` (document types) merged into the generated Info.plist via `INFOPLIST_FILE` + `GENERATE_INFOPLIST_FILE = YES`; the extension does the same for its `NSExtension` dict.
- **App Sandbox is enabled.** Entitlements live in `Config/Distill.entitlements` and `Config/QuickAction.entitlements` (wired via `CODE_SIGN_ENTITLEMENTS`, mirroring the `ENABLE_APP_SANDBOX` / `ENABLE_USER_SELECTED_FILES` build settings). Info.plist is generated (`GENERATE_INFOPLIST_FILE = YES`). The bundled `distill` helper is deliberately unsandboxed: it's launched directly by users and MCP clients with arbitrary paths.
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
