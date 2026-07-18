//
//  PreviewPane.swift
//  Distill
//
//  The right-hand side of the window: shows the converted Markdown for
//  the selected file, with Copy and Open buttons.
//
//  Performance shape (v2.0.1): the queue model holds only the output
//  *path*; this pane streams content in batches from a background
//  producer. Three guarantees, each earned the hard way:
//   1. Selection change cancels the in-flight load (SwiftUI's
//      .task(id:) cancels the old task; every state application is
//      additionally gated on Task.isCancelled, so a stale batch from a
//      deselected file can never touch the UI).
//   2. First paint is fast for any file size: the producer reads lines
//      with a moving cursor (no up-front full split), and the first
//      batch is small (~60 lines ≈ 20–30 blocks) so content appears
//      within ~100 ms — measured by the PreviewFirstPaint signpost.
//   3. Switching away is cheap: state is cleared in one transaction
//      before any new work, and rows are lightweight with append-only
//      stable identity.
//

import SwiftUI
import AppKit
import os.signpost

struct PreviewPane: View {
    let file: QueuedFile?

    @State private var justCopied = false
    @State private var streamed: StreamedContent?
    @State private var unreadableURL: URL?
    @State private var showFullOutput = false

    /// "rendered" or "raw" — remembered across launches.
    @AppStorage("previewRenderMode") private var previewMode = "rendered"

    /// Display cap. The full content always stays in the output file and
    /// is what Copy copies; "Show full output" lifts the cap on demand.
    private static let previewCharacterCap = 50_000

    /// Measures selection → first visible content. The category must be
    /// pointsOfInterest — that's the only signpost track the stock
    /// Time Profiler template records. Free when nobody is profiling.
    private static let signposter = OSSignposter(
        subsystem: "com.rakan.Distill", category: .pointsOfInterest
    )

    /// Grows batch by batch on the main actor; rows are append-only so
    /// ForEach identity stays stable while it streams.
    private struct StreamedContent {
        let outputURL: URL
        var blocks: [MarkdownBlock] = []
        var rawChunks: [String] = []
        var isTruncated = false
        var isComplete = false
    }

    var body: some View {
        if let file {
            switch file.status {
            case .done(let outputURL):
                doneView(outputURL: outputURL)
                    .task(id: TaskKey(url: outputURL, full: showFullOutput)) {
                        await load(outputURL: outputURL, full: showFullOutput)
                    }
                    .onChange(of: file.id) {
                        showFullOutput = false
                    }
            case .converting:
                ProgressView("Converting…")
            case .pending:
                ContentUnavailableView(
                    "Not Converted Yet",
                    systemImage: "clock",
                    description: Text("Click Convert to process the queue.")
                )
            case .failed(let reason):
                ContentUnavailableView(
                    "Conversion Failed",
                    systemImage: "exclamationmark.triangle",
                    description: Text(reason)
                )
            }
        } else {
            ContentUnavailableView(
                "No File Selected",
                systemImage: "doc.text.magnifyingglass",
                description: Text("Convert files, then select one to see its Markdown.")
            )
        }
    }

    private struct TaskKey: Equatable {
        let url: URL
        let full: Bool
    }

    @ViewBuilder
    private func doneView(outputURL: URL) -> some View {
        if let unreadableURL {
            ContentUnavailableView(
                "Preview Unavailable",
                systemImage: "doc.questionmark",
                description: Text("The converted file couldn't be read back from \(unreadableURL.path)")
            )
        } else if let streamed, streamed.outputURL == outputURL {
            markdownPreview(streamed)
        } else {
            ProgressView("Loading preview…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Streaming load

    @MainActor
    private func load(outputURL: URL, full: Bool) async {
        // Cheap teardown first: empty the old tree in one transaction
        // before any parsing begins.
        streamed = nil
        unreadableURL = nil

        let signpostID = Self.signposter.makeSignpostID()
        let interval = Self.signposter.beginInterval("PreviewFirstPaint", id: signpostID)
        var firstBatchPending = true
        func markFirstPaint() {
            if firstBatchPending {
                Self.signposter.endInterval("PreviewFirstPaint", interval)
                firstBatchPending = false
            }
        }

        let cap = full ? nil : Self.previewCharacterCap
        for await event in Self.contentStream(outputURL: outputURL, cap: cap) {
            // Stale batches from a deselected file must never apply.
            if Task.isCancelled { break }
            switch event {
            case .unreadable:
                unreadableURL = outputURL
                markFirstPaint()
            case .begin(let truncated):
                streamed = StreamedContent(outputURL: outputURL, isTruncated: truncated)
            case .batch(let blocks, let chunks):
                streamed?.blocks.append(contentsOf: blocks)
                streamed?.rawChunks.append(contentsOf: chunks)
                markFirstPaint()
            case .complete:
                streamed?.isComplete = true
                markFirstPaint()   // e.g. an empty document
            }
        }
        markFirstPaint()
    }

    private nonisolated enum PreviewEvent: Sendable {
        case unreadable
        case begin(truncated: Bool)
        case batch(blocks: [MarkdownBlock], chunks: [String])
        case complete
    }

    /// Background producer: reads the file, walks it line by line with a
    /// cursor (no up-front whole-document split), and yields parsed
    /// blocks + raw chunks in batches — a small first batch for fast
    /// first paint, larger ones after. Cancels promptly: the consumer's
    /// termination cancels the producer task, which also checks
    /// `Task.isCancelled` between batches.
    private nonisolated static func contentStream(outputURL: URL, cap: Int?) -> AsyncStream<PreviewEvent> {
        AsyncStream { continuation in
            let producer = Task.detached(priority: .userInitiated) {
                guard let fullText = try? String(contentsOf: outputURL, encoding: .utf8) else {
                    continuation.yield(.unreadable)
                    continuation.finish()
                    return
                }

                let text: Substring
                let truncated: Bool
                if let cap, fullText.count > cap {
                    text = fullText.prefix(cap)
                    truncated = true
                } else {
                    text = fullText[...]
                    truncated = false
                }
                continuation.yield(.begin(truncated: truncated))

                let parser = MarkdownBlockParser()
                var chunker = LineChunker()
                var batch: [String] = []
                var isFirstBatch = true
                var cursor = text.startIndex

                func flush(final: Bool) {
                    var blocks = parser.feed(lines: batch)
                    var chunks = chunker.feed(lines: batch)
                    batch = []
                    if final {
                        blocks += parser.finish()
                        chunks += chunker.finish()
                        if truncated {
                            chunks.append("\n… preview capped — use “Show full output” below, or Copy for everything.")
                        }
                    }
                    if !blocks.isEmpty || !chunks.isEmpty {
                        continuation.yield(.batch(blocks: blocks, chunks: chunks))
                    }
                }

                while cursor < text.endIndex {
                    if Task.isCancelled {
                        continuation.finish()
                        return
                    }
                    let lineEnd = text[cursor...].firstIndex(of: "\n") ?? text.endIndex
                    batch.append(String(text[cursor..<lineEnd]))
                    cursor = lineEnd < text.endIndex ? text.index(after: lineEnd) : text.endIndex

                    if batch.count >= (isFirstBatch ? 60 : 2000) {
                        flush(final: false)
                        isFirstBatch = false
                    }
                }
                flush(final: true)
                continuation.yield(.complete)
                continuation.finish()
            }
            continuation.onTermination = { _ in producer.cancel() }
        }
    }

    /// Incremental version of the raw-view chunking: ~1.5 KB pieces cut
    /// at line boundaries (tables have no blank lines, so line-based
    /// cutting is what keeps giant tables from becoming one glyph layer).
    private nonisolated struct LineChunker {
        private var current = ""
        private let targetSize = 1500

        mutating func feed(lines: [String]) -> [String] {
            var out: [String] = []
            for line in lines {
                if !current.isEmpty && current.count + line.count + 1 > targetSize {
                    out.append(current)
                    current = line
                } else {
                    current = current.isEmpty ? line : current + "\n" + line
                }
            }
            return out
        }

        mutating func finish() -> [String] {
            defer { current = "" }
            return current.isEmpty ? [] : [current]
        }
    }

    @concurrent
    private nonisolated static func readFullOutput(at url: URL) async -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - Loaded layout

    private func markdownPreview(_ preview: StreamedContent) -> some View {
        VStack(spacing: 0) {
            // Header: where the file went + actions.
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(preview.outputURL.lastPathComponent)
                            .font(.headline)
                        if let tokens = file?.formattedTokenEstimate {
                            Text(tokens)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.quaternary, in: Capsule())
                                .help("Estimated from content type (~4 chars/token prose, ~3 code, ~1.3 CJK)")
                        }
                        if !preview.isComplete {
                            ProgressView()
                                .controlSize(.small)
                                .help("Still rendering the rest of the document")
                        }
                    }
                    Text(preview.outputURL.deletingLastPathComponent().path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()

                Picker("View", selection: $previewMode) {
                    Text("Rendered").tag("rendered")
                    Text("Raw").tag("raw")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Rendered Markdown, or the raw text that was saved")

                Button {
                    copyFullOutput(preview)
                } label: {
                    Label(justCopied ? "Copied" : "Copy",
                          systemImage: justCopied ? "checkmark" : "doc.on.doc")
                }
                .help("Copy the complete Markdown to the clipboard")

                Button {
                    NSWorkspace.shared.open(preview.outputURL)
                } label: {
                    Label("Open", systemImage: "arrow.up.forward.app")
                }
                .help("Open the .md file in your default editor")
            }
            .padding(10)

            Divider()

            if previewMode == "rendered" {
                RenderedMarkdownView(blocks: preview.blocks)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(preview.rawChunks.indices, id: \.self) { index in
                            Text(preview.rawChunks[index])
                                .font(.system(.body, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .textSelection(.enabled)
                    .padding(12)
                }
                .background(.background)
            }

            if preview.isTruncated {
                Divider()
                HStack {
                    Label("Large document — preview shows the first \(Self.previewCharacterCap / 1000) K characters",
                          systemImage: "text.badge.minus")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Show full output") {
                        showFullOutput = true
                    }
                    .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.bar)
            }
        }
    }

    /// Copy always delivers the *complete* document, not the capped
    /// preview — read back from disk off the main actor.
    private func copyFullOutput(_ preview: StreamedContent) {
        Task {
            let text = await Self.readFullOutput(at: preview.outputURL)
                ?? preview.rawChunks.joined(separator: "\n")
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)

            justCopied = true
            try? await Task.sleep(for: .seconds(1.5))
            justCopied = false
        }
    }
}
