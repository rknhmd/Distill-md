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
import os.log

/// Unified-log channel: `log show --predicate 'subsystem == "com.rakan.Distill.QuickAction"'`
private nonisolated let logger = Logger(subsystem: "com.rakan.Distill.QuickAction", category: "handler")

/// `nonisolated`: the system may call `beginRequest` off the main
/// thread, so this class must not assume MainActor.
nonisolated final class ActionRequestHandler: NSObject, NSExtensionRequestHandling {

    func beginRequest(with context: NSExtensionContext) {
        // No conformance filter here: Finder registers each attachment
        // under the file's *own* type (a PDF is "com.adobe.pdf"), not
        // under public.file-url — filtering for file-url matches nothing.
        let providers = context.inputItems
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] }

        logger.log("beginRequest: \(context.inputItems.count) items, \(providers.count) providers")

        guard !providers.isEmpty else {
            context.completeRequest(returningItems: nil)
            return
        }

        // Collect every file URL, then hand the batch over in one go.
        let collected = URLCollector()
        let group = DispatchGroup()

        for provider in providers {
            group.enter()
            loadFileURL(from: provider) { url in
                if let url {
                    collected.append(url)
                } else {
                    logger.error("provider yielded no URL (types: \(provider.registeredTypeIdentifiers))")
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            let urls = collected.snapshot()
            guard !urls.isEmpty else {
                logger.error("no URLs could be loaded from the providers")
                context.completeRequest(returningItems: nil)
                return
            }

            // The .appex lives at Distill.app/Contents/PlugIns/…, so the
            // host app is three directories up.
            let hostAppURL = Bundle.main.bundleURL
                .deletingLastPathComponent()   // PlugIns/
                .deletingLastPathComponent()   // Contents/
                .deletingLastPathComponent()   // Distill.app

            logger.log("opening \(urls.count) file(s) with \(hostAppURL.path)")

            // Two subtleties, both learned the hard way:
            // - activates must stay false: stealing focus while Finder is
            //   still hosting this request kills the connection and Finder
            //   shows "Couldn't communicate with a helper application."
            //   The app activates itself when the files arrive instead.
            // - Complete the request *immediately* after submitting the
            //   open. Launch Services processes it independently of this
            //   process, and waiting for its completion handler here races
            //   against the host reaping us.
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            NSWorkspace.shared.open(urls, withApplicationAt: hostAppURL, configuration: configuration) { _, error in
                // Logging only — the request is already complete.
                if let error {
                    logger.error("NSWorkspace.open failed: \(error.localizedDescription)")
                }
            }
            context.completeRequest(returningItems: nil)
        }
    }
}

extension ActionRequestHandler {

    /// Gets the on-disk URL out of a Finder-provided attachment, trying
    /// the ways Finder actually delivers them:
    ///  1. an explicit public.file-url representation, if offered;
    ///  2. loadItem under the provider's own registered type — for
    ///     file-backed providers this hands back the NSURL directly;
    ///  3. loadInPlaceFileRepresentation, which resolves to the original
    ///     file when the provider allows in-place access.
    fileprivate func loadFileURL(from provider: NSItemProvider, completion: @escaping @Sendable (URL?) -> Void) {
        func decode(_ item: (any NSSecureCoding)?) -> URL? {
            if let url = item as? URL { return url }
            if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) { return url }
            if let string = item as? String { return URL(string: string) }
            return nil
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                completion(decode(item))
            }
            return
        }

        guard let typeIdentifier = provider.registeredTypeIdentifiers.first else {
            completion(nil)
            return
        }

        provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
            if let url = decode(item), url.isFileURL {
                completion(url)
                return
            }
            // Last resort: ask for a file representation without copying.
            _ = provider.loadInPlaceFileRepresentation(forTypeIdentifier: typeIdentifier) { url, isInPlace, error in
                // A copied (not in-place) URL is deleted when this handler
                // returns, and converting a temp copy would break
                // "save alongside source" anyway — only accept in-place.
                if let error {
                    logger.error("loadInPlace(\(typeIdentifier, privacy: .public)) failed: \(error.localizedDescription)")
                }
                completion(isInPlace ? url : nil)
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
