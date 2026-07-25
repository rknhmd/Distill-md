//
//  FileType.swift
//  Distill
//
//  The document formats Distill knows how to convert in Phase 1.
//

import Foundation
import UniformTypeIdentifiers

/// A supported input format.
///
/// `nonisolated` opts this type out of the project's default MainActor
/// isolation so the background conversion code can use it freely.
public nonisolated enum FileType: String, CaseIterable {
    case pdf
    case plainText
    case markdown
    case csv
    case tsv
    case html
    case docx
    case pptx
    case xlsx
    case legacyDoc   // .doc / .rtf, converted via macOS's textutil
    case zip

    /// Human-readable name shown in the UI.
    public var displayName: String {
        switch self {
        case .pdf: "PDF"
        case .plainText: "Text"
        case .markdown: "Markdown"
        case .csv: "CSV"
        case .tsv: "TSV"
        case .html: "HTML"
        case .docx: "Word"
        case .pptx: "PowerPoint"
        case .xlsx: "Excel"
        case .legacyDoc: "Legacy document"
        case .zip: "ZIP archive"
        }
    }

    /// SF Symbol used for the row icon in the file queue.
    public var symbolName: String {
        switch self {
        case .pdf: "doc.richtext"
        case .plainText: "doc.plaintext"
        case .markdown: "doc.text"
        case .csv, .tsv, .xlsx: "tablecells"
        case .html: "chevron.left.forwardslash.chevron.right"
        case .docx: "doc.fill"
        case .pptx: "rectangle.on.rectangle"
        case .legacyDoc: "doc.badge.clock"
        case .zip: "doc.zipper"
        }
    }

    /// Everything the open panel / file importer should accept. `.text`
    /// covers txt/md/csv already, but listing the specific types keeps
    /// the panel's enabled-files behavior predictable. The Office types
    /// have no UTType constants; they're looked up by extension.
    public static let importableUTTypes: [UTType] = [
        .pdf, .plainText, .text, .html, .commaSeparatedText, .tabSeparatedText, .rtf, .zip,
    ] + ["docx", "pptx", "xlsx", "doc"].compactMap { UTType(filenameExtension: $0) }

    /// Detects the format of a file, or returns `nil` if Distill can't
    /// convert it (yet). Detection is primarily by file extension, with a
    /// UTType conformance check as a fallback for unusual extensions.
    public static func detect(from url: URL) -> FileType? {
        switch url.pathExtension.lowercased() {
        case "pdf": return .pdf
        case "txt", "text", "log": return .plainText
        case "md", "markdown", "mdown", "mkd": return .markdown
        case "csv": return .csv
        case "tsv", "tab": return .tsv
        case "html", "htm", "xhtml": return .html
        case "docx": return .docx
        case "pptx": return .pptx
        case "xlsx": return .xlsx
        case "doc", "rtf": return .legacyDoc
        case "zip": return .zip
        default: break
        }

        // Fallback: ask the system what this extension means. This catches
        // things like ".mdtext" or exotic plain-text extensions.
        guard let type = UTType(filenameExtension: url.pathExtension) else { return nil }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .html) { return .html }
        if type.conforms(to: .commaSeparatedText) { return .csv }
        if type.conforms(to: .tabSeparatedText) { return .tsv }
        if type.conforms(to: .rtf) { return .legacyDoc }
        if type.conforms(to: .plainText) { return .plainText }
        if type.conforms(to: .zip) { return .zip }
        return nil
    }
}
