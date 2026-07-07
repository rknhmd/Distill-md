//
//  RenderedMarkdownView.swift
//  Distill
//
//  A native rendered view of Markdown, built from two halves:
//   1. a small line-based parser that splits the document into blocks
//      (headings, paragraphs, lists, code fences, tables, quotes), and
//   2. SwiftUI views per block, with AttributedString(markdown:) doing
//      the inline work (bold/italic/code/links).
//
//  Apple's AttributedString handles inline Markdown well but flattens
//  block structure, which is why the block splitting is ours.
//

import SwiftUI

struct RenderedMarkdownView: View {
    let markdown: String

    @State private var blocks: [MarkdownBlock] = []

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(blocks) { block in
                    view(for: block)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .textSelection(.enabled)
        .background(.background)
        // Re-parse only when the document changes, not on every redraw.
        .task(id: markdown) {
            blocks = MarkdownBlock.parse(markdown)
        }
    }

    // MARK: Per-block rendering

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block.kind {
        case .heading(let level, let text):
            Text(inline(text))
                .font(headingFont(level))
                .padding(.top, level <= 2 ? 8 : 4)

        case .paragraph(let text):
            Text(inline(text))

        case .codeBlock(let code):
            ScrollView(.horizontal) {
                Text(code)
                    .font(.system(.callout, design: .monospaced))
                    .padding(10)
            }
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))

        case .bulletItem(let indent, let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•").foregroundStyle(.secondary)
                Text(inline(text))
            }
            .padding(.leading, CGFloat(indent) * 18)

        case .orderedItem(let indent, let number, let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(number).").foregroundStyle(.secondary).monospacedDigit()
                Text(inline(text))
            }
            .padding(.leading, CGFloat(indent) * 18)

        case .blockquote(let text):
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(.tint)
                    .frame(width: 3)
                Text(inline(text)).foregroundStyle(.secondary)
            }

        case .table(let rows):
            tableView(rows)

        case .horizontalRule:
            Divider().padding(.vertical, 4)
        }
    }

    private func tableView(_ rows: [[String]]) -> some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 5) {
                if let header = rows.first {
                    GridRow {
                        ForEach(Array(header.enumerated()), id: \.offset) { _, cell in
                            Text(inline(cell)).bold()
                        }
                    }
                    Divider()
                }
                ForEach(Array(rows.dropFirst().enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(inline(cell))
                        }
                    }
                }
            }
            .padding(10)
        }
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .title.bold()
        case 2: .title2.bold()
        case 3: .title3.bold()
        default: .headline
        }
    }

    /// Inline Markdown (bold, italic, `code`, links) via Foundation's
    /// parser; plain text if it isn't valid Markdown.
    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}

// MARK: - Block model + parser

struct MarkdownBlock: Identifiable {
    enum Kind {
        case heading(level: Int, text: String)
        case paragraph(text: String)
        case codeBlock(code: String)
        case bulletItem(indent: Int, text: String)
        case orderedItem(indent: Int, number: String, text: String)
        case blockquote(text: String)
        case table(rows: [[String]])
        case horizontalRule
    }

    let id: Int
    let kind: Kind

    /// Blocks beyond this are dropped with a truncation note — keeps a
    /// pathological document from stalling the preview.
    private static let maxBlocks = 1500

    static func parse(_ markdown: String) -> [MarkdownBlock] {
        var kinds: [Kind] = []

        var paragraphLines: [String] = []
        var quoteLines: [String] = []
        var tableLines: [String] = []
        var codeLines: [String] = []
        var insideCodeFence = false

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            kinds.append(.paragraph(text: paragraphLines.joined(separator: " ")))
            paragraphLines = []
        }
        func flushQuote() {
            guard !quoteLines.isEmpty else { return }
            kinds.append(.blockquote(text: quoteLines.joined(separator: " ")))
            quoteLines = []
        }
        func flushTable() {
            guard !tableLines.isEmpty else { return }
            let rows = tableLines.compactMap { parseTableRow($0) }
            if !rows.isEmpty { kinds.append(.table(rows: rows)) }
            tableLines = []
        }
        func flushAll() {
            flushParagraph()
            flushQuote()
            flushTable()
        }

        for rawLine in markdown.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            // Code fences swallow everything until they close.
            if insideCodeFence {
                if line.hasPrefix("```") {
                    kinds.append(.codeBlock(code: codeLines.joined(separator: "\n")))
                    codeLines = []
                    insideCodeFence = false
                } else {
                    codeLines.append(rawLine)
                }
                continue
            }
            if line.hasPrefix("```") {
                flushAll()
                insideCodeFence = true
                continue
            }

            if line.isEmpty {
                flushAll()
                continue
            }

            // Table rows: | … | — the |---|---| separator line is skipped.
            if line.hasPrefix("|") {
                flushParagraph()
                flushQuote()
                let isSeparator = line.allSatisfy { "|-: ".contains($0) }
                if !isSeparator { tableLines.append(line) }
                continue
            } else {
                flushTable()
            }

            if line.hasPrefix("#") {
                let level = line.prefix(while: { $0 == "#" }).count
                if level <= 6, line.dropFirst(level).hasPrefix(" ") {
                    flushAll()
                    kinds.append(.heading(level: level, text: String(line.dropFirst(level + 1))))
                    continue
                }
            }

            if line == "---" || line == "***" || line == "___" {
                flushAll()
                kinds.append(.horizontalRule)
                continue
            }

            if line.hasPrefix(">") {
                flushParagraph()
                quoteLines.append(String(line.dropFirst().trimmingCharacters(in: .whitespaces)))
                continue
            } else {
                flushQuote()
            }

            // List items — indent comes from the *raw* line's leading spaces.
            let leadingSpaces = rawLine.prefix(while: { $0 == " " }).count
            if let item = parseListItem(line, indent: leadingSpaces / 2) {
                flushAll()
                kinds.append(item)
                continue
            }

            paragraphLines.append(line)
        }

        // End of document: close anything still open.
        if insideCodeFence, !codeLines.isEmpty {
            kinds.append(.codeBlock(code: codeLines.joined(separator: "\n")))
        }
        flushAll()

        if kinds.count > maxBlocks {
            kinds = Array(kinds.prefix(maxBlocks))
            kinds.append(.paragraph(text: "_…preview truncated — open the file for the rest._"))
        }
        return kinds.enumerated().map { MarkdownBlock(id: $0.offset, kind: $0.element) }
    }

    private static func parseListItem(_ line: String, indent: Int) -> Kind? {
        // "- text", "* text", "+ text"
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            return .bulletItem(indent: indent, text: String(line.dropFirst(marker.count)))
        }
        // "12. text" / "12) text"
        let digits = line.prefix(while: \.isNumber)
        guard !digits.isEmpty else { return nil }
        let afterDigits = line.dropFirst(digits.count)
        if afterDigits.hasPrefix(". ") || afterDigits.hasPrefix(") ") {
            return .orderedItem(indent: indent, number: String(digits), text: String(afterDigits.dropFirst(2)))
        }
        return nil
    }

    private static func parseTableRow(_ line: String) -> [String]? {
        // Escaped pipes (\|) are cell *content*, not separators — hide
        // them behind a placeholder before splitting.
        let placeholder = "\u{0001}"
        var cells = line
            .replacingOccurrences(of: "\\|", with: placeholder)
            .components(separatedBy: "|")
        // "| a | b |" splits into ["", " a ", " b ", ""] — drop the shell.
        if cells.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { cells.removeFirst() }
        if cells.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { cells.removeLast() }
        let trimmed = cells.map {
            $0.trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: placeholder, with: "|")
                .replacingOccurrences(of: "<br>", with: "\n")
        }
        return trimmed.isEmpty ? nil : trimmed
    }
}
