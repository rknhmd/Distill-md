//
//  HTMLConverter.swift
//  Distill
//
//  Converts HTML to semantic Markdown with a small, forgiving tag
//  scanner. Real-world HTML is rarely valid XML, so XMLParser is out;
//  NSAttributedString's HTML importer must run on the main thread and
//  flattens tables. A hand-rolled scanner keeps the conversion fully
//  off the main thread with zero dependencies, at the cost of ignoring
//  the (rare) constructs it doesn't know. Unknown tags are transparent:
//  their text content still flows into the output.
//

import Foundation

nonisolated struct HTMLConverter: MarkdownConverting {

    func convert(fileAt url: URL) throws -> ConversionResult {
        let html = try TextFileReader.read(url)
        let markdown = markdown(fromHTML: html)
        guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ConversionError.noConvertibleContent
        }
        return ConversionResult(markdown: markdown)
    }

    /// The parser, exposed for other converters: LegacyDocConverter turns
    /// .doc/.rtf into HTML (via textutil) and pipes it through here.
    func markdown(fromHTML html: String) -> String {
        var parser = HTMLToMarkdownParser(html: html)
        return parser.run()
    }
}

// MARK: - Parser

private nonisolated struct HTMLToMarkdownParser {

    init(html: String) {
        self.html = html
        self.index = html.startIndex
    }

    private let html: String
    private var index: String.Index

    /// The Markdown being built.
    private var out = ""

    // Context that changes how text is emitted:
    private enum ListKind { case unordered, ordered(nextNumber: Int) }
    private var listStack: [ListKind] = []
    private var quoteDepth = 0
    private var inPre = false

    /// href of each currently-open <a>; nil for anchors without one.
    private var openLinkHrefs: [String?] = []

    // Table buffering: cells are collected and the whole table is rendered
    // when </table> arrives (Markdown tables can't be streamed).
    private var inTable = false
    private var tableRows: [[String]] = []
    private var currentRow: [String]?
    private var currentCell: String?

    // MARK: Main loop

    mutating func run() -> String {
        while index < html.endIndex {
            if html[index] == "<" {
                handleAngleBracket()
            } else {
                let textEnd = html[index...].firstIndex(of: "<") ?? html.endIndex
                appendText(String(html[index..<textEnd]))
                index = textEnd
            }
        }
        flushDanglingTable()

        // Safety net: collapse any run of blank lines the tag handlers
        // produced, then normalize the edges.
        while out.contains("\n\n\n") {
            out = out.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "" : trimmed + "\n"
    }

    // MARK: Tag scanning

    private mutating func handleAngleBracket() {
        let rest = html[index...]

        // Comments and declarations (<!-- -->, <!DOCTYPE>, <?xml?>) are noise.
        if rest.hasPrefix("<!--") {
            skip(past: "-->", orAfter: "<!--")
            return
        }
        if rest.hasPrefix("<!") || rest.hasPrefix("<?") {
            skip(past: ">", orAfter: "<")
            return
        }

        // Find the true end of the tag, respecting quoted attribute values
        // (href="a>b" must not end the tag early).
        var cursor = html.index(after: index)
        var quote: Character? = nil
        var tagEnd: String.Index? = nil
        while cursor < html.endIndex {
            let ch = html[cursor]
            if let q = quote {
                if ch == q { quote = nil }
            } else if ch == "\"" || ch == "'" {
                quote = ch
            } else if ch == ">" {
                tagEnd = cursor
                break
            }
            cursor = html.index(after: cursor)
        }
        guard let end = tagEnd else {
            // No closing '>' anywhere — treat the '<' as literal text.
            appendText("<")
            index = html.index(after: index)
            return
        }

        var body = html[html.index(after: index)..<end]
        index = html.index(after: end)

        let isClosing = body.hasPrefix("/")
        if isClosing { body = body.dropFirst() }
        var selfClosing = false
        if body.hasSuffix("/") { selfClosing = true; body = body.dropLast() }

        // Tag name: letters/digits from the start.
        let nameEnd = body.firstIndex { !$0.isLetter && !$0.isNumber } ?? body.endIndex
        let name = body[..<nameEnd].lowercased()
        guard !name.isEmpty else {
            // "< 5 >" and friends aren't tags — reproduce them as text.
            appendText("<" + String(body) + ">")
            return
        }

        if isClosing {
            handleCloseTag(name)
        } else {
            let attributes = Self.parseAttributes(body[nameEnd...])
            handleOpenTag(name, attributes: attributes)
            if selfClosing { handleCloseTag(name) }
        }
    }

    /// Advances `index` past the first occurrence of `marker`, or to the end
    /// of input if it never appears. `orAfter` is how far to skip before
    /// searching, so we don't match the opener itself.
    private mutating func skip(past marker: String, orAfter opener: String) {
        let searchStart = html.index(index, offsetBy: opener.count, limitedBy: html.endIndex) ?? html.endIndex
        if let found = html.range(of: marker, options: .caseInsensitive, range: searchStart..<html.endIndex) {
            index = found.upperBound
        } else {
            index = html.endIndex
        }
    }

    /// Skips everything up to and including `</name ... >`. Used for tags
    /// whose *content* must be discarded (scripts, styles, …).
    private mutating func skipContentOfTag(_ name: String) {
        if let found = html.range(of: "</\(name)", options: .caseInsensitive, range: index..<html.endIndex) {
            index = found.upperBound
            // step past the closing '>'
            if let gt = html[index...].firstIndex(of: ">") {
                index = html.index(after: gt)
            } else {
                index = html.endIndex
            }
        } else {
            index = html.endIndex
        }
    }

    private static func parseAttributes(_ text: Substring) -> [String: String] {
        var attributes: [String: String] = [:]
        var cursor = text.startIndex

        func skipWhitespace() {
            while cursor < text.endIndex, text[cursor].isWhitespace {
                cursor = text.index(after: cursor)
            }
        }

        while cursor < text.endIndex {
            skipWhitespace()
            guard cursor < text.endIndex else { break }

            // Attribute name
            let nameStart = cursor
            while cursor < text.endIndex, !text[cursor].isWhitespace, text[cursor] != "=" {
                cursor = text.index(after: cursor)
            }
            let name = text[nameStart..<cursor].lowercased()
            guard !name.isEmpty else { break }

            skipWhitespace()
            var value = ""
            if cursor < text.endIndex, text[cursor] == "=" {
                cursor = text.index(after: cursor)
                skipWhitespace()
                if cursor < text.endIndex, text[cursor] == "\"" || text[cursor] == "'" {
                    let quote = text[cursor]
                    cursor = text.index(after: cursor)
                    let valueStart = cursor
                    while cursor < text.endIndex, text[cursor] != quote {
                        cursor = text.index(after: cursor)
                    }
                    value = String(text[valueStart..<cursor])
                    if cursor < text.endIndex { cursor = text.index(after: cursor) }
                } else {
                    let valueStart = cursor
                    while cursor < text.endIndex, !text[cursor].isWhitespace {
                        cursor = text.index(after: cursor)
                    }
                    value = String(text[valueStart..<cursor])
                }
            }
            attributes[name] = value
        }
        return attributes
    }

    // MARK: Tag semantics

    private mutating func handleOpenTag(_ name: String, attributes: [String: String]) {
        switch name {
        case "script", "style", "head", "title", "noscript", "template", "svg", "iframe":
            skipContentOfTag(name)

        case "h1", "h2", "h3", "h4", "h5", "h6":
            guard currentCell == nil else { softBreakInCell(); return }
            ensureBlankLine()
            let level = Int(String(name.dropFirst())) ?? 1
            write(String(repeating: "#", count: level) + " ")

        case "p", "div", "section", "article", "main", "aside", "header",
             "footer", "figure", "form", "nav", "address", "details", "summary":
            guard currentCell == nil else { softBreakInCell(); return }
            ensureBlankLine()

        case "br":
            if currentCell != nil { write("<br>") } else { newline() }

        case "hr":
            guard currentCell == nil else { return }
            ensureBlankLine()
            write("---")
            ensureBlankLine()

        case "strong", "b": write("**")
        case "em", "i": write("*")

        case "code":
            if !inPre { write("`") }

        case "pre":
            guard currentCell == nil else { softBreakInCell(); return }
            ensureBlankLine()
            write("```\n")
            inPre = true

        case "a":
            // Treat a missing *or empty* href the same way, so the "["
            // written here is always balanced by "](…)" at the close tag.
            let href = attributes["href"].flatMap { $0.isEmpty ? nil : $0 }
            openLinkHrefs.append(href)
            if href != nil { write("[") }

        case "img":
            let alt = attributes["alt"] ?? ""
            if let src = attributes["src"], !src.isEmpty {
                write("![\(alt)](\(src))")
            } else if !alt.isEmpty {
                write(alt)
            }

        case "ul":
            listStack.append(.unordered)
        case "ol":
            listStack.append(.ordered(nextNumber: 1))
        case "li":
            guard currentCell == nil else { softBreakInCell(); return }
            startListItem()

        case "blockquote":
            guard currentCell == nil else { softBreakInCell(); return }
            ensureBlankLine()
            quoteDepth += 1
            // The "> " prefix is NOT written here — `write` adds it lazily
            // when real content starts a line, so tag boundaries with no
            // text between them don't leave stray "> " lines behind.

        case "table":
            guard !inTable else { return }   // nested tables: let text flow
            inTable = true
            tableRows = []
        case "tr":
            if inTable { currentRow = [] }
        case "th", "td":
            if inTable, currentRow != nil { currentCell = "" }

        default:
            break   // unknown tag: transparent, its text still flows
        }
    }

    private mutating func handleCloseTag(_ name: String) {
        switch name {
        case "h1", "h2", "h3", "h4", "h5", "h6":
            if currentCell == nil { ensureBlankLine() }

        case "p", "div", "section", "article", "main", "aside", "header",
             "footer", "figure", "form", "nav", "address", "details", "summary":
            if currentCell == nil { ensureBlankLine() }

        case "strong", "b": write("**")
        case "em", "i": write("*")

        case "code":
            if !inPre { write("`") }

        case "pre":
            guard inPre else { return }
            inPre = false
            if !out.hasSuffix("\n") { write("\n") }
            write("```")
            ensureBlankLine()

        case "a":
            // Double optional: outer nil = stray </a> with no opener,
            // inner nil = the anchor had no usable href. Write nothing
            // in either case.
            if let href = openLinkHrefs.popLast(), let href {
                write("](\(href))")
            }

        case "ul", "ol":
            if !listStack.isEmpty { listStack.removeLast() }
            if listStack.isEmpty, currentCell == nil { ensureBlankLine() }

        case "blockquote":
            quoteDepth = max(0, quoteDepth - 1)
            if currentCell == nil { ensureBlankLine() }

        case "th", "td":
            if let cell = currentCell {
                currentRow?.append(cell.trimmingCharacters(in: .whitespacesAndNewlines))
                currentCell = nil
            }
        case "tr":
            if let row = currentRow {
                if !row.isEmpty { tableRows.append(row) }
                currentRow = nil
            }
        case "table":
            endTable()

        default:
            break
        }
    }

    // MARK: Lists

    private mutating func startListItem() {
        if !out.isEmpty && !out.hasSuffix("\n") { newline() }
        let depth = max(0, listStack.count - 1)
        let indent = String(repeating: "  ", count: depth)
        switch listStack.last {
        case .ordered(let number):
            write("\(indent)\(number). ")
            listStack[listStack.count - 1] = .ordered(nextNumber: number + 1)
        default:
            // .unordered, or a stray <li> outside any list
            write("\(indent)- ")
        }
    }

    // MARK: Tables

    private mutating func endTable() {
        guard inTable else { return }
        inTable = false
        // Flush a row the HTML forgot to close.
        if let cell = currentCell { currentRow?.append(cell); currentCell = nil }
        if let row = currentRow, !row.isEmpty { tableRows.append(row); currentRow = nil }
        currentRow = nil

        guard !tableRows.isEmpty else { return }
        ensureBlankLine()
        // CSVConverter already knows how to render rows-of-cells as a
        // Markdown table (padding, pipe-escaping) — reuse it.
        write(CSVConverter.markdownTable(from: tableRows))
        tableRows = []
        ensureBlankLine()
    }

    /// If the input ended mid-table, still render what was collected.
    private mutating func flushDanglingTable() {
        if inTable { endTable() }
    }

    // MARK: Text emission

    private mutating func appendText(_ raw: String) {
        let decoded = Self.decodeEntities(raw)

        if inPre {
            write(decoded)
            return
        }
        // Text floating between table tags (indentation between <tr>s, …)
        // belongs to no cell; emitting it would corrupt the layout.
        if inTable && currentCell == nil { return }

        var text = Self.collapseWhitespace(decoded)
        guard !text.isEmpty else { return }

        // Drop a leading space when the destination already ends in
        // whitespace (or a fresh line) — HTML source formatting, not content.
        if text.hasPrefix(" ") {
            let target = currentCell ?? out
            if target.isEmpty || target.hasSuffix(" ") || target.hasSuffix("\n") {
                text.removeFirst()
            }
        }
        guard !text.isEmpty else { return }
        write(text)
    }

    /// HTML collapses whitespace runs into a single space; do the same,
    /// preserving whether the chunk touched its neighbors.
    private static func collapseWhitespace(_ text: String) -> String {
        let words = text.split(whereSeparator: \.isWhitespace)
        if words.isEmpty {
            return text.isEmpty ? "" : " "
        }
        var result = words.joined(separator: " ")
        if let first = text.first, first.isWhitespace { result = " " + result }
        if let last = text.last, last.isWhitespace { result += " " }
        return result
    }

    // MARK: Entities

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
        "nbsp": " ", "ndash": "–", "mdash": "—", "hellip": "…",
        "lsquo": "\u{2018}", "rsquo": "\u{2019}",
        "ldquo": "\u{201C}", "rdquo": "\u{201D}",
        "laquo": "«", "raquo": "»", "middot": "·", "bull": "•",
        "copy": "©", "reg": "®", "trade": "™", "deg": "°",
        "times": "×", "divide": "÷", "minus": "−", "plusmn": "±",
        "frac12": "½", "frac14": "¼", "frac34": "¾",
        "sup2": "²", "sup3": "³", "micro": "µ",
        "euro": "€", "pound": "£", "yen": "¥", "cent": "¢", "sect": "§",
    ]

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = ""
        result.reserveCapacity(text.count)
        var cursor = text.startIndex

        while cursor < text.endIndex {
            let ch = text[cursor]
            guard ch == "&" else {
                result.append(ch)
                cursor = text.index(after: cursor)
                continue
            }
            // An entity is '&' + up to ~10 chars + ';'
            let searchEnd = text.index(cursor, offsetBy: 12, limitedBy: text.endIndex) ?? text.endIndex
            guard let semicolon = text[cursor..<searchEnd].firstIndex(of: ";") else {
                result.append(ch)
                cursor = text.index(after: cursor)
                continue
            }
            let body = String(text[text.index(after: cursor)..<semicolon])
            var replacement: String? = nil

            if body.hasPrefix("#x") || body.hasPrefix("#X") {
                if let code = UInt32(body.dropFirst(2), radix: 16), let scalar = Unicode.Scalar(code) {
                    replacement = String(Character(scalar))
                }
            } else if body.hasPrefix("#") {
                if let code = UInt32(body.dropFirst()), let scalar = Unicode.Scalar(code) {
                    replacement = String(Character(scalar))
                }
            } else {
                replacement = namedEntities[body]
            }

            if let replacement {
                result.append(replacement)
                cursor = text.index(after: semicolon)
            } else {
                result.append(ch)   // unknown entity: keep the '&' literally
                cursor = text.index(after: cursor)
            }
        }
        return result
    }

    // MARK: Output plumbing

    /// Everything funnels through here so content lands in the open table
    /// cell when there is one, and in the document otherwise. Inside a
    /// blockquote, a "> " prefix is inserted whenever content begins a
    /// fresh line.
    private mutating func write(_ text: String) {
        if currentCell != nil {
            currentCell! += text
            return
        }
        if quoteDepth > 0,
           out.hasSuffix("\n") || out.isEmpty,
           !text.hasPrefix("\n"), !text.isEmpty {
            out += quotePrefix()
        }
        out += text
    }

    /// Block-level tags encountered *inside* a table cell degrade to a
    /// single space (Markdown cells are one line).
    private mutating func softBreakInCell() {
        if let cell = currentCell, !cell.isEmpty, !cell.hasSuffix(" ") {
            currentCell! += " "
        }
    }

    private func quotePrefix() -> String {
        String(repeating: "> ", count: quoteDepth)
    }

    /// Starts a fresh line. Trims the trailing space that inter-tag
    /// whitespace tends to leave behind — a stray trailing space is at
    /// best noise and at worst a Markdown hard line break.
    private mutating func newline() {
        while out.hasSuffix(" ") || out.hasSuffix("\t") {
            out.removeLast()
        }
        out += "\n"     // deliberately bypasses write() — no quote prefix on empty lines
    }

    /// Ensures the document output ends with exactly one blank line —
    /// the separator between Markdown blocks. No-op at the very start.
    private mutating func ensureBlankLine() {
        while out.hasSuffix(" ") || out.hasSuffix("\t") {
            out.removeLast()
        }
        guard !out.isEmpty else { return }
        if !out.hasSuffix("\n") { out += "\n" }
        if !out.hasSuffix("\n\n") { out += "\n" }
    }
}
