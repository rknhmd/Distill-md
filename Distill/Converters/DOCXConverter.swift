//
//  DOCXConverter.swift
//  Distill
//
//  Converts Word documents by parsing their OOXML directly:
//  unzip (ZIPFoundation) → walk word/document.xml with Foundation's
//  XMLParser (SAX-style: we get callbacks per tag and collect state).
//
//  The parts of WordprocessingML we care about:
//    <w:p>  paragraph      <w:pPr>  its properties
//      <w:pStyle w:val="Heading1"/>        → "# "
//      <w:numPr><w:ilvl/><w:numId/>        → list item
//    <w:r>  text run       <w:rPr><w:b/><w:i/>  → **bold** / *italic*
//      <w:t>the actual text</w:t>
//    <w:tbl><w:tr><w:tc>   tables
//  word/numbering.xml maps numId+level → bullet vs numbered.
//

import Foundation

nonisolated struct DOCXConverter: MarkdownConverting {

    func convert(fileAt url: URL) throws -> String {
        let archive = try OOXMLArchive(url: url)
        let documentXML = try archive.data(at: "word/document.xml")

        // Optional part: without it every list falls back to bullets.
        let numbering = archive.dataIfPresent(at: "word/numbering.xml")
            .map { NumberingWalker.parse($0) } ?? [:]

        let walker = DocumentWalker(numbering: numbering)
        let parser = XMLParser(data: documentXML)
        parser.shouldProcessNamespaces = true   // match local names, any prefix
        parser.delegate = walker
        guard parser.parse() else {
            throw ConversionError.corruptDocument
        }

        let markdown = walker.assembledMarkdown()
        guard !markdown.isEmpty else {
            throw ConversionError.noConvertibleContent
        }
        return markdown + "\n"
    }
}

// MARK: - word/document.xml walker

/// `nonisolated`: XMLParser calls the delegate synchronously on whatever
/// thread parse() runs on — our background conversion thread — so this
/// class must not be MainActor-isolated.
private nonisolated final class DocumentWalker: NSObject, XMLParserDelegate {

    init(numbering: [String: [Int: Bool]]) {
        self.numbering = numbering
    }

    /// numId → (indent level → is-ordered), from numbering.xml.
    private let numbering: [String: [Int: Bool]]

    /// What a finished block is, which decides the spacing between blocks:
    /// consecutive list items of the *same* kind stay tight (single
    /// newline); everything else is separated by a blank line — including
    /// a bullet list meeting an ordered list, which Markdown would
    /// otherwise fuse into one confused list.
    private enum BlockKind: Equatable {
        case regular, bulletItem, orderedItem
    }

    private var blocks: [(text: String, kind: BlockKind)] = []

    // Run accumulation. Adjacent runs with identical formatting merge, so
    // Word's habit of splitting sentences into many runs doesn't produce
    // "**bo****ld**" garbage.
    private struct Run {
        var text = ""
        var bold = false
        var italic = false
    }

    // Paragraph state
    private var currentRuns: [Run] = []
    private var paragraphStyle: String?
    private var listNumId: String?
    private var listLevel = 0
    private var inParagraphProperties = false

    // Run state
    private var inRun = false
    private var inRunProperties = false
    private var currentRun = Run()
    private var capturingText = false

    // Table state (depth guards against nested tables: inner ones lose
    // their structure but keep their text)
    private var tableDepth = 0
    private var tableRows: [[String]] = []
    private var currentRowCells: [String] = []
    private var currentCellParagraphs: [String] = []
    private var inCell = false

    // MARK: Element callbacks

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch elementName {
        case "p":
            currentRuns = []
            paragraphStyle = nil
            listNumId = nil
            listLevel = 0

        case "pPr":
            inParagraphProperties = true
        case "pStyle" where inParagraphProperties:
            paragraphStyle = value(in: attributeDict)
        case "numId" where inParagraphProperties:
            listNumId = value(in: attributeDict)
        case "ilvl" where inParagraphProperties:
            listLevel = value(in: attributeDict).flatMap(Int.init) ?? 0

        case "r":
            inRun = true
            currentRun = Run()
        case "rPr" where inRun:
            inRunProperties = true
        case "b" where inRunProperties:
            currentRun.bold = flagValue(in: attributeDict)
        case "i" where inRunProperties:
            currentRun.italic = flagValue(in: attributeDict)

        case "t" where inRun:
            capturingText = true
        case "br", "cr":
            if inRun { currentRun.text += "\n" }
        case "tab":
            if inRun { currentRun.text += " " }

        case "tbl":
            tableDepth += 1
            if tableDepth == 1 { tableRows = [] }
        case "tr" where tableDepth == 1:
            currentRowCells = []
        case "tc" where tableDepth == 1:
            inCell = true
            currentCellParagraphs = []

        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch elementName {
        case "pPr":
            inParagraphProperties = false
        case "t":
            capturingText = false
        case "rPr":
            inRunProperties = false
        case "r":
            if !currentRun.text.isEmpty { currentRuns.append(currentRun) }
            inRun = false
        case "p":
            finishParagraph()

        case "tc" where tableDepth == 1:
            inCell = false
            currentRowCells.append(currentCellParagraphs.joined(separator: "<br>"))
        case "tr" where tableDepth == 1:
            if !currentRowCells.isEmpty { tableRows.append(currentRowCells) }
        case "tbl":
            if tableDepth == 1, !tableRows.isEmpty {
                blocks.append((CSVConverter.markdownTable(from: tableRows), .regular))
            }
            tableDepth = max(0, tableDepth - 1)

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capturingText {
            currentRun.text += string
        }
    }

    // MARK: Paragraph assembly

    private func finishParagraph() {
        let text = Self.mergeRuns(currentRuns)
        currentRuns = []
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        // Paragraphs inside a table cell belong to the cell, not the body.
        if inCell {
            currentCellParagraphs.append(text)
            return
        }

        // Headings, by paragraph style.
        if let style = paragraphStyle {
            let lower = style.lowercased()
            if lower.hasPrefix("heading"),
               let level = Int(lower.dropFirst("heading".count)),
               (1...6).contains(level) {
                blocks.append((String(repeating: "#", count: level) + " " + text, .regular))
                return
            }
            if lower == "title" {
                blocks.append(("# " + text, .regular))
                return
            }
            if lower == "subtitle" {
                blocks.append(("## " + text, .regular))
                return
            }
        }

        // List items, by numbering reference.
        if let numId = listNumId {
            let isOrdered = numbering[numId]?[listLevel] ?? false
            let indent = String(repeating: "  ", count: listLevel)
            // "1." for every ordered item is fine: Markdown renderers
            // renumber sequences automatically.
            let marker = isOrdered ? "1." : "-"
            blocks.append(("\(indent)\(marker) \(text)", isOrdered ? .orderedItem : .bulletItem))
            return
        }

        blocks.append((text, .regular))
    }

    /// Merges adjacent same-format runs, then wraps each surviving run in
    /// its Markdown markers — keeping whitespace *outside* the markers
    /// ("** bold**" doesn't parse; " **bold**" does).
    private static func mergeRuns(_ runs: [Run]) -> String {
        var merged: [Run] = []
        for run in runs {
            if let last = merged.last, last.bold == run.bold, last.italic == run.italic {
                merged[merged.count - 1].text += run.text
            } else {
                merged.append(run)
            }
        }

        return merged.map { run in
            let core = run.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !core.isEmpty, run.bold || run.italic else { return run.text }

            var marker = ""
            if run.bold { marker += "**" }
            if run.italic { marker += "*" }

            let leading = run.text.prefix { $0.isWhitespace }
            let trailing = run.text.reversed().prefix { $0.isWhitespace }.reversed()
            return "\(leading)\(marker)\(core)\(String(marker.reversed()))\(String(trailing))"
        }.joined()
    }

    func assembledMarkdown() -> String {
        var parts: [String] = []
        var previousKind = BlockKind.regular
        for block in blocks {
            // Blocks that end in their own newline (tables) would double up
            // with the joiner below — normalize the edge first.
            var text = block.text
            while text.hasSuffix("\n") { text.removeLast() }

            if !parts.isEmpty {
                let sameListContinues = block.kind != .regular && block.kind == previousKind
                parts.append(sameListContinues ? "\n" : "\n\n")
            }
            parts.append(text)
            previousKind = block.kind
        }
        return parts.joined()
    }

    // MARK: Attribute helpers

    /// OOXML values live in the `w:val` attribute; with namespace
    /// processing on, some producers surface it as plain "val".
    private func value(in attributes: [String: String]) -> String? {
        attributes["w:val"] ?? attributes["val"]
    }

    /// <w:b/> means on; <w:b w:val="false"/> (or "0"/"none") means off.
    private func flagValue(in attributes: [String: String]) -> Bool {
        guard let raw = value(in: attributes)?.lowercased() else { return true }
        return !(raw == "false" || raw == "0" || raw == "none")
    }
}

// MARK: - word/numbering.xml walker

/// Extracts numId → (level → ordered?) so list paragraphs can pick "-"
/// vs "1.". Two structures matter: <w:abstractNum> defines formats per
/// level; <w:num> maps the IDs paragraphs actually reference onto them.
private nonisolated final class NumberingWalker: NSObject, XMLParserDelegate {

    static func parse(_ data: Data) -> [String: [Int: Bool]] {
        let walker = NumberingWalker()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = walker
        guard parser.parse() else { return [:] }

        // Join the two maps: numId → abstractNumId → formats.
        var result: [String: [Int: Bool]] = [:]
        for (numId, abstractId) in walker.numToAbstract {
            result[numId] = walker.abstractFormats[abstractId]
        }
        return result
    }

    private var abstractFormats: [String: [Int: Bool]] = [:]
    private var numToAbstract: [String: String] = [:]

    private var currentAbstractId: String?
    private var currentLevel: Int?
    private var currentNumId: String?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let value = attributeDict["w:val"] ?? attributeDict["val"]
        switch elementName {
        case "abstractNum":
            currentAbstractId = attributeDict["w:abstractNumId"] ?? attributeDict["abstractNumId"]
        case "lvl":
            currentLevel = (attributeDict["w:ilvl"] ?? attributeDict["ilvl"]).flatMap(Int.init)
        case "numFmt":
            if let abstractId = currentAbstractId, let level = currentLevel, let value {
                let ordered = value != "bullet" && value != "none"
                abstractFormats[abstractId, default: [:]][level] = ordered
            }
        case "num":
            currentNumId = attributeDict["w:numId"] ?? attributeDict["numId"]
        case "abstractNumId":
            if let numId = currentNumId, let value {
                numToAbstract[numId] = value
            }
        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch elementName {
        case "abstractNum": currentAbstractId = nil
        case "lvl": currentLevel = nil
        case "num": currentNumId = nil
        default: break
        }
    }
}
