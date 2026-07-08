# Distill v2 — Project Brief

## Context

Distill v1.0.0 is complete: a fully native macOS SwiftUI app (~3.7 MB) that
converts documents to clean Markdown for AI consumption. 28 Swift files,
~3,900 lines. All converters conform to one `MarkdownConverting` protocol.
Approved dependencies so far: ZIPFoundation, CoreXLSX. Everything else is
Apple frameworks. The constraint stands: **fully native, no Python, no
bundled interpreters.**

Read `PROJECT_REPORT.md` (or CLAUDE.md) for the v1 architecture before
changing anything. The existing converter harness (SPM package compiling the
app's converter sources against fixtures) is the regression suite — extend
it with fixtures for every change in this brief, and keep all 14 existing
conversions passing.

Competitive context that motivates this release: markitdown (Microsoft) is
the baseline tool in this space (82% F1 in independent benchmarks); the
tools that beat it (Docling 88%, LlamaParse 92%) win almost entirely on
**table fidelity**. markitdown's most notable recent addition is an **MCP
server** so LLM clients can invoke conversion directly. Distill's angle:
native, 4 MB, on-device, no Python environment — now with the same
integration surface.

## Release plan

Two releases. Complete and tag v1.1.0 before starting v2.0 work.

---

# v1.1.0 — Fidelity fixes

Small, high-value gaps in existing converters. No new architecture.

### 1. PPTX tables (highest priority)
Slide XML contains `a:tbl` / `a:tr` / `a:tc` elements that the extractor
currently skips. Emit them as Markdown tables in slide order, integrated
with the existing title/body/notes flow. Handle merged cells by repeating
the value or leaving empty cells — pick one, document it. Add a real-world
fixture (a hand-crafted OOXML table fixture is fine, but ALSO test against
a table made in actual PowerPoint or Keynote-exported .pptx if available).

### 2. DOCX hyperlink URLs
Link text currently survives; URLs are dropped. URLs live in
`word/_rels/document.xml.rels` keyed by relationship ID
(`r:id` on `w:hyperlink`). Parse the rels file, emit `[text](url)`.
Internal anchors (no rels entry) keep text only.

### 3. XLSX date rendering
Date cells currently render as raw serials (e.g. `45123`). Detect
date-formatted cells via CoreXLSX's number-format info and render ISO 8601
dates (`2026-07-08`). Respect the 1900 date system including Excel's
leap-year quirk; if the workbook uses the 1904 system flag, handle it.
Times and datetimes: render as `HH:MM` / `YYYY-MM-DD HH:MM` when the
format indicates them.

### 4. YAML front matter (optional, off by default)
A Settings toggle: "Include metadata header". When on, prepend:

```yaml
---
source: lecture-05.pptx
converted: 2026-07-08
format: PowerPoint
pages: 24            # pages/slides/sheets — whichever applies
tokens: ~3200        # the estimate
---
```

Front matter must not be double-emitted for .md inputs that already
have front matter.

### 5. Smarter token estimate
Keep zero-dependency, but replace flat chars÷4 with a heuristic that
adjusts for content type: code fences and URLs tokenize denser (~3
chars/token), CJK text ~1–1.5 chars/token, prose ~4. Label stays "~" and
the tooltip keeps saying it's an estimate. Do NOT bundle a tokenizer
vocabulary in this release (app size matters).

**Release:** bump version, CHANGELOG, regenerate the zip, tag v1.1.0.

---

# v2.0.0 — The integration release

Headline: Distill becomes usable by other tools, not just humans.

### 1. MCP server mode (flagship)
Add an MCP (Model Context Protocol) server so MCP clients — Claude
Desktop, Claude Code — can invoke Distill's converters directly.

- Use the official MCP Swift SDK (modelcontextprotocol/swift-sdk). This is
  a NEW dependency — it's approved. Verify current API against its README
  at implementation time rather than assuming.
- Transport: stdio. Ship it as a small companion executable target
  (`distill-mcp`) inside the app bundle (Contents/MacOS or
  Contents/Helpers), so the .app remains the single artifact users
  download.
- Tools to expose:
  - `convert_to_markdown(path) -> markdown` — converts a file, returns the
    Markdown text directly (does not write a file unless asked).
  - `convert_file(path, output_dir?) -> output_path` — converts and writes
    the .md, returns where it landed.
  - `list_supported_formats() -> [...]`
- Sandbox note: the MCP process runs outside the app's GUI sandbox flow —
  decide deliberately whether the helper is sandboxed (and document file
  access implications) or unsandboxed CLI-style. Explain the choice.
- README gets a "Use with Claude Desktop / Claude Code" section with the
  exact JSON config snippet users paste in.

### 2. CLI companion
A `distill` command-line executable (same binary as the MCP helper or a
sibling target — prefer one binary with subcommands: `distill convert
file.pdf`, `distill mcp`). Flags: `--output-dir`, `--front-matter`,
`--stdout`. Include a short "install the CLI" path (symlink from the app
bundle into /usr/local/bin or a `distill install-cli` command; ask the
user which pattern they prefer before implementing).

### 3. Image extraction
Settings toggle, off by default: "Extract embedded images". When on,
images from DOCX (word/media/), PPTX (ppt/media/), and PDF (page images
via PDFKit) are written to `<name>-assets/` next to the .md, with
relative links `![](name-assets/image1.png)` at the correct positions
(DOCX/PPTX: where the `a:blip`/drawing reference occurs; PDF: end of the
page's text is acceptable). Dedupe identical images by content hash.
Watch-folder mode must not re-ingest the assets folder.

### 4. Clipboard conversion
Menu item + shortcut (⌘⇧V "Convert Clipboard"): read HTML or RTF from
the pasteboard (RTF → HTML via textutil staging, HTML → existing HTML
converter), put the resulting Markdown back on the clipboard, flash the
status bar. If the pasteboard has only plain text, pass it through
unchanged with a status note.

### 5. Multi-column PDF reading order (best-effort)
Current extraction interleaves columns on 2-column layouts. Improve with
x-position clustering per page: detect when text blocks form two (or
more) distinct column bands and emit left column top-to-bottom, then
right. Guard rails: only re-order when column separation is unambiguous
(clear gutter, similar band widths); otherwise fall back to current
behavior. Add fixtures: a 2-column PDF and a normal PDF that must NOT be
re-ordered.

**Release:** version bump, CHANGELOG, README rewrite around the new
story ("native document infrastructure for AI workflows"), regenerate
zip, tag v2.0.0.

---

# Explicitly OUT of scope (do not build)

- PDF table detection. Without an ML model this is heuristic-only and
  fails often; competitors solve it with dedicated models (TableFormer).
  It may become an experimental branch later — not in these releases.
- Bundled BPE tokenizer vocabulary.
- Notarization/signing changes (separate decision, needs a paid Apple
  Developer account).
- Any cloud or LLM-API integration. Everything stays on-device.

# Working style

- One numbered item at a time; extend the harness with fixtures before or
  with the implementation; keep all prior fixtures green.
- Build with xcodebuild after every meaningful change (the DEVELOPER_DIR
  workaround is in CLAUDE.md).
- Commit at natural checkpoints with clear messages; tag releases.
- The developer is still learning Swift — explain non-obvious choices
  briefly (concurrency isolation, sandbox implications, SPM wiring).
- At the end of each release, produce a summary and a manual test list
  like the Phase 1–5 reports did.
