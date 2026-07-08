//
//  ActionRequestHandler.swift
//  DistillQuickAction
//
//  The Finder Quick Action ("Convert to Markdown"). It has no UI and
//  does no conversion itself: it collects the selected files and opens
//  them with the main app through Launch Services, which attaches
//  sandbox read access to each file — the same grant a drag-and-drop
//  would produce. The app then queues and converts them normally
//  (see AppDelegate.application(_:open:)).
//

import Foundation
import AppKit
import UniformTypeIdentifiers

/// `nonisolated`: the system may call `beginRequest` off the main
/// thread, so this class must not assume MainActor.
nonisolated final class ActionRequestHandler: NSObject, NSExtensionRequestHandling {

    func beginRequest(with context: NSExtensionContext) {
        let providers = context.inputItems
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] }
            .filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }

        guard !providers.isEmpty else {
            context.completeRequest(returningItems: nil)
            return
        }

        // Collect every file URL, then hand the batch over in one go.
        let collected = URLCollector()
        let group = DispatchGroup()

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    collected.append(url)
                } else if let url = item as? URL {
                    collected.append(url)
                }
            }
        }

        group.notify(queue: .main) {
            let urls = collected.snapshot()
            guard !urls.isEmpty else {
                context.completeRequest(returningItems: nil)
                return
            }

            // The .appex lives at Distill.app/Contents/PlugIns/…, so the
            // host app is three directories up.
            let hostAppURL = Bundle.main.bundleURL
                .deletingLastPathComponent()   // PlugIns/
                .deletingLastPathComponent()   // Contents/
                .deletingLastPathComponent()   // Distill.app

            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.open(urls, withApplicationAt: hostAppURL, configuration: configuration) { _, _ in
                context.completeRequest(returningItems: nil)
            }
        }
    }
}

/// Tiny thread-safe accumulator — provider callbacks arrive on
/// arbitrary queues.
private final class URLCollector: @unchecked Sendable {
    private var urls: [URL] = []
    private let lock = NSLock()

    func append(_ url: URL) {
        lock.lock()
        defer { lock.unlock() }
        urls.append(url)
    }

    func snapshot() -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        return urls
    }
}
