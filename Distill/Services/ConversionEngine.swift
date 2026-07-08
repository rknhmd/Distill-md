//
//  ConversionEngine.swift
//  Distill
//
//  Routes a file to the right converter and runs it off the main thread.
//

import Foundation

nonisolated enum ConversionEngine {

    /// One place maps formats to converters; Phase 2 formats (DOCX, PPTX,
    /// XLSX, …) will each add a case here and nothing else changes.
    static func converter(for type: FileType) -> any MarkdownConverting {
        switch type {
        case .pdf: PDFConverter()
        case .plainText: PlainTextConverter(isMarkdownInput: false)
        case .markdown: PlainTextConverter(isMarkdownInput: true)
        case .csv: CSVConverter(delimiter: ",")
        case .tsv: CSVConverter(delimiter: "\t")
        case .html: HTMLConverter()
        case .docx: DOCXConverter()
        case .pptx: PPTXConverter()
        case .xlsx: XLSXConverter()
        case .legacyDoc: LegacyDocConverter()
        }
    }

    /// Converts one file to Markdown.
    ///
    /// `@concurrent` sends this to the global concurrent executor — i.e.
    /// a background thread — so the UI keeps rendering while a large PDF
    /// is being chewed through. The caller just `await`s the result.
    @concurrent
    static func convert(fileAt url: URL, type: FileType) async throws -> ConversionResult {
        // URLs from the open panel need their security scope activated
        // before we can read; drag-and-drop URLs usually arrive already
        // readable (start returns false then, which is harmless).
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }

        return try await converter(for: type).convert(fileAt: url)
    }
}
