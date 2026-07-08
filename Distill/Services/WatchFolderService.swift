//
//  WatchFolderService.swift
//  Distill
//
//  Watches one folder and reports new convertible files while the app
//  runs. Built on a kqueue-backed DispatchSource: the file descriptor
//  is opened with O_EVTONLY and the source fires whenever the
//  directory's contents change.
//
//  Semantics that keep this from misbehaving:
//  - Files already in the folder when watching starts are *not*
//    converted (a baseline snapshot seeds `knownPaths`).
//  - Events are debounced, and a file must be non-empty and untouched
//    for a moment before it's picked up — dropping a big file into the
//    folder fires many events while it's still being copied.
//  - Markdown files are ignored entirely: our own outputs land in the
//    watched folder in "alongside source" mode, and converting them
//    again would loop forever.
//

import Foundation
import Observation

@MainActor
@Observable
final class WatchFolderService {

    /// Called with newly appeared convertible files. AppModel points this
    /// at addFilesAndConvert.
    @ObservationIgnored var onNewFiles: (([URL]) -> Void)?

    private(set) var isWatching = false
    private(set) var watchedFolderName: String?

    @ObservationIgnored private var source: (any DispatchSourceFileSystemObject)?
    @ObservationIgnored private var knownPaths: Set<String> = []
    @ObservationIgnored private var debounceTask: Task<Void, Never>?

    /// (Re)starts watching according to the current settings. Safe to
    /// call any time — Settings calls it when the toggle or folder change.
    func applySettings() {
        stop()
        guard AppSettings.watchFolderEnabled,
              let folder = FolderAccessManager.shared.watchFolderURL() else { return }

        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        // Baseline: whatever is in the folder now is old news.
        knownPaths = Set(candidateFiles(in: folder).map(\.path))

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: .write,
            queue: .main
        )
        source.setEventHandler { [weak self] in
            // The handler runs on the main queue; hop into MainActor
            // explicitly so the compiler agrees.
            Task { @MainActor [weak self] in
                self?.scheduleScan(of: folder)
            }
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()

        self.source = source
        watchedFolderName = folder.lastPathComponent
        isWatching = true
    }

    func stop() {
        debounceTask?.cancel()
        debounceTask = nil
        source?.cancel()   // cancel handler closes the descriptor
        source = nil
        isWatching = false
        watchedFolderName = nil
    }

    // MARK: - Scanning

    /// Directory events arrive in bursts; wait for quiet before scanning.
    private func scheduleScan(of folder: URL) {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.scan(folder)
        }
    }

    private func scan(_ folder: URL) {
        let candidates = candidateFiles(in: folder)
        var fresh: [URL] = []

        for url in candidates where !knownPaths.contains(url.path) {
            // Skip files modified within the last second — likely still
            // being written. The next directory event retries them.
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let modified = values?.contentModificationDate ?? .distantPast
            let size = values?.fileSize ?? 0
            guard size > 0, Date().timeIntervalSince(modified) > 1.0 else { continue }

            knownPaths.insert(url.path)
            fresh.append(url)
        }

        if !fresh.isEmpty {
            onNewFiles?(fresh)
        }
    }

    /// Shallow listing of files we'd actually convert: supported types,
    /// no Markdown (loop protection), nothing hidden or half-downloaded.
    private func candidateFiles(in folder: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return contents.filter { url in
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else {
                return false
            }
            if url.lastPathComponent.hasSuffix(".download") || url.lastPathComponent.hasSuffix(".part") {
                return false
            }
            guard let type = FileType.detect(from: url), type != .markdown else {
                return false
            }
            return true
        }
    }
}
