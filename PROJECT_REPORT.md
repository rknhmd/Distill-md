# Distill — Project Report

**Date:** July 8, 2026
**Status:** v1.0.0 built, installed, and functional — all five phases of the project brief delivered
**Footprint:** 28 Swift files, ~3,900 lines · 3.7 MB installed app (goal was ~5 MB) · 1.1 MB release zip

Distill is a fully native macOS app (SwiftUI) that converts documents into clean,
token-efficient Markdown for feeding to AI models. It was built phase by phase
against `distill-project-brief.md`, under two hard constraints: **no non-native
code** (no Python, no Electron, no bundled interpreters) and only two approved
Swift packages (ZIPFoundation, CoreXLSX). Everything else is Apple frameworks.

---

## Phase 1 — Core app

**The shell.** A two-pane main window: file queue on the left (drop files
anywhere in the window, or ⌘O / toolbar button), Markdown preview on the right.
Every queued file shows its type icon, size, and live status —
pending / converting / done / failed-with-reason. Unsupported files stay visible
in the queue with the reason instead of vanishing. A bottom status bar shows the
output destination and run progress; Settings (⌘,) persist via `@AppStorage`.

**The first four converters.** PDF (PDFKit text layer), TXT/MD (cleanup
passthrough that respects Markdown's whitespace semantics), CSV/TSV (RFC-4180
state machine: quoted fields, embedded delimiters/newlines, `""` escapes), and
HTML — a ~400-line hand-rolled tolerant tag scanner producing headings, links,
lists, tables, blockquotes, and code fences. `NSAttributedString`'s importer was
rejected deliberately: it's main-thread-only and flattens tables.

**The sandbox architecture** (the defining Phase 1 decision). Dropping a file
into a sandboxed app grants access to *that file*, not its folder — so "save
alongside source" can't just write. `FolderAccessManager` implements
probe → stored security-scoped bookmark → one-time "Grant Access" panel
(pre-pointed at the folder). Each folder is asked once, ever; grants persist
across launches. Outputs never overwrite: `name.md`, `name-2.md`, ….

**Concurrency model.** The project uses Swift's default-MainActor isolation.
All conversion work hops off the main thread through a single `@concurrent`
engine entry point; converters are explicitly `nonisolated`. The UI never
blocks — it only suspends while awaiting results.

## Phase 2 — Office formats

Two approved packages were wired into the project (hand-edited `project.pbxproj`
for SPM references): **ZIPFoundation** and **CoreXLSX**.

- **DOCX** — unzips the OOXML package and SAX-parses `word/document.xml` with
  Foundation's `XMLParser`: headings by paragraph style, bold/italic with
  adjacent-run merging (Word fragments sentences into many runs), tables, and
  lists — with `word/numbering.xml` parsed separately so bullet vs numbered
  comes out right, including nesting.
- **PPTX** — enumerates `ppt/slides/slideN.xml` in numeric order (slide10 after
  slide2), extracts title placeholders and body text as indented bullets, skips
  slide-number/date/footer chrome, and appends speaker notes per slide.
- **XLSX** — CoreXLSX-based: one Markdown table per sheet, shared/inline
  strings, cached formula results, sparse cells padded by column reference,
  5,000-row safety cap.
- **Legacy .doc / .rtf** — staged into the sandbox temp folder and run through
  macOS's built-in `textutil` to HTML, then through the same HTML→Markdown
  parser as `.html` files (structure preserved, zero new dependencies).

A notable find during testing: `textutil`-generated .docx files contain no real
`w:tbl` tables (they fake them with tabs), so a hand-crafted OOXML fixture was
built to prove the table path — files from real Word/Pages/LibreOffice work.

## Phase 3 — Differentiators

- **OCR fallback** — PDF pages whose text layer has fewer than 10 characters
  are rendered to a bitmap (~180 DPI, capped at 4000 px) and recognized with
  Vision's `RecognizeTextRequest`, fully on-device. Per page: a mixed document
  keeps its real text and only OCRs the scans. This made the converter protocol
  `async` — sync converters satisfy it unchanged.
- **Token estimates** — the standard chars ÷ 4 approximation, shown in each
  queue row ("Word · 12 KB · ~3.2k tokens") and as a badge in the preview
  header with an explanatory tooltip.
- **Auto-copy** — when a run converts exactly one file and the setting is on,
  the Markdown lands on the clipboard with a status-bar flash.
- **Rendered preview** — a native SwiftUI Markdown renderer (no WebView): a
  ~150-line block parser (headings, lists, tables, code fences, quotes) plus
  per-block views, with `AttributedString(markdown:)` handling inline styling.
  Segmented **Rendered | Raw** toggle, persisted.

## Phase 4 — System integration

- **Finder Quick Action** — a second target, `DistillQuickAction` (.appex,
  action extension). It converts nothing itself: it collects the selected
  files and opens them with the main app via
  `NSWorkspace.open(_:withApplicationAt:)`, because Launch Services transfers
  sandbox read access with the open — the same grant drag-and-drop produces.
- **"Open With → Distill"** — document types declared for all 11 formats
  (Viewer role, Alternate rank: Distill never steals double-click ownership).
  Files arrive through `AppDelegate.application(_:open:)` and convert
  immediately; arrivals during an active run join it.
- **Watch folder** — kqueue-backed `DispatchSource` monitoring with a 1.5 s
  debounce, a baseline snapshot (pre-existing files are never touched),
  stability checks for half-copied files, and Markdown exclusion so converted
  output can't loop back in. Toggle + folder picker in Settings; "Watching
  'folder'" indicator in the status bar.
- **Polish** — programmatically generated app icon (gradient squircle, white
  drop, all 10 catalog sizes from an AppKit script), custom About window,
  File menu with Add Files… (⌘O) and Convert All (⌘⏎).

## Phase 5 — Publish

- **README** — features, format table, install and build-from-source
  instructions, architecture notes, privacy statement.
- **LICENSE** — MIT. **CHANGELOG** — Keep-a-Changelog v1.0.0.
- **.gitignore** — Xcode/Swift standard; the user-state file tracked by the
  initial commit was untracked.
- **Release artifact** — Release build zipped with `ditto --keepParent` into
  `dist/Distill-1.0.0.zip`; round-trip extraction and signature verified.

## Post-release: installation & the Quick Action debugging story

**Installation.** The Release build was installed to `/Applications`, registered
with Launch Services, and launched — Distill now appears in the Apps library,
Spotlight, and Dock. Locally built apps carry no quarantine flag, so no
right-click → Open dance is needed on this machine (only for downloaders of
the GitHub zip).

**The Quick Action needed three real fixes**, found by instrumenting the
extension (filesystem breadcrumbs — the unified log was unqueryable in this
environment):

1. **It never appeared** — two causes: the extension was registered but had no
   enablement "election" (fixed via `pluginkit -e use`), and the activation
   rule used the dictionary form, which Finder ignores; replaced with the
   predicate-string (`SUBQUERY … UTI-CONFORMS-TO "public.data"`) form.
2. **It appeared but did nothing** — breadcrumbs showed the handler running
   with *zero* usable attachments: the code filtered for providers conforming
   to `public.file-url`, but Finder registers attachments under the file's own
   type (`com.adobe.pdf`, …). Rewrote URL extraction to load via the provider's
   registered type with `loadInPlaceFileRepresentation` as fallback.
3. **It converted but showed "Couldn't communicate with a helper
   application"** — the extension waited for `NSWorkspace.open`'s completion
   while also activating the app, which tears down Finder's connection to the
   extension. Now it submits the open, completes the Finder request
   immediately, and the *app* activates itself when files arrive.

Along the way the action was renamed to **"Convert to md"** (per request), and
a classic **macOS Service** with the same name was added as a second right-click
path (registered in the app's Info.plist + `NSApp.servicesProvider`; the
services daemon cache was flushed — Services menus can lag until re-login).

## Verification

All converters were exercised by a standalone SPM harness compiling the app's
converter sources directly, against real fixtures: textutil-generated Office
files, hand-crafted OOXML with edge cases (sparse spreadsheet cells, multi-run
paragraphs, numeric slide ordering, escaped pipes), a cupsfilter-generated
text PDF, and a purpose-built image-only PDF for OCR. **All 14 conversions
passed**, including three expected-failure error paths (empty file, fake PDF,
corrupt DOCX → clean, specific failure messages). The OCR path recovered text
from the scanned fixture. The end-to-end app flow was verified live:
`open -a Distill file.pdf` → converted `.md` on disk, and the Quick Action
chain confirmed by breadcrumb evidence and a successful conversion.

## Known limitations (deliberate v1 scope)

- XLSX dates render as raw serial numbers; DOCX hyperlink URLs aren't emitted
  (link text is kept); PPTX tables are skipped (slide text is kept).
- Token estimate is the chars ÷ 4 heuristic, not a real tokenizer.
- Watch folder ignores `.md` inputs by design (loop prevention).
- The app is ad-hoc signed; notarization is a later decision (right-click →
  Open for downloaded copies).

## Current state & next steps

- Git: 3 commits (`Initial Commit` → phases 1–3 → phases 4–5). The Quick
  Action fixes, rename, and Service addition are **uncommitted** pending final
  confirmation that the last fix runs clean — after which the debug
  breadcrumbs should be stripped and `dist/Distill-1.0.0.zip` regenerated.
- To publish: create the GitHub repo, push, draft a v1.0.0 release, attach the
  zip. Screenshots for the README are worth adding once the UI is final.
