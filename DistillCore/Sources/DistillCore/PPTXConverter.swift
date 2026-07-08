//
//  PPTXConverter.swift
//  Distill
//
//  Converts PowerPoint decks: one Markdown section per slide, with the
//  slide title as a heading, body text as bullets, tables as Markdown
//  tables (in their slide position), and speaker notes appended.
//
//  Inside the .pptx ZIP:
//    ppt/slides/slideN.xml           the slides themselves
//    ppt/notesSlides/notesSlideN.xml speaker notes (same N by convention)
//  Text lives in shapes (<p:sp>). A shape's placeholder (<p:ph type=…>)
//  says what it is — title, body, slide number… Paragraphs are <a:p>,
//  runs <a:r>, text <a:t>, indent level is <a:pPr lvl="…">.
//  Tables live outside shapes, in <p:graphicFrame> → <a:tbl>, with rows
//  <a:tr> and cells <a:tc>.
//

import Foundation

nonisolated struct PPTXConverter: MarkdownConverting {

    func convert(fileAt url: URL, options: ConversionOptions) throws -> ConversionResult {
        let archive = try OOXMLArchive(url: url)

        let slidePaths = archive
            .paths(withPrefix: "ppt/slides/slide", suffix: ".xml")
            .sorted { Self.slideNumber(in: $0) < Self.slideNumber(in: $1) }
        guard !slidePaths.isEmpty else {
            throw ConversionError.noConvertibleContent
        }

        let collector = options.extractImages ? AssetCollector() : nil

        var sections: [String] = []
        for path in slidePaths {
            let number = Self.slideNumber(in: path)
            guard let slideData = archive.dataIfPresent(at: path) else { continue }

            // Each slide has its own rels file; image targets look like
            // "../media/image1.png" relative to ppt/slides/.
            var resolveImage: ((String) -> String?)?
            if let collector {
                let relsPath = "ppt/slides/_rels/\(URL(fileURLWithPath: path).lastPathComponent).rels"
                let targets = archive.dataIfPresent(at: relsPath)
                    .map { RelationshipsWalker.parseTargets($0, externalOnly: false) } ?? [:]
                resolveImage = { relId in
                    guard let target = targets[relId] else { return nil }
                    let normalized = target.replacingOccurrences(of: "../", with: "ppt/")
                    guard let data = archive.dataIfPresent(at: normalized), !data.isEmpty else { return nil }
                    let ext = (normalized as NSString).pathExtension.lowercased()
                    return collector.register(data: data, preferredExtension: ext.isEmpty ? "bin" : ext)
                }
            }

            guard let slide = ShapeTextWalker.parse(slideData, resolveImage: resolveImage) else { continue }

            // Speaker notes: PowerPoint, Keynote, and python-pptx all keep
            // notesSlideN.xml aligned with slideN.xml.
            let notes = archive
                .dataIfPresent(at: "ppt/notesSlides/notesSlide\(number).xml")
                .flatMap { ShapeTextWalker.parse($0) }

            sections.append(Self.renderSlide(number: number, slide: slide, notes: notes))
        }

        let markdown = sections.joined(separator: "\n\n")
        guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ConversionError.noConvertibleContent
        }
        return ConversionResult(
            markdown: markdown + "\n",
            unitCount: slidePaths.count,
            unitLabel: "slides",
            assets: collector?.assets ?? []
        )
    }

    private static func renderSlide(
        number: Int,
        slide: ShapeTextWalker.Result,
        notes: ShapeTextWalker.Result?
    ) -> String {
        var lines: [String] = []

        if let title = slide.title, !title.isEmpty {
            lines.append("## Slide \(number): \(title)")
        } else {
            lines.append("## Slide \(number)")
        }

        var previousWasTable = false
        for (index, block) in slide.content.enumerated() {
            switch block {
            case .paragraph(let text, let level):
                if index == 0 || previousWasTable { lines.append("") }
                let indent = String(repeating: "  ", count: level)
                lines.append("\(indent)- \(text)")
                previousWasTable = false

            case .table(let rows):
                lines.append("")
                var table = CSVConverter.markdownTable(from: rows)
                while table.hasSuffix("\n") { table.removeLast() }
                lines.append(table)
                previousWasTable = true

            case .image(let assetName):
                lines.append("")
                lines.append(AssetCollector.placeholderLink(for: assetName))
                previousWasTable = true   // same spacing behavior: blank line after
            }
        }

        // Notes come out of the same walker; their "body" is the prose.
        if let notes {
            let noteLines: [String] = notes.content.compactMap {
                if case .paragraph(let text, _) = $0, !text.isEmpty { return text }
                return nil
            }
            if !noteLines.isEmpty {
                lines.append("")
                lines.append("**Speaker notes:** " + noteLines.joined(separator: " "))
            }
        }

        return lines.joined(separator: "\n")
    }

    /// "ppt/slides/slide12.xml" → 12
    private static func slideNumber(in path: String) -> Int {
        let name = (path as NSString).lastPathComponent
        let digits = name.drop { !$0.isNumber }.prefix { $0.isNumber }
        return Int(digits) ?? 0
    }
}

// MARK: - Shape & table text walker

/// SAX walker shared by slides and notes slides. Collects slide content
/// in document order: paragraphs from placeholder shapes, and tables
/// from graphic frames. The title placeholder is pulled out separately.
private nonisolated final class ShapeTextWalker: NSObject, XMLParserDelegate {

    enum SlideContent {
        case paragraph(text: String, level: Int)
        case table(rows: [[String]])
        case image(assetName: String)
    }

    struct Result {
        var title: String?
        var content: [SlideContent] = []
    }

    static func parse(_ data: Data, resolveImage: ((String) -> String?)? = nil) -> Result? {
        let walker = ShapeTextWalker()
        walker.resolveImage = resolveImage
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = walker
        guard parser.parse() else { return nil }
        return walker.result
    }

    /// r:embed id → registered asset name; nil when extraction is off.
    var resolveImage: ((String) -> String?)?

    private var result = Result()

    // Placeholder types whose text is chrome, not content.
    private static let skippedPlaceholders: Set<String> = ["sldNum", "dt", "ftr", "hdr", "sldImg"]
    private static let titlePlaceholders: Set<String> = ["title", "ctrTitle"]

    // Per-shape state
    private var inShape = false
    private var placeholderType: String?
    private var shapeParagraphs: [(text: String, level: Int)] = []

    // Per-paragraph state (shared by shapes and table cells)
    private var inParagraph = false
    private var paragraphText = ""
    private var paragraphLevel = 0
    private var capturingText = false

    // Table state. Continuation cells of merges (hMerge/vMerge) are
    // present in the XML as empty markers — they become empty Markdown
    // cells, which keeps the grid rectangular. (Documented choice:
    // merged values are NOT repeated.)
    private var tableDepth = 0
    private var tableRows: [[String]] = []
    private var currentRowCells: [String] = []
    private var inTableCell = false
    private var currentCellParagraphs: [String] = []
    private var cellIsMergeContinuation = false

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch elementName {
        case "sp":
            inShape = true
            placeholderType = nil
            shapeParagraphs = []
        case "ph" where inShape:
            placeholderType = attributeDict["type"]

        case "tbl":
            tableDepth += 1
            if tableDepth == 1 { tableRows = [] }
        case "tr" where tableDepth == 1:
            currentRowCells = []
        case "tc" where tableDepth == 1:
            inTableCell = true
            currentCellParagraphs = []
            // hMerge/vMerge mark cells covered by a merge to their left /
            // above. Present-and-not-false means "this is a continuation".
            let hMerge = attributeDict["hMerge"], vMerge = attributeDict["vMerge"]
            func isSet(_ value: String?) -> Bool {
                guard let value else { return false }
                return value != "0" && value.lowercased() != "false"
            }
            cellIsMergeContinuation = isSet(hMerge) || isSet(vMerge)

        case "blip":
            // <a:blip r:embed="rId4"/> inside a p:pic — a slide image, at
            // this point in document order.
            if let resolveImage,
               let relId = attributeDict["r:embed"] ?? attributeDict["embed"],
               let assetName = resolveImage(relId) {
                result.content.append(.image(assetName: assetName))
            }

        case "p" where inShape || inTableCell:
            inParagraph = true
            paragraphText = ""
            paragraphLevel = 0
        case "pPr" where inParagraph:
            paragraphLevel = attributeDict["lvl"].flatMap(Int.init) ?? 0
        case "t" where inParagraph:
            capturingText = true
        case "br" where inParagraph:
            paragraphText += " "

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capturingText {
            paragraphText += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch elementName {
        case "t":
            capturingText = false

        case "p" where inParagraph:
            inParagraph = false
            let text = paragraphText.trimmingCharacters(in: .whitespacesAndNewlines)
            if inTableCell {
                if !text.isEmpty { currentCellParagraphs.append(text) }
            } else if !text.isEmpty {
                shapeParagraphs.append((text: text, level: paragraphLevel))
            }

        case "tc" where tableDepth == 1:
            inTableCell = false
            currentRowCells.append(
                cellIsMergeContinuation ? "" : currentCellParagraphs.joined(separator: " ")
            )
        case "tr" where tableDepth == 1:
            if !currentRowCells.isEmpty { tableRows.append(currentRowCells) }
        case "tbl":
            if tableDepth == 1, !tableRows.isEmpty {
                result.content.append(.table(rows: tableRows))
                tableRows = []
            }
            tableDepth = max(0, tableDepth - 1)

        case "sp":
            finishShape()
            inShape = false

        default:
            break
        }
    }

    private func finishShape() {
        guard !shapeParagraphs.isEmpty else { return }
        let type = placeholderType ?? ""

        if Self.skippedPlaceholders.contains(type) {
            return
        }
        if Self.titlePlaceholders.contains(type) {
            let title = shapeParagraphs.map(\.text).joined(separator: " ")
            // First title shape wins; extras (unusual) fall through to body.
            if result.title == nil {
                result.title = title
                return
            }
        }
        for paragraph in shapeParagraphs {
            result.content.append(.paragraph(text: paragraph.text, level: paragraph.level))
        }
    }
}
