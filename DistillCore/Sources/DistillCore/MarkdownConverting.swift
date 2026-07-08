//
//  MarkdownConverting.swift
//  Distill
//
//  The common interface every converter implements, plus the shared
//  error type. New formats (DOCX, PPTX, … in Phase 2) just add a new
//  conforming type and one line in ConversionEngine.
//

import Foundation

/// What a conversion produces: the Markdown itself, plus the format's
/// notion of "how many units" (pages, slides, sheets) when it has one —
/// used by the optional YAML front-matter header.
public nonisolated struct ConversionResult {
    public let markdown: String
    public var unitCount: Int?
    public var unitLabel: String

    public init(markdown: String, unitCount: Int? = nil, unitLabel: String = "pages") {
        self.markdown = markdown
        self.unitCount = unitCount
        self.unitLabel = unitLabel
    }
}

/// Anything that can turn a file on disk into Markdown.
///
/// `nonisolated` + `Sendable`: converters run on a background thread
/// (see `ConversionEngine`), so they must not touch MainActor state and
/// must be safe to pass across concurrency domains. All converters are
/// stateless value types, which satisfies this automatically.
///
/// The requirement is `async` because some converters await other
/// frameworks (PDF OCR awaits Vision). Purely synchronous converters
/// just declare `func convert(fileAt:) throws -> ConversionResult` — a
/// sync method satisfies an async requirement.
nonisolated protocol MarkdownConverting: Sendable {
    func convert(fileAt url: URL) async throws -> ConversionResult
}

/// Every way a conversion can fail, with a user-facing message for each.
/// Keeping messages here (not scattered through the UI) means the failure
/// reason shown in the queue row is always specific and consistent.
public nonisolated enum ConversionError: Error, LocalizedError, Equatable {
    case unsupportedType
    case fileUnreadable
    case emptyFile
    case textEncodingUnrecognized
    case pdfPasswordProtected
    case pdfHasNoTextLayer
    case corruptDocument
    case textutilFailed
    case noConvertibleContent
    case customOutputFolderNotSet
    case writePermissionDenied(folderName: String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedType:
            "Unsupported file type"
        case .fileUnreadable:
            "The file couldn't be read"
        case .emptyFile:
            "The file is empty"
        case .textEncodingUnrecognized:
            "Couldn't decode the file's text encoding"
        case .pdfPasswordProtected:
            "The PDF is password-protected"
        case .pdfHasNoTextLayer:
            "No readable text found on any page, even with OCR"
        case .corruptDocument:
            "The document's internal structure couldn't be read"
        case .textutilFailed:
            "macOS's document converter couldn't process this file"
        case .noConvertibleContent:
            "No convertible content found in the file"
        case .customOutputFolderNotSet:
            "No output folder chosen — pick one in Settings"
        case .writePermissionDenied(let folderName):
            "Permission to write in “\(folderName)” was not granted"
        }
    }
}
