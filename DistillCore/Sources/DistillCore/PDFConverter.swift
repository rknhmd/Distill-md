//
//  PDFConverter.swift
//  Distill
//
//  Extracts the text layer from PDFs using PDFKit. Pages without a
//  usable text layer (scans, exported images) fall back to on-device
//  OCR with the Vision framework — per page, so a mixed document keeps
//  its real text and only OCRs the scanned pages.
//

import Foundation
import PDFKit
import AppKit
import Vision

nonisolated struct PDFConverter: MarkdownConverting {

    /// A page whose text layer has fewer characters than this is treated
    /// as image-only. (Scans often carry a few stray glyphs of "text".)
    private static let minimumTextLayerLength = 10

    /// OCR rendering scale: points → pixels. 2.5× ≈ 180 DPI, plenty for
    /// print-size type; the cap keeps poster-sized pages from producing
    /// gigantic bitmaps.
    private static let renderScale: CGFloat = 2.5
    private static let maxRenderDimension: CGFloat = 4000

    func convert(fileAt url: URL, options: ConversionOptions) async throws -> ConversionResult {
        guard let document = PDFDocument(url: url) else {
            throw ConversionError.fileUnreadable
        }
        guard !document.isLocked else {
            throw ConversionError.pdfPasswordProtected
        }

        // Image extraction goes through CoreGraphics' PDF object model
        // (PDFKit doesn't expose XObjects).
        let collector = options.extractImages ? AssetCollector() : nil
        let cgDocument = options.extractImages ? CGPDFDocument(url as CFURL) : nil

        var pageTexts: [String] = []
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }

            // autoreleasepool keeps PDFKit's Objective-C allocations from
            // piling up across a large document. (Only around the sync
            // part — `await` can't happen inside it.)
            let layerText = autoreleasepool { Self.cleanPageText(page.string ?? "") }
            if layerText.count >= Self.minimumTextLayerLength {
                pageTexts.append(layerText)
                continue
            }
            // When aligning images per page, hold the slot even if the
            // page yields no text below.
            defer {
                if collector != nil && pageTexts.count == pageIndex {
                    pageTexts.append("")
                }
            }

            // No usable text layer — OCR the rendered page instead.
            let ocrText = try? await Self.recognizeText(on: page)
            if let ocrText, !ocrText.isEmpty {
                pageTexts.append(ocrText)
            } else if !layerText.isEmpty {
                pageTexts.append(layerText)   // keep the few real glyphs
            }
        }

        // Per the brief: page images are appended after each page's text
        // (exact in-text position isn't recoverable from PDF structure).
        if let collector, let cgDocument {
            for pageIndex in 0..<document.pageCount {
                let links = PDFImageExtraction
                    .images(inPageAt: pageIndex + 1, of: cgDocument)
                    .map { collector.register(data: $0.data, preferredExtension: $0.fileExtension) }
                    .map { AssetCollector.placeholderLink(for: $0) }
                guard !links.isEmpty else { continue }
                let block = links.joined(separator: "\n\n")
                if pageIndex < pageTexts.count {
                    pageTexts[pageIndex] += "\n\n" + block
                } else {
                    pageTexts.append(block)
                }
            }
        }

        let nonEmptyPages = pageTexts.filter { !$0.isEmpty }
        guard !nonEmptyPages.isEmpty else {
            throw ConversionError.pdfHasNoTextLayer
        }
        return ConversionResult(
            markdown: nonEmptyPages.joined(separator: "\n\n") + "\n",
            unitCount: document.pageCount,
            unitLabel: "pages",
            assets: collector?.assets ?? []
        )
    }

    // MARK: - OCR fallback

    private static func recognizeText(on page: PDFPage) async throws -> String {
        guard let cgImage = renderImage(of: page) else { return "" }

        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        request.usesLanguageCorrection = true

        // Vision runs on-device; observations arrive in reading order.
        let observations = try await request.perform(on: cgImage)
        let lines = observations.compactMap { $0.topCandidates(1).first?.string }
        return cleanPageText(lines.joined(separator: "\n"))
    }

    private static func renderImage(of page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        let scale = min(renderScale, maxRenderDimension / max(bounds.width, bounds.height))
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let image = page.thumbnail(of: size, for: .mediaBox)
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    // MARK: - Cleanup

    /// PDF text extraction tends to leave odd spacing behind. Keep the
    /// cleanup conservative: trim line edges and collapse blank-line runs;
    /// never touch spacing *within* a line (it may be meaningful).
    private static func cleanPageText(_ text: String) -> String {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }

        var cleaned: [String] = []
        var blankRun = 0
        for line in lines {
            if line.isEmpty {
                blankRun += 1
                if blankRun <= 1 { cleaned.append(line) }
            } else {
                blankRun = 0
                cleaned.append(line)
            }
        }
        while cleaned.first?.isEmpty == true { cleaned.removeFirst() }
        while cleaned.last?.isEmpty == true { cleaned.removeLast() }
        return cleaned.joined(separator: "\n")
    }
}
