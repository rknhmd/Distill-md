//
//  PDFColumnLayout.swift
//  DistillCore
//
//  Best-effort reading order for multi-column PDF pages. PDFKit's
//  page.string walks the content stream, which interleaves side-by-side
//  columns line by line. This detects the common two-column case from
//  line geometry and emits left column then right column instead.
//
//  Guard rails (per the v2 brief): reorder ONLY when the layout is
//  unambiguous — enough lines in each band, a clear vertical gutter,
//  similar band widths, and full-width lines (title, footer) only at
//  the top or bottom. Everything else falls back to page.string.
//

import Foundation
import PDFKit

nonisolated enum PDFColumnLayout {

    /// Text for one page in corrected reading order, or nil when the
    /// page doesn't look unambiguously two-column.
    static func reorderedText(for page: PDFPage) -> String? {
        let pageBounds = page.bounds(for: .mediaBox)
        guard let fullSelection = page.selection(for: pageBounds) else { return nil }

        // Line-level text with geometry.
        let lines: [(text: String, rect: CGRect)] = fullSelection.selectionsByLine().compactMap {
            guard let text = $0.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { return nil }
            return (text, $0.bounds(for: page))
        }
        guard lines.count >= 8 else { return nil }   // too little text to judge

        // Content band and its midpoint.
        let contentMinX = lines.map(\.rect.minX).min() ?? 0
        let contentMaxX = lines.map(\.rect.maxX).max() ?? 0
        let contentWidth = contentMaxX - contentMinX
        guard contentWidth > 100 else { return nil }
        let midX = contentMinX + contentWidth / 2

        var left: [(text: String, rect: CGRect)] = []
        var right: [(text: String, rect: CGRect)] = []
        var spanning: [(text: String, rect: CGRect)] = []

        for line in lines {
            if line.rect.maxX <= midX + contentWidth * 0.02 {
                left.append(line)
            } else if line.rect.minX >= midX - contentWidth * 0.02 {
                right.append(line)
            } else {
                spanning.append(line)
            }
        }

        // Rail 1: both columns need real content.
        guard left.count >= 3, right.count >= 3 else { return nil }
        // Rail 2: columns should hold the overwhelming majority of lines.
        guard Double(left.count + right.count) >= Double(lines.count) * 0.7 else { return nil }

        // Rail 3: a clear gutter — the widest left line must end before
        // the leftmost right line begins, with visible daylight.
        let leftEdge = left.map(\.rect.maxX).max() ?? 0
        let rightEdge = right.map(\.rect.minX).min() ?? 0
        let gutter = rightEdge - leftEdge
        guard gutter >= max(8, contentWidth * 0.03) else { return nil }

        // Rail 4: similar band widths (a narrow sidebar isn't "columns").
        let leftWidth = (left.map(\.rect.maxX).max() ?? 0) - (left.map(\.rect.minX).min() ?? 0)
        let rightWidth = (right.map(\.rect.maxX).max() ?? 0) - (right.map(\.rect.minX).min() ?? 0)
        let ratio = min(leftWidth, rightWidth) / max(leftWidth, rightWidth)
        guard ratio >= 0.6 else { return nil }

        // Rail 5: spanning lines (title, footer) may only sit above or
        // below the columns — one in the middle means complex layout.
        let columnTop = max(left.map(\.rect.maxY).max() ?? 0, right.map(\.rect.maxY).max() ?? 0)
        let columnBottom = min(left.map(\.rect.minY).min() ?? 0, right.map(\.rect.minY).min() ?? 0)
        var header: [(text: String, rect: CGRect)] = []
        var footer: [(text: String, rect: CGRect)] = []
        for line in spanning {
            if line.rect.minY >= columnTop - 2 {
                header.append(line)
            } else if line.rect.maxY <= columnBottom + 2 {
                footer.append(line)
            } else {
                return nil
            }
        }

        // PDF y grows upward: top-to-bottom = descending y.
        func topToBottom(_ items: [(text: String, rect: CGRect)]) -> [String] {
            items.sorted { $0.rect.midY > $1.rect.midY }.map(\.text)
        }

        let ordered = topToBottom(header) + topToBottom(left) + topToBottom(right) + topToBottom(footer)
        return ordered.joined(separator: "\n")
    }
}
