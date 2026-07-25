//
//  OutputWriter.swift
//  Distill
//
//  Decides where a converted file goes and writes it there — without
//  ever overwriting anything that already exists.
//

import Foundation
import DistillCore

@MainActor
enum OutputWriter {

    /// Writes `markdown` to the effective destination — the session
    /// override when one is set, otherwise the Settings default — and
    /// returns the URL it landed at. May show a one-time "Grant Access"
    /// panel when the sandbox doesn't yet allow writing there.
    static func write(
        _ markdown: String,
        assets: [ExtractedAsset] = [],
        forSource sourceURL: URL,
        sessionOverride: AppModel.SessionOutput? = nil
    ) throws -> URL {
        let destinationFolder: URL
        switch (sessionOverride, AppSettings.outputMode) {
        case (.alongsideSource, _):
            destinationFolder = sourceURL.deletingLastPathComponent()
        case (.folder(let url), _):
            destinationFolder = url
        case (nil, .alongsideSource):
            destinationFolder = sourceURL.deletingLastPathComponent()
        case (nil, .customFolder):
            guard let custom = FolderAccessManager.shared.customOutputFolderURL() else {
                throw ConversionError.customOutputFolderNotSet
            }
            destinationFolder = custom
        }

        guard let writableFolder = FolderAccessManager.shared.writableURL(
            for: destinationFolder,
            promptIfNeeded: true
        ) else {
            throw ConversionError.writePermissionDenied(folderName: destinationFolder.lastPathComponent)
        }

        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let destination = OutputNaming.uniqueDestination(in: writableFolder, baseName: baseName)
        // Assets folder is named after the final .md (suffix included),
        // so this must run after unique naming.
        let finalMarkdown = try AssetWriter.materialize(
            markdown: markdown, assets: assets, besideMarkdownAt: destination
        )
        try Data(finalMarkdown.utf8).write(to: destination, options: .atomic)
        return destination
    }
}
