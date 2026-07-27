# Distill — Rename + Dual-Build Setup Brief (App Store / Direct)

## Goal

Two things, in this order, before any further feature work:

1. **Rename** the product to **Distill.md** (display name only — see task 1).
2. **Split into two builds** from one codebase:
   - **Direct** (primary, unchanged in behavior): everything the app does
     today — GUI, Finder Quick Action, watch folder, the `distill` CLI in
     `Contents/Helpers`, and the MCP server. Notarized zip on GitHub.
   - **MAS**: a sandbox-clean variant suitable for Mac App Store submission —
     GUI, Finder Quick Action, watch folder — with the CLI and MCP helper
     excluded and no UI referencing them.

The Direct build is the developer's daily driver. It must come out of this
work **functionally identical**. The MAS build is additive: a second output,
never a modification of the first.

## Why the split is necessary (context, not a task)

Mac App Store apps must run in the App Sandbox, and any helper binary inside
the bundle inherits that sandbox. When Claude Desktop or Terminal launches the
helper directly, it gets its own empty container with no user-granted file
access, so `convert_to_markdown("/some/path")` cannot read the file.
Separately, `install-cli` symlinks into `/usr/local/bin`, which an App Store
app may never write to. Those features cannot ship in a sandboxed App Store
build in their current form, so the MAS build omits them.

The GUI app is already sandboxed (Phase 1: security-scoped bookmarks via
`FolderAccessManager`, `ENABLE_USER_SELECTED_FILES = readwrite`), so little or
no sandbox work should be needed for the app itself — verify rather than
assume.

## Before you start

Confirm the working tree is clean and the current release tag is committed, so
the pre-rename, pre-split state is recoverable. Do the rename and the split as
separate commits.

## Task

### 1. Rename to "Distill.md"

Display name only. Keep build settings and command names period-free:

- **`PRODUCT_NAME` stays `Distill`** — periods in the product name leak into
  the bundle path, executable name, and code-signing paths. Don't do it.
- **Set `CFBundleDisplayName` to `Distill.md`** — this is what Finder, the
  Dock, and the menu bar show.
- **Bundle identifier stays `com.rakan.Distill`** — identifiers don't need to
  match display names, and changing it would reset existing `@AppStorage`
  settings and stored folder grants.
- **CLI command stays `distill`** — command-line tools shouldn't have periods.
- **MCP server key stays `distill`** in the client config snippet.

Update every user-visible occurrence of the old name: About window, window
title, Finder Quick Action / Service names, README, CHANGELOG, help text, and
the release artifact filename. Note in the response which files changed so the
GitHub repo name can be updated to match.

Confirm the exact name with the developer before executing if App Store
availability hasn't been verified yet — "Distill" alone is heavily used on the
App Store and names must be unique there.

### 2. Build configuration split

Add a `Release-MAS` build configuration (and a matching scheme) alongside the
existing `Release`. Prefer configurations + schemes over duplicate targets so
target settings aren't maintained twice — if a separate target is genuinely
cleaner here, explain why before doing it.

Set `SWIFT_ACTIVE_COMPILATION_CONDITIONS` to include `MAS` for the MAS
configuration only, and guard MAS-specific differences with `#if MAS`.

### 3. Exclude the helper from the MAS build

The `distill` binary must not be embedded in `Contents/Helpers` in the MAS
build — the build phase that copies it needs to be conditional on the
configuration. Pick a mechanism that fails loudly rather than silently (a
stray helper in an App Store submission is a rejection), and verify by
inspecting the built `.app` for both configurations.

The `DistillCLI` and MCP targets keep existing in the project; they simply
aren't built or embedded for MAS.

### 4. Bundle identifiers — distinct per build

Both builds must be installable side by side for testing:

- **Direct: `com.rakan.Distill`** (unchanged — preserves existing settings and
  folder grants).
- **MAS: a distinct identifier** (e.g. `com.rakan.Distill.mas`). Invisible to
  users; it's what gets registered in App Store Connect.

Verify that installing one does not replace or shadow the other in Launch
Services, and that they don't share `@AppStorage`/preferences domains in a way
that causes cross-talk.

### 5. Entitlements

Separate entitlements files per configuration via `CODE_SIGN_ENTITLEMENTS`:

- Direct: current entitlements.
- MAS: App Sandbox on, hardened runtime on, user-selected-files read/write,
  plus whatever the Finder extension and watch folder genuinely need — and
  nothing more. Audit for entitlements that exist only to serve the CLI/MCP
  path and drop them from MAS.

### 6. UI and text surfaces

Under `#if MAS`, remove or hide anything referencing the excluded features:

- Any Settings item for installing/enabling the CLI.
- About window / Help menu text mentioning CLI or MCP.
- Feature or format lists that imply CLI availability.

While in those surfaces: the drop-zone format list is still the Phase 1 list
(`PDF · TXT · MD · CSV · TSV · HTML`) in the current build. Fix it in **both**
configurations — it should reflect Word, PowerPoint, Excel (and ZIP once that
lands).

### 7. Privacy manifest

Add a `PrivacyInfo.xcprivacy` declaring required-reason API usage (file
timestamps, user defaults, disk space — audit what's actually used) and "data
not collected." Missing or incorrect privacy manifests are a leading App Store
rejection cause. Include it in both builds; it's harmless in the direct build.

### 8. Versioning

App Store requires a monotonically increasing `CFBundleVersion`. Make sure
both builds derive version/build numbers from one source of truth so they
can't drift.

### 9. Documentation

- README: a short "Which build do I want?" section — direct build for CLI and
  MCP (with the GitHub release link), App Store build for the GUI.
- CHANGELOG: note the rename and the build split.
- `CLAUDE.md`: document how to build each configuration.

## Guard rails

- **DistillCore must not diverge.** All converter behavior stays identical
  between builds; the flag governs packaging and UI only. No `#if MAS` inside
  converter logic.
- **The harness stays green**, and keeps testing DistillCore
  configuration-independently.
- **The Direct build must be functionally unchanged.** Verify after the split:
  CLI works, MCP responds to a real client call, Finder Quick Action works,
  watch folder works, existing settings and folder grants survive.
- Verify the MAS build launches, converts files through the GUI, and contains
  no `Contents/Helpers`.

## Decisions to raise before implementing

Ask rather than assume:

1. **`textutil` in the MAS build.** Legacy `.doc`/`.rtf` support spawns
   `/usr/bin/textutil`. Subprocess spawning from a sandboxed app is a review
   risk. Options: keep it and accept the risk, or compile out legacy
   `.doc`/`.rtf` in MAS only (with format lists adjusted to match). Current
   lean: keep it, and drop it only if a review rejection forces the issue.
2. **MAS build scope.** Omit CLI/MCP entirely (the plan), or later add an
   XPC-client variant where the helpers forward requests to the running app
   over a pre-granted folder scope. Not building the XPC path now — just don't
   foreclose it architecturally.

## Out of scope

- Actual App Store submission, App Store Connect setup, certificates, or
  enrolling in the Apple Developer Program.
- The XPC helper architecture.
- Notarization changes to the direct build.

## Done when

The rename is applied everywhere user-visible, both configurations build
clean, the Direct build is verified unchanged (including CLI and a live MCP
call), the MAS build is sandbox-clean with no embedded helper, both are
installable side by side, the harness is green, and the docs describe the
split.
