# Distill — Project Brief

## What this is

Distill is a native macOS app (SwiftUI) that converts documents into clean
Markdown, optimized for feeding to AI models. Markdown is the most
token-efficient format for LLM consumption — the app's entire purpose is
"drop file in, get AI-ready .md out."

This is the second-generation rewrite of an existing Python/Tkinter app
called MarkdownDrop (v1), which lives in a separate folder and must never
be touched. Distill is a fresh, fully native Swift project.

## Hard constraints

1. **Fully native — no shortcuts.** No Python sidecar, no bundled
   interpreters, no Electron. All conversion is done in Swift using Apple
   frameworks and (sparingly) Swift packages. The goal is a small (~5MB),
   fast, professional Mac app AND a learning project — the developer is a
   second-year computer engineering student building this partly for
   portfolio value.
2. **The Xcode project already exists**: SwiftUI app named "Distill",
   bundle ID com.rakan.Distill, in ~/Developer/. Work inside it.
3. **macOS only.** Target the current macOS SDK. App must support both
   light and dark mode natively.
4. **Build with xcodebuild after every meaningful change** and fix errors
   before moving on. The developer will also build/run in Xcode (⌘R) to
   verify UI.
5. The developer is new to Swift. Prefer clear, idiomatic, well-commented
   code over clever code. When making an architectural choice, briefly
   explain it.

## Conversion engine plan (all native)

- PDF: PDFKit for text extraction. If a page has no text layer, fall back
  to Vision framework OCR (Phase 3).
- TXT / MD: passthrough with cleanup.
- CSV / TSV: parse and emit Markdown tables.
- HTML: strip to semantic Markdown (headings, links, lists, tables).
- DOCX: OOXML parsing — unzip (ZIPFoundation), parse word/document.xml
  with XMLParser. Extract headings (by style), paragraphs, lists, tables,
  bold/italic. (Phase 2)
- PPTX: unzip, parse ppt/slides/slideN.xml — slide titles, body text,
  speaker notes. (Phase 2)
- XLSX: use the CoreXLSX Swift package rather than hand-rolling. Emit one
  Markdown table per sheet. (Phase 2)
- Legacy .doc/.rtf: convert via macOS's built-in `textutil` CLI (this is
  an OS tool, not a bundled dependency — acceptable).

Allowed Swift package dependencies: ZIPFoundation, CoreXLSX. Everything
else should be Apple frameworks. Ask before adding any other dependency.

## Roadmap

### Phase 1 — Core app (start here)
- SwiftUI shell: main window with drag-and-drop zone, file queue list
  (name, type icon via SF Symbols, size, status), output folder picker,
  convert button, per-file status (pending/converting/done/failed with
  reason).
- Settings persisted with @AppStorage: output folder mode (alongside
  source vs custom folder), auto-copy-to-clipboard toggle.
- Working converters: PDF (text-layer), TXT/MD, CSV/TSV, HTML.
- Conversion runs off the main thread; UI stays responsive; progress
  shown.
- Duplicate-name handling: never overwrite; append -2, -3, etc.
- Markdown preview pane: select a converted file to view its output;
  Copy and Open buttons.

### Phase 2 — Office formats
- DOCX extractor (headings, paragraphs, lists, tables, basic inline
  formatting).
- PPTX extractor (titles, body text, speaker notes, one section per
  slide).
- XLSX via CoreXLSX (Markdown table per sheet).
- Legacy .doc/.rtf via textutil.

### Phase 3 — Differentiators
- OCR fallback for image-only PDF pages via Vision framework.
- Token count estimate per converted file (approximate GPT-style BPE
  count; a simple chars/4 heuristic with a note is acceptable v1, a real
  tokenizer later).
- Auto-copy-to-clipboard after single-file conversion (respect the
  setting).
- Rendered Markdown preview (not just raw text).

### Phase 4 — System integration
- Finder Quick Action extension: right-click file → "Convert to
  Markdown".
- Watch folder: auto-convert anything dropped into a chosen folder.
- App icon, About window, final polish.

### Phase 5 — Publish
- GitHub-ready: README, LICENSE (MIT), CHANGELOG, .gitignore for Xcode.
- Zipped .app as a GitHub Release artifact.
- App remains unsigned for now (right-click → Open); notarization is a
  later decision.

## Working style

- Complete one phase before starting the next; within a phase, build and
  verify incrementally.
- At the end of each phase, summarize what was built and list what the
  developer should manually test.
- Keep the code organized: Models/, Views/, Converters/, Services/
  groups in the project.
