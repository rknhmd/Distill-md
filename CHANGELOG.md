# Changelog

All notable changes to Distill are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [2.1.0] - 2026-07-25

### Added
- **ZIP archive conversion** — drop a .zip and get one combined
  Markdown document: every supported file inside is converted under a
  `# path/inside/zip` section header in stable path order; skipped
  entries (unsupported formats, nested archives) are listed at the
  end. Junk (`__MACOSX/`, `.DS_Store`, hidden files) is ignored.
  Untrusted-input guards: 500 MB / 1,000-entry caps, path-traversal
  (zip-slip) rejection, no recursion into nested archives. Available
  in the app, the CLI, and MCP.
- **Session output override** — the status bar's destination readout
  is now a control: pick "Next to original files" or a one-off folder
  for *this session only*. The Settings default is untouched (and wins
  again on next launch); the status bar shows "— this session" while
  an override is active, and Settings notes when it's being
  overridden. Session folder grants are deliberately not persisted.

### Changed
- Drop-zone and About format lists now include the Office formats and
  ZIP.

## [2.0.1] - 2026-07-13

Performance release — supersedes 2.0.0.

Measured (Time Profiler, same batch → preview → clear workload):
main-thread CPU 34.8 s → 13.5 s; hangs 8 → 3 with cumulative hang time
22.3 s → 4.3 s; SwiftUI ViewGraph work 22.9 s → 3.6 s; AttributeGraph
invalidation 9.3 s → 0.1 s; NSView teardown 11.9 s → 1.6 s.

A residual 2.27 s Severe Hang traced to the raw preview laying out one
giant glyph layer (CA::Transaction::commit). The raw view now renders
in lazy ~1.5 KB line-boundary chunks, so only visible text lays out:
a third profiler run on a 300 KB raw preview shows **zero hangs** and
CA::Transaction::commit down from 9.1 s to 0.2 s. (Trade-off: drag
selection doesn't span chunk boundaries — Copy remains the
whole-document path.)

The preview now also *streams*: selecting a file cancels the previous
file's in-flight parse (stale batches can never reach the UI), the
first ~25 blocks render from a small first batch while the rest keeps
parsing in the background, and switching away clears the old tree in
one cheap transaction. Measured on a huge → small → huge selection
sequence (PreviewFirstPaint signposts, Instruments): first content in
**58 ms / 59 ms**, zero hangs.

### Fixed
- **Preview and Clear no longer hang.** Time Profiler showed ~96% of
  CPU time on the main thread with Severe Hangs when previewing a
  large converted file or clearing a big batch. The queue no longer
  keeps every document's Markdown in memory (the output file is the
  source of truth), the preview loads and parses on a background task,
  and large outputs display the first 50 KB with a "Show full output"
  control. Copy and auto-copy always deliver the complete document,
  read back from disk.
- CLI: when an unquoted path with spaces splits into several "no such
  file" errors, the error now includes the exact quoted path to use.
  (Quoted paths always worked.)

### Verified
- DOCX hyperlinks: display text is preserved (`[text](url)`); a
  `[url](url)` result means the document's visible text was the URL
  itself. Now regression-locked in the harness.
- The regression harness (fixtures + runner) now lives in the repo
  under `convtest/` with deterministic regeneration scripts.

## [2.0.0] - 2026-07-08

The integration release: Distill becomes usable by other tools, not
just humans.

### Added
- **MCP server** — `distill mcp` speaks the Model Context Protocol
  over stdio (official Swift SDK), so Claude Desktop and Claude Code
  can convert documents directly. Tools: `convert_to_markdown`,
  `convert_file`, `list_supported_formats`.
- **`distill` CLI** — shipped inside the app at
  `Contents/Helpers/distill`: `convert` (with `--output-dir`,
  `--front-matter`, `--extract-images`, `--stdout`), `list-formats`,
  and `install-cli` (symlinks itself into /usr/local/bin).
- **Image extraction** (off by default) — embedded images from Word,
  PowerPoint, and PDF land in `<name>-assets/` next to the .md, linked
  at their positions, deduplicated by content hash.
- **Clipboard conversion** — ⌘⇧V converts HTML/RTF on the clipboard to
  Markdown in place; plain text passes through with a note.
- **Multi-column PDFs** — unambiguous two-column pages now read left
  column then right, with conservative guard rails (anything uncertain
  keeps the old order).

### Changed
- The conversion engine now lives in **DistillCore**, a standalone
  local Swift package shared by the app, the CLI/MCP helper, and the
  test harness.
- The helper binary is intentionally unsandboxed (headless tools can't
  request file grants); the app remains fully sandboxed.

## [1.1.0] - 2026-07-08

Fidelity release: existing converters get measurably better output.

### Added
- **PPTX tables** — slide tables now convert to Markdown tables in their
  slide position. Merged cells keep the value in the origin cell and
  leave continuation cells empty.
- **DOCX hyperlinks** — link URLs are resolved from the document's
  relationships and emitted as `[text](url)`; internal anchor links
  keep their text.
- **XLSX dates** — date/time-formatted cells render as ISO 8601
  (`2026-07-08`, `14:30`, or both) instead of raw serial numbers.
  Handles built-in and custom number formats, both the 1900 date system
  (including Excel's leap-year quirk) and the 1904 system.
- **YAML front matter** (optional, off by default) — a Settings toggle
  prepends source, date, format, page/slide/sheet count, and the token
  estimate to converted files. Markdown inputs with existing front
  matter are left untouched.

### Changed
- **Token estimates** are now content-aware: code and URLs count at
  ~3 characters per token, CJK text at ~1.3, prose at ~4 — instead of a
  flat chars÷4. Still an estimate, still zero dependencies.
- Quick Action: no more "Couldn't communicate with a helper
  application" dialog; the app comes forward on its own when files
  arrive.

## [1.0.0] - 2026-07-08

First release.

### Added

**Conversion**
- Converters for PDF, DOCX, PPTX, XLSX, legacy .doc/.rtf, HTML, CSV/TSV,
  and TXT/Markdown — all fully native (Apple frameworks + ZIPFoundation
  and CoreXLSX).
- On-device OCR fallback (Vision framework) for PDF pages without a text
  layer; per page, so mixed documents keep their real text.
- DOCX: headings by style, bold/italic, bullet vs numbered lists resolved
  through numbering.xml, tables.
- PPTX: one section per slide with title, body bullets, and speaker notes.
- XLSX: one Markdown table per sheet; shared/inline strings, formula
  results, sparse-cell padding.
- Legacy .doc/.rtf via macOS's built-in textutil, piped through the same
  HTML-to-Markdown parser used for .html input.
- Duplicate-safe output naming (name.md, name-2.md, …) — never overwrites.

**App**
- Drag-and-drop queue with per-file status, type icons, and failure reasons.
- Markdown preview pane with Rendered/Raw toggle, Copy and Open buttons.
- Token count estimate (chars ÷ 4) per converted file.
- Output modes: alongside the source file, or a single chosen folder —
  sandbox-correct via security-scoped bookmarks with a one-time
  Grant Access prompt per folder.
- Optional auto-copy to clipboard after single-file conversions.
- Light and dark mode.

**System integration**
- Finder Quick Action: right-click files → "Convert to md".
- "Open With → Distill" for all supported formats.
- Watch folder: files added to a chosen folder convert automatically
  while Distill runs (Markdown files skipped to prevent loops).
- File menu with Add Files… (⌘O) and Convert All (⌘⏎); custom About window.
