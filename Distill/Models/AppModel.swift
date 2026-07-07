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
import Observation
import AppKit

@MainActor
@Observable
final class AppModel {

    // MARK: State

    var files: [QueuedFile] = []
    var selectedFileID: QueuedFile.ID?

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
        files[index].markdown = nil
    }

    // MARK: Conversion

    func convertAll() {
        guard !isConverting else { return }
        let pendingIDs = files.filter { $0.status == .pending }.map(\.id)
        guard !pendingIDs.isEmpty else { return }

        isConverting = true
        runTotal = pendingIDs.count
        runCompleted = 0

        // This Task stays on the MainActor (it inherits the model's
        // isolation); only ConversionEngine.convert hops off it.
        Task {
            await runQueue(ids: pendingIDs)
        }
    }

    private func runQueue(ids: [QueuedFile.ID]) async {
        for id in ids {
            // Re-find the file each iteration — the user may have removed
            // rows while we were busy converting earlier ones.
            guard let index = files.firstIndex(where: { $0.id == id }),
                  files[index].status == .pending,
                  let type = files[index].type else { continue }

            files[index].status = .converting
            let sourceURL = files[index].sourceURL

            do {
                let markdown = try await ConversionEngine.convert(fileAt: sourceURL, type: type)
                let outputURL = try OutputWriter.write(markdown, forSource: sourceURL)
                if let i = files.firstIndex(where: { $0.id == id }) {
                    files[i].markdown = markdown
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
            runCompleted += 1
        }
        isConverting = false

        autoCopyIfRequested(convertedIDs: ids)
    }

    /// Phase 3: when the run converted exactly one file successfully and
    /// the Settings toggle is on, put the result straight on the clipboard.
    private func autoCopyIfRequested(convertedIDs: [QueuedFile.ID]) {
        guard runTotal == 1,
              AppSettings.autoCopyToClipboard,
              let id = convertedIDs.first,
              let file = files.first(where: { $0.id == id }),
              case .done = file.status,
              let markdown = file.markdown else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(markdown, forType: .string)
        flash("Markdown copied to clipboard")
    }

    private func flash(_ message: String) {
        statusFlash = message
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            // Clear only if nothing newer replaced the message meanwhile.
            if statusFlash == message { statusFlash = nil }
        }
    }
}
