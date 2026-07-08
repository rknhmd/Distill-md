//
//  FrontMatter.swift
//  Distill
//
//  Builds the optional YAML metadata header (Settings → "Include
//  metadata header"). Prepended by AppModel after conversion — the
//  converters themselves stay metadata-free.
//

import Foundation

nonisolated enum FrontMatter {

    /// ---
    /// source: lecture-05.pptx
    /// converted: 2026-07-08
    /// format: PowerPoint
    /// slides: 24
    /// tokens: ~3200
    /// ---
    static func header(
        sourceName: String,
        format: FileType,
        result: ConversionResult,
        tokenEstimate: Int
    ) -> String {
        var lines = ["---"]
        lines.append("source: \(yamlSafe(sourceName))")
        lines.append("converted: \(todayISO())")
        lines.append("format: \(format.displayName)")
        if let count = result.unitCount {
            lines.append("\(result.unitLabel): \(count)")
        }
        lines.append("tokens: ~\(tokenEstimate)")
        lines.append("---")
        return lines.joined(separator: "\n") + "\n\n"
    }

    /// A .md input that already begins with front matter keeps it —
    /// emitting a second header would corrupt the first.
    static func contentAlreadyHasFrontMatter(_ markdown: String, type: FileType?) -> Bool {
        type == .markdown && markdown.hasPrefix("---")
    }

    /// Quote values YAML would misparse (":" starts a mapping, "#" a
    /// comment). File names rarely need this, but "Report: final.docx"
    /// exists somewhere.
    private static func yamlSafe(_ value: String) -> String {
        guard value.contains(":") || value.contains("#") || value.hasPrefix(" ") else {
            return value
        }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    private static func todayISO() -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let parts = calendar.dateComponents([.year, .month, .day], from: Date())
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
