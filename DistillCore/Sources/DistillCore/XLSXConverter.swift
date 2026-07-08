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

    func convert(fileAt url: URL, options: ConversionOptions) throws -> ConversionResult {
        guard let file = XLSXFile(filepath: url.path) else {
            throw ConversionError.fileUnreadable
        }

        // Most cell text lives in a shared-strings pool; cells hold indexes.
        let sharedStrings = try? file.parseSharedStrings()

        // Style index → is-this-a-date classification, so serial numbers
        // in date-formatted cells render as dates instead of "46203".
        let dateKinds = Self.dateKindsByStyleIndex(try? file.parseStyles())

        // Excel has two epochs. CoreXLSX doesn't surface workbookPr, so
        // read the 1904 flag straight out of xl/workbook.xml ourselves.
        let use1904 = Self.workbookUses1904DateSystem(url: url)

        let context = CellContext(sharedStrings: sharedStrings, dateKinds: dateKinds, use1904: use1904)

        var sheets: [(name: String?, table: String)] = []
        var totalSheetCount = 0

        do {
            for workbook in try file.parseWorkbooks() {
                for (name, path) in try file.parseWorksheetPathsAndNames(workbook: workbook) {
                    totalSheetCount += 1
                    let worksheet = try file.parseWorksheet(at: path)
                    if let table = Self.markdownTable(for: worksheet, context: context) {
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
        let markdown: String
        if sheets.count == 1 && totalSheetCount == 1 {
            markdown = sheets[0].table
        } else {
            markdown = sheets
                .map { "## Sheet: \($0.name ?? "Unnamed")\n\n\($0.table)" }
                .joined(separator: "\n")
        }
        return ConversionResult(markdown: markdown, unitCount: totalSheetCount, unitLabel: "sheets")
    }

    /// Everything a cell needs to render itself as text.
    private struct CellContext {
        let sharedStrings: SharedStrings?
        let dateKinds: [Int: DateKind]
        let use1904: Bool
    }

    /// What a date-formatted cell's number format asks for.
    private enum DateKind {
        case date       // 2026-07-08
        case time       // 14:30
        case dateTime   // 2026-07-08 14:30
    }

    /// Renders one worksheet, or nil when it has no content at all.
    private static func markdownTable(for worksheet: Worksheet, context: CellContext) -> String? {
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
                cellsByColumn[column] = text(for: cell, context: context)
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

    private static func text(for cell: Cell, context: CellContext) -> String {
        // Shared-string cells: the value is an index into the pool.
        // (Gate on the type: CoreXLSX's stringValue returns the raw value
        // for every OTHER cell type too, which would swallow the
        // date-formatted numerics below.)
        if cell.type == .sharedString,
           let sharedStrings = context.sharedStrings,
           let text = cell.stringValue(sharedStrings) {
            return text
        }
        // Inline strings carry their text directly.
        if let inline = cell.inlineString?.text {
            return inline
        }
        // ISO-typed date cells (t="d") carry the timestamp as text.
        if cell.type == .date, let value = cell.value {
            return String(value.prefix(16)).replacingOccurrences(of: "T", with: " ")
        }
        // Numeric cells whose style says "this is a date/time": convert
        // the serial number.
        if let style = cell.styleIndex,
           let kind = context.dateKinds[style],
           let serial = cell.value.flatMap(Double.init) {
            return formatSerial(serial, kind: kind, use1904: context.use1904)
        }
        // Everything else (numbers, booleans, formula results) has its
        // cached value as a plain string.
        return cell.value ?? ""
    }

    // MARK: - Date support

    /// Builds style-index → DateKind from styles.xml. Built-in number
    /// formats 14–22 and 45–47 are date/time; custom formats (id ≥ 164)
    /// are classified from their format code.
    private static func dateKindsByStyleIndex(_ styles: Styles?) -> [Int: DateKind] {
        guard let formats = styles?.cellFormats?.items else { return [:] }

        // Custom format codes by id, e.g. 164: "yyyy-mm-dd;@".
        var customCodes: [Int: String] = [:]
        for format in styles?.numberFormats?.items ?? [] {
            customCodes[format.id] = format.formatCode
        }

        var kinds: [Int: DateKind] = [:]
        for (index, format) in formats.enumerated() {
            let id = format.numberFormatId
            switch id {
            case 14...17: kinds[index] = .date
            case 18...21, 45...47: kinds[index] = .time
            case 22: kinds[index] = .dateTime
            default:
                if let code = customCodes[id], let kind = classify(formatCode: code) {
                    kinds[index] = kind
                }
            }
        }
        return kinds
    }

    /// Reads a custom number-format code ("yyyy-mm-dd hh:mm;@") and
    /// decides whether it's a date, time, or both. Quoted literals and
    /// [bracketed] sections don't count; 'm' alone is ambiguous
    /// (month vs minute) so the signal is y/d for dates, h/s for times.
    private static func classify(formatCode: String) -> DateKind? {
        var meaningful = ""
        var inQuote = false, inBracket = false
        for ch in formatCode {
            switch ch {
            case "\"": inQuote.toggle()
            case "[": inBracket = true
            case "]": inBracket = false
            default:
                if !inQuote && !inBracket { meaningful.append(ch) }
            }
        }
        let lower = meaningful.lowercased()
        let hasDate = lower.contains("y") || lower.contains("d")
        let hasTime = lower.contains("h") || lower.contains("s")
        switch (hasDate, hasTime) {
        case (true, true): return .dateTime
        case (true, false): return .date
        case (false, true): return .time
        case (false, false): return nil
        }
    }

    /// Excel's 1900 epoch is 1899-12-30 by convention: that offset
    /// absorbs Excel's fictitious 1900-02-29 (the famous Lotus 1-2-3
    /// compatibility bug) for all real dates. The 1904 system (old Mac
    /// Excel) starts at 1904-01-01 and has no quirk.
    private static func formatSerial(_ serial: Double, kind: DateKind, use1904: Bool) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        let epochComponents = use1904
            ? DateComponents(year: 1904, month: 1, day: 1)
            : DateComponents(year: 1899, month: 12, day: 30)
        guard let epoch = calendar.date(from: epochComponents) else { return String(serial) }

        // Round to the nearest minute — serial fractions carry float fuzz.
        let seconds = (serial * 86400 / 60).rounded() * 60
        let date = epoch.addingTimeInterval(seconds)
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)

        func pad(_ value: Int?, _ width: Int = 2) -> String {
            String(format: "%0\(width)d", value ?? 0)
        }
        let dateText = "\(pad(parts.year, 4))-\(pad(parts.month))-\(pad(parts.day))"
        let timeText = "\(pad(parts.hour)):\(pad(parts.minute))"

        switch kind {
        case .date: return dateText
        case .time: return timeText
        case .dateTime: return "\(dateText) \(timeText)"
        }
    }

    /// Peeks at xl/workbook.xml for <workbookPr date1904="1"/>.
    /// String-level check — the flag is a single attribute and pulling
    /// in a whole XML walk for it isn't worth it.
    private static func workbookUses1904DateSystem(url: URL) -> Bool {
        guard let archive = try? OOXMLArchive(url: url),
              let data = archive.dataIfPresent(at: "xl/workbook.xml"),
              let xml = String(data: data, encoding: .utf8) else { return false }
        guard let range = xml.range(of: "date1904=\"") else { return false }
        let value = xml[range.upperBound...].prefix { $0 != "\"" }
        return value == "1" || value.lowercased() == "true"
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
