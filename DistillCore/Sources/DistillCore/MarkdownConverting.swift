//
//  MarkdownConverting.swift
//  Distill
//
//  The common interface every converter implements, plus the shared
//  error type. New formats (DOCX, PPTX, … in Phase 2) just add a new
//  conforming type and one line in ConversionEngine.
//

import Foundation

/// Knobs the caller can turn per conversion.
public nonisolated struct ConversionOptions: Sendable {
    /// Extract embedded images (DOCX/PPTX media, PDF page images). The
    /// Markdown then contains `distill-asset://<name>` placeholder links
    /// and the result carries the image bytes — AssetWriter turns both
    /// into real files + relative links once the output path is known.
    public var extractImages: Bool

    public init(extractImages: Bool = false) {
        self.extractImages = extractImages
    }
}

/// An embedded image pulled out of a document, not yet written anywhere.
public nonisolated struct ExtractedAsset: Sendable {
    /// Name the Markdown placeholders reference, e.g. "image1.png".
    public let name: String
    public let data: Data

    public init(name: String, data: Data) {
        self.name = name
        self.data = data
    }
}

/// What a conversion produces: the Markdown itself, plus the format's
/// notion of "how many units" (pages, slides, sheets) when it has one —
/// used by the optional YAML front-matter header — and any extracted
/// images awaiting materialization.
public nonisolated struct ConversionResult {
    public let markdown: String
    public var unitCount: Int?
    public var unitLabel: String
    public var assets: [ExtractedAsset]

    public init(markdown: String, unitCount: Int? = nil, unitLabel: String = "pages", assets: [ExtractedAsset] = []) {
        self.markdown = markdown
        self.unitCount = unitCount
        self.unitLabel = unitLabel
        self.assets = assets
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
/// just declare `func convert(fileAt:options:) throws` — a sync method
/// satisfies an async requirement. Converters without embedded images
/// simply ignore `options`.
nonisolated protocol MarkdownConverting: Sendable {
    func convert(fileAt url: URL, options: ConversionOptions) async throws -> ConversionResult
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
