//
//  CSVConverter.swift
//  Distill
//
//  Parses CSV/TSV (RFC 4180 style: quoted fields, embedded delimiters and
//  newlines, doubled-quote escapes) and emits a Markdown table.
//

import Foundation

nonisolated struct CSVConverter: MarkdownConverting {

    /// "," for .csv, "\t" for .tsv.
    let delimiter: Character

    func convert(fileAt url: URL) throws -> String {
        let text = try TextFileReader.read(url)
        let rows = Self.parse(text, delimiter: delimiter)
        guard !rows.isEmpty else { throw ConversionError.noConvertibleContent }
        return Self.markdownTable(from: rows)
    }

    // MARK: - Parsing

    /// A small state machine over the characters. The one piece of state
    /// that matters is `insideQuotes`: inside a quoted field, delimiters
    /// and newlines are literal text, and `""` means one `"` character.
    static func parse(_ text: String, delimiter: Character) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var insideQuotes = false

        var index = text.startIndex
        let end = text.endIndex

        func endField() {
            currentRow.append(currentField)
            currentField = ""
        }
        func endRow() {
            endField()
            // Skip rows that are entirely empty (e.g. the phantom row after
            // a trailing newline, or stray blank lines).
            if !(currentRow.count == 1 && currentRow[0].isEmpty) {
                rows.append(currentRow)
            }
            currentRow = []
        }

        while index < end {
            let ch = text[index]

            if insideQuotes {
                if ch == "\"" {
                    let next = text.index(after: index)
                    if next < end, text[next] == "\"" {
                        currentField.append("\"")   // "" escape → literal quote
                        index = next
                    } else {
                        insideQuotes = false        // closing quote
                    }
                } else {
                    currentField.append(ch)
                }
            } else {
                switch ch {
                case "\"" where currentField.isEmpty:
                    insideQuotes = true             // opening quote
                case delimiter:
                    endField()
                case "\r":
                    let next = text.index(after: index)
                    if next < end, text[next] == "\n" { index = next }  // \r\n
                    endRow()
                case "\n":
                    endRow()
                default:
                    currentField.append(ch)
                }
            }
            index = text.index(after: index)
        }

        // Flush whatever the last line left behind (file may not end in \n).
        if !currentField.isEmpty || !currentRow.isEmpty {
            endRow()
        }
        return rows
    }

    // MARK: - Rendering

    static func markdownTable(from rows: [[String]]) -> String {
        // Ragged files happen; pad every row to the widest one.
        let columnCount = rows.map(\.count).max() ?? 0

        func renderRow(_ row: [String]) -> String {
            let padded = row + Array(repeating: "", count: columnCount - row.count)
            let cells = padded.map { escapeCell($0) }
            return "| " + cells.joined(separator: " | ") + " |"
        }

        var lines: [String] = []
        lines.append(renderRow(rows[0]))    // Markdown tables need a header row
        lines.append("| " + Array(repeating: "---", count: columnCount).joined(separator: " | ") + " |")
        for row in rows.dropFirst() {
            lines.append(renderRow(row))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Pipes would break the table syntax; newlines inside a cell become
    /// `<br>` (the standard Markdown-table workaround), and literal tabs
    /// become spaces so renderers don't mistake them for layout.
    private static func escapeCell(_ cell: String) -> String {
        cell.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\r\n", with: "<br>")
            .replacingOccurrences(of: "\n", with: "<br>")
            .replacingOccurrences(of: "\t", with: " ")
    }
}
