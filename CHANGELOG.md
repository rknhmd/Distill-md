# Changelog

All notable changes to Distill are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

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
