//
//  PPTXConverter.swift
//  Distill
//
//  Converts PowerPoint decks: one Markdown section per slide, with the
//  slide title as a heading, body text as bullets, and speaker notes
//  appended underneath.
//
//  Inside the .pptx ZIP:
//    ppt/slides/slideN.xml           the slides themselves
//    ppt/notesSlides/notesSlideN.xml speaker notes (same N by convention)
//  Text lives in shapes (<p:sp>). A shape's placeholder (<p:ph type=…>)
//  says what it is — title, body, slide number… Paragraphs are <a:p>,
//  runs <a:r>, text <a:t>, indent level is <a:pPr lvl="…">.
//

import Foundation

nonisolated struct PPTXConverter: MarkdownConverting {

    func convert(fileAt url: URL) throws -> String {
        let archive = try OOXMLArchive(url: url)

        let slidePaths = archive
            .paths(withPrefix: "ppt/slides/slide", suffix: ".xml")
            .sorted { Self.slideNumber(in: $0) < Self.slideNumber(in: $1) }
        guard !slidePaths.isEmpty else {
            throw ConversionError.noConvertibleContent
        }

        var sections: [String] = []
        for path in slidePaths {
            let number = Self.slideNumber(in: path)
            guard let slideData = archive.dataIfPresent(at: path),
                  let slide = ShapeTextWalker.parse(slideData) else { continue }

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
        return markdown + "\n"
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

        if !slide.bodyParagraphs.isEmpty {
            lines.append("")
            for paragraph in slide.bodyParagraphs {
                let indent = String(repeating: "  ", count: paragraph.level)
                lines.append("\(indent)- \(paragraph.text)")
            }
        }

        // Notes come out of the same walker; their "body" is the prose.
        if let notes {
            let noteLines = notes.bodyParagraphs.map(\.text).filter { !$0.isEmpty }
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

// MARK: - Shape text walker

/// SAX walker shared by slides and notes slides: collects, per shape,
/// the placeholder type and the paragraphs of text inside it, then sorts
/// shapes into "title" and "body".
private nonisolated final class ShapeTextWalker: NSObject, XMLParserDelegate {

    struct Paragraph {
        let text: String
        let level: Int
    }

    struct Result {
        var title: String?
        var bodyParagraphs: [Paragraph] = []
    }

    static func parse(_ data: Data) -> Result? {
        let walker = ShapeTextWalker()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = walker
        guard parser.parse() else { return nil }
        return walker.result
    }

    private var result = Result()

    // Placeholder types whose text is chrome, not content.
    private static let skippedPlaceholders: Set<String> = ["sldNum", "dt", "ftr", "hdr", "sldImg"]
    private static let titlePlaceholders: Set<String> = ["title", "ctrTitle"]

    // Per-shape state
    private var inShape = false
    private var placeholderType: String?
    private var shapeParagraphs: [Paragraph] = []

    // Per-paragraph state
    private var inParagraph = false
    private var paragraphText = ""
    private var paragraphLevel = 0
    private var capturingText = false

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

        case "p" where inShape:
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
            if !text.isEmpty {
                shapeParagraphs.append(Paragraph(text: text, level: paragraphLevel))
            }
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
        result.bodyParagraphs.append(contentsOf: shapeParagraphs)
    }
}
