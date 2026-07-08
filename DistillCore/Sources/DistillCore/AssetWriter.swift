//
//  AssetWriter.swift
//  DistillCore
//
//  Turns a ConversionResult's extracted images into real files. The
//  assets folder is named after the *final* .md file ("report-2.md" →
//  "report-2-assets/"), which is only known after duplicate-safe naming
//  — hence this runs at write time, not conversion time. Shared by the
//  app's OutputWriter, the CLI, and the MCP convert_file tool.
//

import Foundation

public nonisolated enum AssetWriter {

    /// The scheme converters use in placeholder links.
    public static let placeholderPrefix = "distill-asset://"

    /// Writes `assets` into "<mdBaseName>-assets/" next to the Markdown
    /// destination and rewrites placeholder links to relative paths.
    /// With no assets this is a no-op passthrough.
    public static func materialize(
        markdown: String,
        assets: [ExtractedAsset],
        besideMarkdownAt destination: URL
    ) throws -> String {
        guard !assets.isEmpty else { return markdown }

        let folderName = destination.deletingPathExtension().lastPathComponent + "-assets"
        let folder = destination.deletingLastPathComponent()
            .appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        for asset in assets {
            // Assets within one conversion are already deduped by content
            // hash, so plain overwrite semantics are fine here.
            try asset.data.write(to: folder.appendingPathComponent(asset.name), options: .atomic)
        }

        return markdown.replacingOccurrences(of: placeholderPrefix, with: folderName + "/")
    }
}
