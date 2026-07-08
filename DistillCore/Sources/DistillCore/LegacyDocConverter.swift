//
//  LegacyDocConverter.swift
//  Distill
//
//  Handles legacy .doc and .rtf via macOS's built-in `textutil` command
//  (an OS tool, not a bundled dependency — allowed by the project brief).
//
//  The pipeline: copy the file into our sandbox container's temp folder
//  (a child process can always read there, whereas the drag-and-drop
//  grant on the original may not extend to it), run
//  `textutil -convert html -stdout`, then feed the HTML through the same
//  HTML→Markdown parser the .html converter uses. Going through HTML
//  (instead of plain text) preserves headings, bold/italic, lists, and
//  tables.
//

import Foundation

nonisolated struct LegacyDocConverter: MarkdownConverting {

    func convert(fileAt url: URL, options: ConversionOptions) throws -> ConversionResult {
        let html = try TextUtil.htmlFromFile(at: url)
        let markdown = HTMLConverter().markdown(fromHTML: html)
        guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ConversionError.noConvertibleContent
        }
        return ConversionResult(markdown: markdown)
    }
}

/// Runs macOS's built-in `textutil` (an OS tool, not a bundled
/// dependency) to turn legacy formats into HTML for our parser.
/// Inputs are staged into the process's temp directory first: a child
/// process can always read there, whereas grants on the original file
/// may not extend to it.
nonisolated enum TextUtil {

    static func htmlFromFile(at url: URL) throws -> String {
        let stagingDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: stagingDir) }

        let stagedInput = stagingDir.appendingPathComponent(url.lastPathComponent)
        do {
            try FileManager.default.copyItem(at: url, to: stagedInput)
        } catch {
            throw ConversionError.fileUnreadable
        }
        return try htmlFromStagedFile(stagedInput)
    }

    static func htmlFromData(_ data: Data, fileExtension: String) throws -> String {
        let stagingDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: stagingDir) }

        let stagedInput = stagingDir.appendingPathComponent("clipboard.\(fileExtension)")
        try data.write(to: stagedInput)
        return try htmlFromStagedFile(stagedInput)
    }

    private static func htmlFromStagedFile(_ input: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
        process.arguments = ["-convert", "html", "-stdout", input.path]

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()   // silence; the exit code is enough

        do {
            try process.run()
        } catch {
            throw ConversionError.textutilFailed
        }
        // Drain stdout *before* waiting: if the pipe's buffer fills while
        // we wait, textutil blocks on write and we deadlock.
        let htmlData = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ConversionError.textutilFailed
        }
        guard let html = String(data: htmlData, encoding: .utf8), !html.isEmpty else {
            throw ConversionError.noConvertibleContent
        }
        return html
    }
}
