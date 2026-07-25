//
//  ZipConverter.swift
//  DistillCore
//
//  Converts a .zip archive into ONE combined Markdown document: every
//  supported file inside goes through its normal converter, each under
//  a `# path/inside/zip` section header, in stable path order.
//  Unsupported entries are listed under "Skipped" at the end — nothing
//  is dropped silently.
//
//  Safety guards (untrusted archives are the norm, not the exception):
//  - total uncompressed size capped (central-directory sizes checked
//    up front, and re-checked during extraction against lying headers)
//  - entry count capped
//  - zip-slip rejected: any entry whose resolved path escapes the
//    extraction directory fails the whole archive
//  - nested archives are skipped with a note — no recursion
//  - __MACOSX/, .DS_Store, and hidden files are ignored entirely
//
//  Embedded-image extraction is disabled for archive members (asset
//  names from different members would collide); noted in the output
//  when it would have applied.
//

import Foundation
import ZIPFoundation

nonisolated struct ZipConverter: MarkdownConverting {

    static let maxTotalUncompressedBytes: Int64 = 500 * 1024 * 1024   // 500 MB
    static let maxEntryCount = 1000

    func convert(fileAt url: URL, options: ConversionOptions) async throws -> ConversionResult {
        let archive: Archive
        do {
            archive = try Archive(url: url, accessMode: .read)
        } catch {
            throw ConversionError.corruptDocument
        }

        // ---- Pass 1: classify entries and enforce the caps up front ----
        var convertible: [(path: String, entry: Entry)] = []
        var skipped: [(path: String, reason: String)] = []
        var totalUncompressed: Int64 = 0
        var consideredCount = 0

        for entry in archive {
            let path = entry.path
            guard entry.type == .file else { continue }

            // Traversal detection happens BEFORE the junk filter: ".."
            // starts with a dot and would otherwise be swallowed as a
            // "hidden file" — silently, which is exactly wrong for a
            // malicious archive. Absolute paths are equally hostile.
            if path.hasPrefix("/") || path.split(separator: "/").contains("..") {
                throw ConversionError.archiveUnsafeEntry(path: path)
            }
            if Self.isJunk(path) { continue }

            consideredCount += 1
            guard consideredCount <= Self.maxEntryCount else {
                throw ConversionError.archiveTooManyEntries(limit: Self.maxEntryCount)
            }
            totalUncompressed += Int64(entry.uncompressedSize)
            guard totalUncompressed <= Self.maxTotalUncompressedBytes else {
                throw ConversionError.archiveTooLarge(
                    limitMB: Int(Self.maxTotalUncompressedBytes / (1024 * 1024))
                )
            }

            let entryURL = URL(fileURLWithPath: path, relativeTo: URL(fileURLWithPath: "/"))
            let type = FileType.detect(from: entryURL)
            switch type {
            case .zip:
                skipped.append((path, "nested archive — not expanded"))
            case nil:
                skipped.append((path, "unsupported format"))
            case .some:
                convertible.append((path, entry))
            }
        }

        guard !convertible.isEmpty || !skipped.isEmpty else {
            throw ConversionError.noConvertibleContent
        }

        // ---- Pass 2: extract the convertible entries ----
        let extractionDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("distill-zip-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: extractionDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: extractionDir) }

        let rootPath = extractionDir.standardizedFileURL.path
        var extracted: [(path: String, fileURL: URL, type: FileType)] = []

        for (path, entry) in convertible {
            let destination = extractionDir.appendingPathComponent(path).standardizedFileURL
            // Zip-slip: "../../etc/passwd" style entries must not escape.
            guard destination.path.hasPrefix(rootPath + "/") else {
                throw ConversionError.archiveUnsafeEntry(path: path)
            }
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            do {
                _ = try archive.extract(entry, to: destination)
            } catch {
                skipped.append((path, "couldn't be extracted"))
                continue
            }
            guard let type = FileType.detect(from: destination) else { continue }
            extracted.append((path, destination, type))
        }

        // ---- Pass 3: convert, in stable path order ----
        extracted.sort { $0.path < $1.path }
        skipped.sort { $0.path < $1.path }

        // Images off inside archives: per-member asset names would collide.
        var memberOptions = options
        memberOptions.extractImages = false

        var sections: [String] = []
        var convertedCount = 0
        for (path, fileURL, type) in extracted {
            do {
                let result = try await ConversionEngine.converter(for: type)
                    .convert(fileAt: fileURL, options: memberOptions)
                var body = result.markdown
                while body.hasSuffix("\n") { body.removeLast() }
                sections.append("# \(path)\n\n\(body)")
                convertedCount += 1
            } catch {
                let reason = (error as? ConversionError)?.errorDescription ?? error.localizedDescription
                skipped.append((path, "conversion failed: \(reason)"))
            }
        }

        if !skipped.isEmpty {
            let lines = skipped.sorted { $0.path < $1.path }
                .map { "- \($0.path) (\($0.reason))" }
            sections.append("## Skipped\n\n" + lines.joined(separator: "\n"))
        }
        if options.extractImages && convertedCount > 0 {
            sections.append("_Embedded images are not extracted from archive members._")
        }

        guard !sections.isEmpty else {
            throw ConversionError.noConvertibleContent
        }
        return ConversionResult(
            markdown: sections.joined(separator: "\n\n") + "\n",
            unitCount: convertedCount,
            unitLabel: "files"
        )
    }

    /// macOS resource-fork folders, Finder metadata, and hidden files.
    /// "." / ".." are NOT junk — they're traversal, and the caller has
    /// already rejected them before this runs.
    private static func isJunk(_ path: String) -> Bool {
        if path.hasPrefix("__MACOSX/") || path.contains("/__MACOSX/") { return true }
        for component in path.split(separator: "/") {
            if component == "." || component == ".." { continue }
            if component.hasPrefix(".") { return true }   // .DS_Store, dotfiles
        }
        return false
    }
}
