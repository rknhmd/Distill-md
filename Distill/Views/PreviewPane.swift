//
//  PreviewPane.swift
//  Distill
//
//  The right-hand side of the window: shows the converted Markdown for
//  the selected file, with Copy and Open buttons.
//
//  Performance shape (v2.0.1 fix 1): the queue model holds only the
//  output *path*. Selecting a file loads and parses its Markdown on a
//  background task, and only the first ~50 KB is displayed unless the
//  user asks for the full output — big documents previously produced
//  multi-second main-thread hangs (GraphHost.flushTransactions) here.
//

import SwiftUI
import AppKit

struct PreviewPane: View {
    let file: QueuedFile?

    @State private var justCopied = false
    @State private var previewState: PreviewState = .idle
    @State private var showFullOutput = false

    /// "rendered" or "raw" — remembered across launches.
    @AppStorage("previewRenderMode") private var previewMode = "rendered"

    /// Display cap. The full content always stays in the output file and
    /// is what Copy copies; "Show full output" lifts the cap on demand.
    private static let previewCharacterCap = 50_000

    /// Everything the pane needs, produced off the main actor —
    /// `nonisolated` so the @concurrent loader can construct it there.
    private nonisolated struct LoadedPreview: Sendable {
        let outputURL: URL
        let displayText: String
        let blocks: [MarkdownBlock]
        let isTruncated: Bool
    }

    private enum PreviewState {
        case idle
        case loading
        case loaded(LoadedPreview)
        case unreadable(URL)
    }

    var body: some View {
        if let file {
            switch file.status {
            case .done(let outputURL):
                previewContainer(outputURL: outputURL)
                    // Reload when the selection or the cap changes. The id
                    // ties the task to both, and SwiftUI cancels the old
                    // task automatically on change.
                    .task(id: TaskKey(url: outputURL, full: showFullOutput)) {
                        previewState = .loading
                        let cap = showFullOutput ? nil : Self.previewCharacterCap
                        if let loaded = await Self.loadPreview(outputURL: outputURL, cap: cap) {
                            previewState = .loaded(loaded)
                        } else {
                            previewState = .unreadable(outputURL)
                        }
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

    private nonisolated struct TaskKey: Equatable, Sendable {
        let url: URL
        let full: Bool
    }

    // MARK: - Background loading

    /// Reads the output file and parses the display portion into blocks,
    /// entirely off the main actor (@concurrent forces the hop).
    @concurrent
    private nonisolated static func loadPreview(outputURL: URL, cap: Int?) async -> LoadedPreview? {
        guard let full = try? String(contentsOf: outputURL, encoding: .utf8) else { return nil }

        let isTruncated: Bool
        let displayText: String
        if let cap, full.count > cap {
            isTruncated = true
            displayText = String(full.prefix(cap))
                + "\n\n… preview capped — use “Show full output” below, or Copy for everything."
        } else {
            isTruncated = false
            displayText = full
        }

        return LoadedPreview(
            outputURL: outputURL,
            displayText: displayText,
            blocks: MarkdownBlock.parse(displayText),
            isTruncated: isTruncated
        )
    }

    @concurrent
    private nonisolated static func readFullOutput(at url: URL) async -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - Loaded layout

    @ViewBuilder
    private func previewContainer(outputURL: URL) -> some View {
        switch previewState {
        case .idle, .loading:
            ProgressView("Loading preview…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .unreadable(let url):
            ContentUnavailableView(
                "Preview Unavailable",
                systemImage: "doc.questionmark",
                description: Text("The converted file couldn't be read back from \(url.path)")
            )
        case .loaded(let preview):
            markdownPreview(preview)
        }
    }

    private func markdownPreview(_ preview: LoadedPreview) -> some View {
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
                    Text(preview.displayText)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
    private func copyFullOutput(_ preview: LoadedPreview) {
        Task {
            let text = await Self.readFullOutput(at: preview.outputURL) ?? preview.displayText
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)

            justCopied = true
            try? await Task.sleep(for: .seconds(1.5))
            justCopied = false
        }
    }
}
