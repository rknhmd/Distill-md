//
//  AppModel.swift
//  Distill
//
//  The single source of truth for the UI: the file queue, the selection,
//  and the conversion run. Views read it; user actions call its methods.
//
//  @MainActor: all mutations happen on the main thread, so SwiftUI can
//  observe safely. The heavy lifting is `await`ed from ConversionEngine,
//  which hops to a background thread — the main thread is never blocked,
//  it just suspends.
//

import Foundation
import DistillCore
import Observation
import AppKit

@MainActor
@Observable
final class AppModel {

    // MARK: State

    var files: [QueuedFile] = []
    var selectedFileID: QueuedFile.ID?

    /// Watches the folder chosen in Settings and feeds new files in.
    let watchFolder = WatchFolderService()

    init() {
        watchFolder.onNewFiles = { [weak self] urls in
            self?.addFilesAndConvert(urls)
        }
        watchFolder.applySettings()
    }

    private(set) var isConverting = false
    /// Progress through the current run, for the status bar.
    private(set) var runCompleted = 0
    private(set) var runTotal = 0

    /// A short-lived message for the status bar ("Copied to clipboard").
    private(set) var statusFlash: String?

    // MARK: Derived values

    var selectedFile: QueuedFile? {
        files.first { $0.id == selectedFileID }
    }

    var pendingCount: Int { files.filter { $0.status == .pending }.count }

    var doneCount: Int {
        files.filter { if case .done = $0.status { true } else { false } }.count
    }

    var failedCount: Int {
        files.filter { if case .failed = $0.status { true } else { false } }.count
    }

    // MARK: Adding files

    func addFiles(_ urls: [URL]) {
        for url in urls {
            let url = url.standardizedFileURL

            // Same file twice is a no-op (use "Convert Again" to re-run).
            guard !files.contains(where: { $0.sourceURL == url }) else { continue }

            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                continue
            }
            if isDirectory.boolValue {
                files.append(QueuedFile(
                    sourceURL: url, type: nil, sizeBytes: 0,
                    status: .failed(reason: "Folders aren't supported — drop individual files")
                ))
                continue
            }

            let type = FileType.detect(from: url)
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { Int64($0) } ?? 0

            // Unsupported files still get a row (with a reason) — seeing
            // *why* nothing happened beats a file silently vanishing.
            let status: ConversionStatus = type == nil
                ? .failed(reason: "Unsupported file type")
                : .pending
            files.append(QueuedFile(sourceURL: url, type: type, sizeBytes: size, status: status))
        }
    }

    /// The File → Add Files… menu command (⌘O). Unlike the toolbar
    /// button (which uses SwiftUI's fileImporter), menu commands live
    /// outside the view hierarchy, so this shows an NSOpenPanel directly.
    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = FileType.importableUTTypes
        panel.prompt = "Add"
        if panel.runModal() == .OK {
            addFiles(panel.urls)
        }
    }

    /// Files arriving from outside the window — "Open With", the Finder
    /// Quick Action, or the watch folder — should convert immediately;
    /// that's what the sender asked for. If a run is already going, the
    /// new files join it (runQueue drains *all* pending files).
    func addFilesAndConvert(_ urls: [URL]) {
        addFiles(urls)
        if isConverting {
            runTotal = runCompleted + pendingCount
        } else {
            convertAll()
        }
    }

    // MARK: Queue management

    func removeFile(id: QueuedFile.ID) {
        guard !isConverting else { return }
        files.removeAll { $0.id == id }
        if selectedFileID == id { selectedFileID = nil }
    }

    func clearQueue() {
        guard !isConverting else { return }
        files.removeAll()
        selectedFileID = nil
    }

    /// Re-queues a failed (or already-converted) file.
    func requeue(id: QueuedFile.ID) {
        guard !isConverting, let index = files.firstIndex(where: { $0.id == id }) else { return }
        files[index].status = .pending
        files[index].tokenEstimate = nil
    }

    // MARK: Conversion

    func convertAll() {
        guard !isConverting, pendingCount > 0 else { return }

        isConverting = true
        runTotal = pendingCount
        runCompleted = 0

        // This Task stays on the MainActor (it inherits the model's
        // isolation); only ConversionEngine.convert hops off it.
        Task {
            await runQueue()
        }
    }

    private func runQueue() async {
        var convertedIDs: [QueuedFile.ID] = []

        // A while-loop rather than a snapshot of IDs: files added during
        // the run (Quick Action, watch folder) get drained by it too.
        while let index = files.firstIndex(where: { $0.status == .pending }) {
            let id = files[index].id
            guard let type = files[index].type else {
                // Shouldn't happen (typeless files are queued as .failed),
                // but a plain `continue` here would loop forever.
                files[index].status = .failed(reason: "Unsupported file type")
                continue
            }

            files[index].status = .converting
            let sourceURL = files[index].sourceURL

            do {
                let options = ConversionOptions(extractImages: AppSettings.extractImages)
                let result = try await ConversionEngine.convert(fileAt: sourceURL, type: type, options: options)

                // Token estimate covers the *content*; the optional front
                // matter below quotes that number, so order matters.
                let tokens = TokenEstimator.estimate(result.markdown)

                var markdown = result.markdown
                if AppSettings.includeFrontMatter,
                   !FrontMatter.contentAlreadyHasFrontMatter(markdown, type: type) {
                    markdown = FrontMatter.header(
                        sourceName: sourceURL.lastPathComponent,
                        format: type,
                        result: result,
                        tokenEstimate: tokens
                    ) + markdown
                }

                let outputURL = try OutputWriter.write(markdown, assets: result.assets, forSource: sourceURL)
                if let i = files.firstIndex(where: { $0.id == id }) {
                    files[i].tokenEstimate = tokens
                    files[i].status = .done(outputURL: outputURL)
                    // Auto-show the first result if nothing is selected yet.
                    if selectedFileID == nil { selectedFileID = id }
                }
            } catch {
                let reason = (error as? ConversionError)?.errorDescription ?? error.localizedDescription
                if let i = files.firstIndex(where: { $0.id == id }) {
                    files[i].status = .failed(reason: reason)
                }
            }
            convertedIDs.append(id)
            runCompleted += 1
        }
        isConverting = false

        autoCopyIfRequested(convertedIDs: convertedIDs)
    }

    /// Phase 3: when the run converted exactly one file successfully and
    /// the Settings toggle is on, put the result straight on the clipboard.
    /// The model no longer holds the Markdown (v2.0.1 fix 1), so this
    /// reads the freshly written output file — off the main actor, since
    /// the file can be large.
    private func autoCopyIfRequested(convertedIDs: [QueuedFile.ID]) {
        guard runTotal == 1,
              AppSettings.autoCopyToClipboard,
              let id = convertedIDs.first,
              let file = files.first(where: { $0.id == id }),
              case .done(let outputURL) = file.status else { return }

        Task {
            guard let markdown = await Self.readOutputFile(at: outputURL) else { return }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(markdown, forType: .string)
            flash("Markdown copied to clipboard")
        }
    }

    /// Disk read forced onto the global concurrent executor.
    @concurrent
    private nonisolated static func readOutputFile(at url: URL) async -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }

    private func flash(_ message: String) {
        statusFlash = message
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            // Clear only if nothing newer replaced the message meanwhile.
            if statusFlash == message { statusFlash = nil }
        }
    }

    // MARK: Clipboard conversion (⌘⇧V)

    /// Reads HTML or RTF off the pasteboard, converts it to Markdown,
    /// and puts the Markdown back. Plain text passes through unchanged
    /// (the status flash says so). v2 brief item 4.
    func convertClipboard() {
        let pasteboard = NSPasteboard.general

        func replaceClipboard(with markdown: String, message: String) {
            pasteboard.clearContents()
            pasteboard.setString(markdown, forType: .string)
            flash(message)
        }

        if let html = pasteboard.string(forType: .html) {
            let markdown = ConversionEngine.markdown(fromHTML: html)
            if !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                replaceClipboard(with: markdown, message: "Clipboard converted to Markdown")
                return
            }
        }
        if let rtfData = pasteboard.data(forType: .rtf) {
            if let markdown = try? ConversionEngine.markdown(fromRTF: rtfData) {
                replaceClipboard(with: markdown, message: "Clipboard converted to Markdown")
                return
            }
        }
        if let plain = pasteboard.string(forType: .string) {
            replaceClipboard(with: plain, message: "Clipboard was already plain text")
            return
        }
        flash("Nothing convertible on the clipboard")
    }
}
