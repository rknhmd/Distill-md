//
//  PreviewPane.swift
//  Distill
//
//  The right-hand side of the window: shows the converted Markdown for
//  the selected file, with Copy and Open buttons. (Rendered — as opposed
//  to raw — Markdown preview is a Phase 3 item.)
//

import SwiftUI
import AppKit

struct PreviewPane: View {
    let file: QueuedFile?

    @State private var justCopied = false

    /// "rendered" or "raw" — remembered across launches.
    @AppStorage("previewRenderMode") private var previewMode = "rendered"

    /// Very large documents make SwiftUI's Text layout crawl; the preview
    /// is capped and the full content still lives in the output file.
    private static let previewCharacterLimit = 120_000

    var body: some View {
        if let file {
            switch file.status {
            case .done(let outputURL):
                if let markdown = file.markdown {
                    markdownPreview(markdown: markdown, outputURL: outputURL)
                } else {
                    // Shouldn't happen (done ⇒ markdown kept), but never
                    // show a blank pane if it somehow does.
                    ContentUnavailableView(
                        "Preview Unavailable",
                        systemImage: "doc.questionmark",
                        description: Text("The converted file is at \(outputURL.path)")
                    )
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

    // MARK: - The actual preview

    private func markdownPreview(markdown: String, outputURL: URL) -> some View {
        VStack(spacing: 0) {
            // Header: where the file went + actions.
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(outputURL.lastPathComponent)
                            .font(.headline)
                        if let tokens = file?.formattedTokenEstimate {
                            Text(tokens)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.quaternary, in: Capsule())
                                .help("Estimated as characters ÷ 4 — the usual quick approximation of LLM (BPE) tokens")
                        }
                    }
                    Text(outputURL.deletingLastPathComponent().path)
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
                    copyToClipboard(markdown)
                } label: {
                    Label(justCopied ? "Copied" : "Copy",
                          systemImage: justCopied ? "checkmark" : "doc.on.doc")
                }
                .help("Copy the Markdown to the clipboard")

                Button {
                    NSWorkspace.shared.open(outputURL)
                } label: {
                    Label("Open", systemImage: "arrow.up.forward.app")
                }
                .help("Open the .md file in your default editor")
            }
            .padding(10)

            Divider()

            if previewMode == "rendered" {
                RenderedMarkdownView(markdown: previewText(for: markdown))
            } else {
                ScrollView {
                    Text(previewText(for: markdown))
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .background(.background)
            }
        }
    }

    private func previewText(for markdown: String) -> String {
        guard markdown.count > Self.previewCharacterLimit else { return markdown }
        return markdown.prefix(Self.previewCharacterLimit)
            + "\n\n… preview truncated — the full document is in the saved file."
    }

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Flash "Copied" on the button for a moment.
        justCopied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            justCopied = false
        }
    }
}
