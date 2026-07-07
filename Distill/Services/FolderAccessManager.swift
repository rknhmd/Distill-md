//
//  FolderAccessManager.swift
//  Distill
//
//  Distill runs in the App Sandbox, which is why this file exists.
//
//  The sandbox rules that matter here:
//  - Dragging a file into the app (or picking it in an open panel) grants
//    access to *that file* — not to the folder it lives in.
//  - So "save foo.md next to foo.pdf" needs the user to grant access to
//    the folder once. We show an open panel pre-pointed at that folder;
//    one click on "Grant Access" and we're allowed in.
//  - A grant normally dies with the process. Persisting it as a
//    *security-scoped bookmark* lets us restore it on the next launch
//    without asking again.
//
//  This class owns that whole dance: probe → stored bookmark → prompt.
//

import AppKit

@MainActor
final class FolderAccessManager {

    static let shared = FolderAccessManager()
    private init() {}

    /// Folders whose security scope we've started this session.
    /// Keyed by the folder's standardized path.
    private var activeFolders: [String: URL] = [:]

    // MARK: - Write access to arbitrary folders

    /// Returns a URL we can actually write into for `folder`, or nil if the
    /// user declined (or `promptIfNeeded` is false and we have no grant).
    func writableURL(for folder: URL, promptIfNeeded: Bool) -> URL? {
        let folder = folder.standardizedFileURL

        // 1. Already writable: inside the app container, or covered by a
        //    security scope we started earlier in this session.
        if FileManager.default.isWritableFile(atPath: folder.path) {
            return folder
        }
        // 2. A bookmark saved from a previous grant (this or an earlier launch).
        if let resolved = resolveStoredGrant(covering: folder) {
            return resolved
        }
        // 3. Ask the user.
        guard promptIfNeeded else { return nil }
        return promptForAccess(to: folder)
    }

    private func promptForAccess(to folder: URL) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = folder
        panel.prompt = "Grant Access"
        panel.message = "Distill needs your permission to save Markdown files in “\(folder.lastPathComponent)”."

        guard panel.runModal() == .OK, let chosen = panel.url else { return nil }

        storeBookmark(for: chosen, key: nil)
        startAccessing(chosen)

        // The grant covers our target if the user picked the folder itself
        // or an ancestor. (They're free to pick somewhere unrelated, in
        // which case the write below would still fail — check honestly.)
        let target = folder.standardizedFileURL
        return FileManager.default.isWritableFile(atPath: target.path) ? target : nil
    }

    // MARK: - The custom output folder (Settings)

    /// Shows a folder picker for Settings → "A single folder I choose".
    /// Returns the chosen folder after persisting a bookmark for it.
    func chooseCustomOutputFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Converted Markdown files will be saved in this folder."

        guard panel.runModal() == .OK, let chosen = panel.url else { return nil }
        storeBookmark(for: chosen, key: AppSettings.customFolderBookmarkKey)
        startAccessing(chosen)
        return chosen.standardizedFileURL
    }

    /// Resolves the custom output folder from its bookmark, restoring
    /// access after a relaunch. nil if the user never chose one.
    func customOutputFolderURL() -> URL? {
        guard let path = AppSettings.customFolderPath else { return nil }
        if let active = activeFolders[path] { return active }

        guard let data = UserDefaults.standard.data(forKey: AppSettings.customFolderBookmarkKey),
              let url = resolveBookmark(data, rewriteKeyIfStale: AppSettings.customFolderBookmarkKey)
        else { return nil }
        startAccessing(url)
        return url
    }

    // MARK: - Bookmark plumbing

    /// Looks for a stored grant for `folder` or any of its ancestors.
    private func resolveStoredGrant(covering folder: URL) -> URL? {
        let folderPath = folder.path
        let stored = UserDefaults.standard.dictionary(forKey: AppSettings.grantedBookmarksKey) as? [String: Data] ?? [:]

        for (grantedPath, data) in stored {
            let covers = folderPath == grantedPath || folderPath.hasPrefix(grantedPath + "/")
            guard covers, let url = resolveBookmark(data, rewriteKeyIfStale: nil) else { continue }
            startAccessing(url)
            if FileManager.default.isWritableFile(atPath: folderPath) {
                return folder
            }
        }
        return nil
    }

    /// Turns bookmark data back into a URL. If the system says the bookmark
    /// is stale (the folder moved, an OS update, …), a fresh one is written.
    private func resolveBookmark(_ data: Data, rewriteKeyIfStale key: String?) -> URL? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }

        if isStale {
            storeBookmark(for: url, key: key)
        }
        return url
    }

    /// Saves a security-scoped bookmark, either under a dedicated defaults
    /// key (custom output folder) or into the shared granted-folders map.
    private func storeBookmark(for folder: URL, key: String?) {
        guard let data = try? folder.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return }

        if let key {
            UserDefaults.standard.set(data, forKey: key)
        } else {
            var all = UserDefaults.standard.dictionary(forKey: AppSettings.grantedBookmarksKey) as? [String: Data] ?? [:]
            all[folder.standardizedFileURL.path] = data
            UserDefaults.standard.set(all, forKey: AppSettings.grantedBookmarksKey)
        }
    }

    /// Begins security-scoped access and keeps the URL alive for the rest
    /// of the session. (The OS releases everything when the app exits, so
    /// there's no matching stop — deliberate, not a leak.)
    private func startAccessing(_ url: URL) {
        let path = url.standardizedFileURL.path
        guard activeFolders[path] == nil else { return }
        _ = url.startAccessingSecurityScopedResource()
        activeFolders[path] = url
    }
}
