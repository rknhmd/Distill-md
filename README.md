<p align="center">
  <img src="Distill/Assets.xcassets/AppIcon.appiconset/icon_256x256@1x.png" width="128" alt="Distill icon">
</p>

<h1 align="center">Distill</h1>

<p align="center"><b>Native document infrastructure for AI workflows.</b></p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS-blue" alt="Platform: macOS">
  <img src="https://img.shields.io/badge/Swift-native-orange" alt="Swift">
  <img src="https://img.shields.io/badge/MCP-server-8A2BE2" alt="MCP server">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License: MIT">
</p>

Distill converts documents into clean, token-efficient Markdown for AI
consumption — and exposes that ability to everything on your Mac: a
drag-and-drop app, a Finder Quick Action, a watch folder, a `distill`
CLI, and an **MCP server** that lets Claude Desktop and Claude Code
convert files themselves.

It is a fully native Swift app — under 15 MB with the MCP server
included, versus the hundreds of MB a Python or Electron equivalent
drags in. No interpreter, no cloud: every conversion happens
on-device, OCR included.

## The three ways in

**The app.** Drop files anywhere in the window (or right-click →
Quick Actions → *Convert to md* in Finder). Per-file status, rendered
Markdown preview, token estimates, watch folder, never overwrites.

**The CLI.**

```sh
/Applications/Distill.app/Contents/Helpers/distill install-cli   # once

distill convert report.pdf slides.pptx        # .md next to each source
distill convert data.xlsx --output-dir ~/md   # or into a folder
distill convert report.pdf --stdout           # straight to stdout
distill convert deck.pptx --front-matter --extract-images
distill convert "Ch25 textbook.pdf"           # quote paths with spaces
```

**MCP (Claude Desktop / Claude Code).** Add to your client's MCP
config (`claude_desktop_config.json`, or `claude mcp add` for Claude
Code):

```json
{
  "mcpServers": {
    "distill": {
      "command": "/Applications/Distill.app/Contents/Helpers/distill",
      "args": ["mcp"]
    }
  }
}
```

Tools exposed: `convert_to_markdown(path, front_matter?)` returns the
Markdown directly; `convert_file(path, output_dir?, front_matter?,
extract_images?)` writes the .md and returns its path;
`list_supported_formats()`.

## What the conversions get right

| Format | Fidelity notes |
| --- | --- |
| PDF | Text layer via PDFKit; per-page Vision OCR fallback for scans; two-column pages read in correct order (guarded heuristic); embedded images extractable |
| Word (.docx) | Headings, bold/italic, bullet vs numbered lists, tables, hyperlink URLs, inline images |
| PowerPoint (.pptx) | One section per slide: title, body bullets, tables (merged cells handled), speaker notes, images |
| Excel (.xlsx) | Markdown table per sheet; dates/times as ISO 8601 (1900 & 1904 systems); shared/inline strings; formula results |
| Legacy .doc / .rtf | macOS textutil → the HTML pipeline |
| HTML | Hand-rolled tolerant parser: headings, links, lists, tables, code |
| CSV / TSV | RFC-4180 parsing → Markdown tables |
| TXT / MD | Cleanup passthrough |
| ZIP archives | One combined document: every supported file inside, sectioned by path in stable order; skipped entries listed. 500 MB / 1,000-entry caps, zip-slip rejection, no nested-archive recursion |

Everywhere: token estimates (content-aware: prose ~4 chars/token, code
~3, CJK ~1.3), optional YAML front matter (source, date, format,
pages, tokens), duplicate-safe naming, image extraction into
`<name>-assets/` with content-hash dedupe.

Also in the app: **⌘⇧V converts the clipboard** — copy rich text or
HTML anywhere, get Markdown back.

## Which build do I want?

Distill ships as two builds from one codebase:

| | **Direct** (this repo's releases) | **Mac App Store** |
| --- | --- | --- |
| App, Finder Quick Action, watch folder | ✅ | ✅ |
| `distill` command-line tool | ✅ | — |
| MCP server for Claude Desktop / Code | ✅ | — |
| Install | download + right-click Open | one click, auto-updates |

**Want the CLI or the MCP server? Take the Direct build.** App Store apps
must run in the App Sandbox, and a helper binary inside a sandboxed
bundle inherits that sandbox — launched by Claude Desktop or a terminal
it gets an empty container and can't read the files you name. Symlinking
into `/usr/local/bin` isn't permitted there either. Rather than ship a
version of those features that quietly fails, the App Store build leaves
them out. Conversion quality is identical in both.

## Install

1. Download the zip from the latest [GitHub Release](../../releases),
   unzip, move `Distill.app` to `/Applications`.
2. First launch of a downloaded copy: right-click → **Open** → **Open**
   (the app is not yet notarized).
3. Optional: `distill install-cli` for the terminal, and the MCP config
   above for Claude.

## Build from source

Xcode 26 on macOS. Clone, `open Distill.xcodeproj`, ⌘R. Package
dependencies (ZIPFoundation, CoreXLSX, MCP swift-sdk) resolve on first
build. The conversion engine also builds standalone:
`cd DistillCore && swift build`.

## Architecture

- **DistillCore** — a local Swift package holding every converter and
  the engine facade. Public surface: `ConversionEngine`, `FileType`,
  `ConversionResult`, plus front-matter/token utilities. The three
  consumers (app, CLI/MCP helper, regression harness) all speak this
  API and nothing else.
- **The app** owns the sandbox story: drag/open grants, security-scoped
  bookmarks with a one-time Grant Access panel per folder, watch-folder
  monitoring, SwiftUI throughout.
- **The helper** (`Contents/Helpers/distill`) is one binary with
  subcommands — CLI and MCP server. It is deliberately *unsandboxed*:
  users and MCP clients hand it arbitrary paths, which a sandboxed
  process couldn't read headlessly. The GUI app stays fully sandboxed.
- **Concurrency:** UI on the main actor; conversions hop through one
  `@concurrent` entry point to background threads.

## Privacy

No network, no telemetry, no accounts. Vision OCR runs locally. The
MCP server only ever reads the paths a client passes it.

## License

[MIT](LICENSE) © 2026 Rakan Hamadeh
