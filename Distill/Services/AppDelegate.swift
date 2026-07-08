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
import os.log

private nonisolated let logger = Logger(subsystem: "com.rakan.Distill", category: "open-files")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Set by DistillApp once the SwiftUI scene exists. Files can arrive
    /// *before* that (opening a file can be what launches the app), so
    /// they're buffered until the model shows up.
    var model: AppModel? {
        didSet { flushPendingURLs() }
    }

    private var pendingURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register as the provider of the "Convert to md" Service
        // declared under NSServices in Info.plist.
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        logger.log("received \(urls.count) file(s) to open (model attached: \(self.model != nil))")
        // The Quick Action hands files over without activating us (doing
        // so from the extension breaks Finder's request) — come forward
        // now so the user sees the conversion happen.
        NSApp.activate()
        pendingURLs.append(contentsOf: urls)
        flushPendingURLs()
    }

    /// The Service entry point. The selector is derived from the
    /// NSMessage key in Info.plist: "convertToMarkdown" →
    /// convertToMarkdown(_:userData:error:).
    @objc func convertToMarkdown(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
        logger.log("service invoked with \(urls.count) file(s)")
        guard !urls.isEmpty else { return }

        NSApp.activate()
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
