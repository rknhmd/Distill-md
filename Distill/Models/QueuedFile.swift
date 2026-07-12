//
//  QueuedFile.swift
//  Distill
//
//  One entry in the conversion queue.
//

import Foundation
import DistillCore

/// Where a file currently is in its conversion lifecycle.
enum ConversionStatus: Equatable {
    case pending
    case converting
    case done(outputURL: URL)
    case failed(reason: String)
}

/// A file the user has added to the queue.
///
/// This is a value type: views read it, and `AppModel` is the only place
/// that mutates the array of these. That keeps state changes predictable.
struct QueuedFile: Identifiable, Equatable {
    let id = UUID()
    let sourceURL: URL

    /// Detected format, or `nil` when the file isn't a supported type
    /// (such files sit in the queue with a `.failed` status so the user
    /// can see why nothing happened).
    let type: FileType?

    /// Size in bytes, read once when the file is added.
    let sizeBytes: Int64

    var status: ConversionStatus = .pending

    // Note: the converted Markdown is deliberately NOT stored here. A big
    // batch would pin every document's full text in the view tree, which
    // profiled as severe main-thread hangs on preview and Clear (v2.0.1
    // fix 1). The output path in `status` is the source of truth; the
    // preview loads content lazily.

    var fileName: String { sourceURL.lastPathComponent }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }

    /// Rough LLM token estimate, set at conversion time over the document
    /// *content* (the optional front-matter header isn't counted). Stored
    /// rather than computed so the number always describes what the
    /// estimator saw. See TokenEstimator for the heuristic.
    var tokenEstimate: Int?

    /// "~1.2k tokens" / "~87 tokens" — nil until converted.
    var formattedTokenEstimate: String? {
        guard let tokens = tokenEstimate else { return nil }
        if tokens >= 10_000 {
            return "~\(tokens / 1000)k tokens"
        }
        if tokens >= 1000 {
            return String(format: "~%.1fk tokens", Double(tokens) / 1000)
        }
        return "~\(tokens) tokens"
    }
}
