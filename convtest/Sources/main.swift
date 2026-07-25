// Regression harness: runs DistillCore's public engine API against the
// fixture files — the same entry point the app, CLI, and MCP server use.
// Usage: swift run convtest <samples-dir>

import Foundation
import DistillCore

let samplesDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "samples", isDirectory: true)
var failures: [String] = []

@MainActor
func run(_ name: String, expectFailure: Bool = false) async {
    let url = samplesDir.appendingPathComponent(name)
    print("\n===== \(name) =====")
    guard let type = FileType.detect(from: url) else {
        print("!! no FileType detected")
        failures.append("\(name): type detection failed")
        return
    }
    do {
        let markdown = try await ConversionEngine.convert(fileAt: url, type: type).markdown
        print(markdown, terminator: "")
        print("----- (\(markdown.count) chars, OK)")
        if expectFailure { failures.append("\(name): succeeded but should have failed") }
    } catch {
        print("!! \(expectFailure ? "expected failure" : "FAILED"): \(error.localizedDescription)")
        if !expectFailure { failures.append("\(name): \(error.localizedDescription)") }
    }
}

// Phase 1 formats
await run("sample.txt")
await run("Ch25 textbook.txt")   // spaces in filenames (v2.0.1 item 2)
await run("sample.csv")
await run("sample.tsv")
await run("sample.html")
await run("sample.pdf")

// Office formats
await run("feature.docx")
await run("sample.docx")
await run("deck.pptx")
await run("real.pptx")
await run("budget.xlsx")
await run("budget1904.xlsx")
await run("sample.rtf")
await run("sample.doc")

// OCR
await run("scanned.pdf")

// Archives
await run("mixed.zip")
await run("zipslip.zip", expectFailure: true)
await run("toomany.zip", expectFailure: true)

// Error paths
let emptyURL = samplesDir.appendingPathComponent("empty.txt")
FileManager.default.createFile(atPath: emptyURL.path, contents: Data())
await run("empty.txt", expectFailure: true)
try? Data("not a pdf".utf8).write(to: samplesDir.appendingPathComponent("fake.pdf"))
await run("fake.pdf", expectFailure: true)
try? Data("not a zip".utf8).write(to: samplesDir.appendingPathComponent("fake.docx"))
await run("fake.docx", expectFailure: true)

// ===== v1.1 unit checks: front matter + token estimator =====
print("\n===== front matter =====")
let fm = FrontMatter.header(
    sourceName: "Report: final.pptx",
    format: .pptx,
    result: ConversionResult(markdown: "x", unitCount: 24, unitLabel: "slides"),
    tokenEstimate: 3200
)
print(fm, terminator: "")
if !fm.hasPrefix("---\n") || !fm.contains("slides: 24") || !fm.contains("tokens: ~3200")
    || !fm.contains("\"Report: final.pptx\"") || !fm.hasSuffix("---\n\n") {
    failures.append("front matter malformed")
}
if !FrontMatter.contentAlreadyHasFrontMatter("---\ntitle: x\n---\nbody", type: .markdown) {
    failures.append("front-matter double-emit guard broken")
}
if FrontMatter.contentAlreadyHasFrontMatter("--- not front matter", type: .plainText) {
    failures.append("front-matter guard triggers on non-markdown")
}

print("\n===== token estimator =====")
let prose = String(repeating: "The quick brown fox jumps over the lazy dog. ", count: 50)
let cjk = String(repeating: "这是一个用于测试的句子，日本語の文もあります。", count: 100)
let code = "```swift\n" + String(repeating: "let value = compute(alpha: a, beta: b) + helper(x)\n", count: 40) + "```"
let proseTokens = TokenEstimator.estimate(prose)
let cjkTokens = TokenEstimator.estimate(cjk)
let codeTokens = TokenEstimator.estimate(code)
let proseRatio = Double(prose.count) / Double(proseTokens)
let cjkRatio = Double(cjk.count) / Double(cjkTokens)
let codeRatio = Double(code.count) / Double(codeTokens)
print(String(format: "prose: %.2f chars/tok, cjk: %.2f, code: %.2f", proseRatio, cjkRatio, codeRatio))
if !(cjkRatio < 2.0) { failures.append("CJK should tokenize near 1.3 chars/token") }
if !(codeRatio < 3.5) { failures.append("code should tokenize near 3 chars/token") }
if !(proseRatio > 3.5 && proseRatio < 4.6) { failures.append("prose should stay near 4 chars/token") }

// ===== v2 checks: image extraction =====
print("\n===== image extraction =====")
@MainActor
func runImageCheck(_ name: String, expectAssets: Int, expectLinks: Int) async {
    let url = samplesDir.appendingPathComponent(name)
    guard let type = FileType.detect(from: url) else {
        failures.append("\(name): type detection failed"); return
    }
    do {
        let result = try await ConversionEngine.convert(
            fileAt: url, type: type, options: ConversionOptions(extractImages: true)
        )
        let outDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("distill-img-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outDir) }

        let mdURL = outDir.appendingPathComponent("out.md")
        let final = try AssetWriter.materialize(
            markdown: result.markdown, assets: result.assets, besideMarkdownAt: mdURL
        )
        let linkCount = final.components(separatedBy: "out-assets/").count - 1
        let assetFiles = (try? FileManager.default.contentsOfDirectory(
            atPath: outDir.appendingPathComponent("out-assets").path)) ?? []

        print("\(name): assets=\(result.assets.count) files=\(assetFiles.count) links=\(linkCount) \(assetFiles.sorted())")
        if final.contains("distill-asset://") { failures.append("\(name): placeholder not rewritten") }
        if result.assets.count != expectAssets { failures.append("\(name): expected \(expectAssets) assets, got \(result.assets.count)") }
        if assetFiles.count != expectAssets { failures.append("\(name): expected \(expectAssets) asset files, got \(assetFiles.count)") }
        if linkCount != expectLinks { failures.append("\(name): expected \(expectLinks) links, got \(linkCount)") }
    } catch {
        failures.append("\(name) (images): \(error.localizedDescription)")
    }
}
// DOCX embeds the identical PNG twice: 1 deduped asset, 2 links.
await runImageCheck("feature.docx", expectAssets: 1, expectLinks: 2)
// pptxgenjs deck: one PNG on slide 2.
await runImageCheck("real.pptx", expectAssets: 1, expectLinks: 1)
// cupsfilter JPEG PDF: one DCT image.
await runImageCheck("photo.pdf", expectAssets: 1, expectLinks: 1)
// Extraction OFF must leave no placeholders and no assets.
do {
    let url = samplesDir.appendingPathComponent("feature.docx")
    let plain = try await ConversionEngine.convert(fileAt: url, type: .docx)
    if plain.markdown.contains("distill-asset://") || !plain.assets.isEmpty {
        failures.append("extraction off but placeholders/assets present")
    }
}

// ===== v2 checks: snippet conversion (clipboard backend) =====
print("\n===== snippet conversion =====")
let snippetHTML = "<h2>Title</h2><p>Some <b>bold</b> text and a <a href=\"https://x.dev\">link</a>.</p>"
let snippetMD = ConversionEngine.markdown(fromHTML: snippetHTML)
print(snippetMD, terminator: "")
if !snippetMD.contains("## Title") || !snippetMD.contains("**bold**") || !snippetMD.contains("[link](https://x.dev)") {
    failures.append("markdown(fromHTML:) output wrong")
}
do {
    let rtfData = try Data(contentsOf: samplesDir.appendingPathComponent("sample.rtf"))
    let rtfMD = try ConversionEngine.markdown(fromRTF: rtfData)
    if !rtfMD.contains("**Annual Report**") || !rtfMD.contains("| Q1 | 10 |") {
        failures.append("markdown(fromRTF:) output wrong")
    }
    print("rtf snippet: \(rtfMD.count) chars OK")
} catch {
    failures.append("markdown(fromRTF:) threw: \(error.localizedDescription)")
}

// ===== v2 checks: multi-column PDF reading order =====
print("\n===== pdf columns =====")
do {
    let two = try await ConversionEngine.convert(
        fileAt: samplesDir.appendingPathComponent("twocol.pdf"), type: .pdf
    ).markdown
    func pos(_ needle: String, in text: String) -> Int {
        text.range(of: needle).map { text.distance(from: text.startIndex, to: $0.lowerBound) } ?? -1
    }
    let l8 = pos("LEFT-8", in: two), r1 = pos("RIGHT-1", in: two)
    let title = pos("TWO COLUMN TEST", in: two)
    print("twocol: title@\(title) LEFT-8@\(l8) RIGHT-1@\(r1)")
    if title != 0 { failures.append("twocol: title should lead the page") }
    if l8 < 0 || r1 < 0 || l8 > r1 { failures.append("twocol: left column must complete before right begins") }

    let one = try await ConversionEngine.convert(
        fileAt: samplesDir.appendingPathComponent("onecol.pdf"), type: .pdf
    ).markdown
    var lastIndex = -1
    for n in 1...8 {
        let p = pos("SINGLE-\(n)", in: one)
        if p < lastIndex { failures.append("onecol: SINGLE-\(n) out of order — reordering touched a single-column page") }
        lastIndex = p
    }
    print("onecol: sequence preserved")
} catch {
    failures.append("pdf columns: \(error.localizedDescription)")
}


// ===== v2.0.1 item 3: DOCX hyperlink display text is preserved =====
print("\n===== docx hyperlink text =====")
do {
    let md = try await ConversionEngine.convert(
        fileAt: samplesDir.appendingPathComponent("feature.docx"), type: .docx
    ).markdown
    if md.contains("[**the docs**](https://example.com/docs%28v2%29)") {
        print("anchor text preserved: [**the docs**](…)")
    } else {
        failures.append("docx hyperlink display text dropped or malformed")
    }
    if !md.contains("internal section.") || md.contains("[internal section]") {
        failures.append("docx internal anchor should stay plain text")
    }
} catch {
    failures.append("docx hyperlink check: \(error.localizedDescription)")
}

// ===== zip combined-document assertions =====
print("\n===== zip structure =====")
do {
    let md = try await ConversionEngine.convert(
        fileAt: samplesDir.appendingPathComponent("mixed.zip"), type: .zip
    ).markdown
    func pos(_ n: String) -> Int {
        md.range(of: n).map { md.distance(from: md.startIndex, to: $0.lowerBound) } ?? -1
    }
    let sections = ["# data/budget.csv", "# docs/note.txt", "# docs/report.html"]
    var last = -1
    for s in sections {
        let p = pos(s)
        if p < 0 { failures.append("mixed.zip: missing section \(s)") }
        if p < last { failures.append("mixed.zip: sections out of path order at \(s)") }
        last = p
    }
    if !md.contains("## Skipped") { failures.append("mixed.zip: no Skipped list") }
    if !md.contains("image.png (unsupported format)") { failures.append("mixed.zip: unsupported entry not listed") }
    if !md.contains("nested.zip (nested archive") { failures.append("mixed.zip: nested archive not noted") }
    if md.contains("DS_Store") || md.contains("__MACOSX") || md.contains(".hidden") {
        failures.append("mixed.zip: junk/hidden entries leaked into output")
    }
    if !md.contains("Zipped Report") || !md.contains("| pen | 2 |") {
        failures.append("mixed.zip: member content missing")
    }
    print("sections in order, skipped list present, junk excluded")
} catch {
    failures.append("mixed.zip structure: \(error.localizedDescription)")
}

print("\n=========================")

print(failures.isEmpty ? "ALL CONVERSIONS PASSED" : "FAILURES:\n" + failures.joined(separator: "\n"))
exit(failures.isEmpty ? 0 : 1)

