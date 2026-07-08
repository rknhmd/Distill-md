//
//  PlainTextConverter.swift
//  Distill
//
//  Handles .txt and .md files: mostly passthrough, plus light cleanup so
//  the output is tidy and token-efficient.
//

import Foundation

nonisolated struct PlainTextConverter: MarkdownConverting {

    /// Markdown gives meaning to some whitespace (two trailing spaces are a
    /// hard line break), so for .md input we skip the per-line trimming we
    /// apply to plain .txt files.
    let isMarkdownInput: Bool

    func convert(fileAt url: URL) throws -> ConversionResult {
        var text = try TextFileReader.read(url)

        // Normalize Windows (\r\n) and old-Mac (\r) line endings to \n.
        text = text.replacingOccurrences(of: "\r\n", with: "\n")
        text = text.replacingOccurrences(of: "\r", with: "\n")

        var lines = text.components(separatedBy: "\n")

        if !isMarkdownInput {
            // Trailing spaces/tabs are invisible noise in plain text.
            lines = lines.map { line in
                var line = line
                while let last = line.last, last == " " || last == "\t" {
                    line.removeLast()
                }
                return line
            }
        }

        // Collapse runs of 3+ blank lines down to a single blank line —
        // enough to keep paragraph separation without wasting tokens.
        var cleaned: [String] = []
        var blankRun = 0
        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                blankRun += 1
                if blankRun <= 1 { cleaned.append(line) }
            } else {
                blankRun = 0
                cleaned.append(line)
            }
        }

        // Drop leading/trailing blank lines and end with exactly one newline.
        while cleaned.first?.isEmpty == true { cleaned.removeFirst() }
        while cleaned.last?.isEmpty == true { cleaned.removeLast() }

        let result = cleaned.joined(separator: "\n")
        guard !result.isEmpty else { throw ConversionError.emptyFile }
        return ConversionResult(markdown: result + "\n")
    }
}
