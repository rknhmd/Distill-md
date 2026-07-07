//
//  XLSXConverter.swift
//  Distill
//
//  Converts Excel workbooks with the CoreXLSX package (hand-rolling
//  SpreadsheetML — shared strings, cell references, sparse storage —
//  isn't worth it). One Markdown table per sheet.
//

import Foundation
import CoreXLSX

nonisolated struct XLSXConverter: MarkdownConverting {

    /// Sheets beyond this many rows are cut off with a note — a million-row
    /// export would otherwise produce megabytes of Markdown nobody wants.
    private static let maxRowsPerSheet = 5000

    func convert(fileAt url: URL) throws -> String {
        guard let file = XLSXFile(filepath: url.path) else {
            throw ConversionError.fileUnreadable
        }

        // Most cell text lives in a shared-strings pool; cells hold indexes.
        let sharedStrings = try? file.parseSharedStrings()

        var sheets: [(name: String?, table: String)] = []
        var totalSheetCount = 0

        do {
            for workbook in try file.parseWorkbooks() {
                for (name, path) in try file.parseWorksheetPathsAndNames(workbook: workbook) {
                    totalSheetCount += 1
                    let worksheet = try file.parseWorksheet(at: path)
                    if let table = Self.markdownTable(for: worksheet, sharedStrings: sharedStrings) {
                        sheets.append((name: name, table: table))
                    }
                }
            }
        } catch {
            throw ConversionError.corruptDocument
        }

        guard !sheets.isEmpty else {
            throw ConversionError.noConvertibleContent
        }

        // A workbook with a single sheet doesn't need its name announced.
        if sheets.count == 1 && totalSheetCount == 1 {
            return sheets[0].table
        }
        return sheets
            .map { "## Sheet: \($0.name ?? "Unnamed")\n\n\($0.table)" }
            .joined(separator: "\n")
    }

    /// Renders one worksheet, or nil when it has no content at all.
    private static func markdownTable(for worksheet: Worksheet, sharedStrings: SharedStrings?) -> String? {
        guard let rows = worksheet.data?.rows, !rows.isEmpty else { return nil }

        var matrix: [[String]] = []
        var truncated = false

        for row in rows {
            if matrix.count >= maxRowsPerSheet {
                truncated = true
                break
            }
            // Cells are stored sparsely with A1-style references — place
            // them by column index so gaps become empty cells.
            var cellsByColumn: [Int: String] = [:]
            for cell in row.cells {
                let column = columnIndex(cell.reference.column.value)
                cellsByColumn[column] = text(for: cell, sharedStrings: sharedStrings)
            }
            guard let maxColumn = cellsByColumn.keys.max() else { continue }   // skip empty rows
            var rowValues = Array(repeating: "", count: maxColumn + 1)
            for (column, value) in cellsByColumn {
                rowValues[column] = value
            }
            // Rows that only contain empty strings aren't content either.
            if rowValues.allSatisfy({ $0.isEmpty }) { continue }
            matrix.append(rowValues)
        }

        guard !matrix.isEmpty else { return nil }
        var table = CSVConverter.markdownTable(from: matrix)
        if truncated {
            table += "\n_Sheet truncated at \(maxRowsPerSheet) rows._\n"
        }
        return table
    }

    private static func text(for cell: Cell, sharedStrings: SharedStrings?) -> String {
        // Shared-string cells: the value is an index into the pool.
        if let sharedStrings, let text = cell.stringValue(sharedStrings) {
            return text
        }
        // Inline strings carry their text directly.
        if let inline = cell.inlineString?.text {
            return inline
        }
        // Everything else (numbers, booleans, formula results) has its
        // cached value as a plain string. Dates appear as raw serial
        // numbers for now — proper date rendering is a known limitation.
        return cell.value ?? ""
    }

    /// "A" → 0, "B" → 1, … "AA" → 26 (base-26 letters, 1-based → 0-based).
    private static func columnIndex(_ letters: String) -> Int {
        var result = 0
        for scalar in letters.uppercased().unicodeScalars where scalar.value >= 65 && scalar.value <= 90 {
            result = result * 26 + Int(scalar.value) - 64
        }
        return max(0, result - 1)
    }
}
