# Changelog

All notable changes to Distill are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

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
