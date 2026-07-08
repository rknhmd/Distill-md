//
//  AppDelegate.swift
//  Distill
//
//  SwiftUI apps still need a small NSApplicationDelegate for one thing
//  we use: receiving files opened from Finder ("Open With → Distill",
//  or the Quick Action extension handing files over). Launch Services
//  attaches sandbox read access to files delivered this way, same as
//  drag-and-drop.
//

import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Set by DistillApp once the SwiftUI scene exists. Files can arrive
    /// *before* that (opening a file can be what launches the app), so
    /// they're buffered until the model shows up.
    var model: AppModel? {
        didSet { flushPendingURLs() }
    }

    private var pendingURLs: [URL] = []

    func application(_ application: NSApplication, open urls: [URL]) {
        pendingURLs.append(contentsOf: urls)
        flushPendingURLs()
    }

    private func flushPendingURLs() {
        guard let model, !pendingURLs.isEmpty else { return }
        let urls = pendingURLs
        pendingURLs = []
        model.addFilesAndConvert(urls)
    }
}
