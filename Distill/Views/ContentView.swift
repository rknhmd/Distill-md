//
//  ContentView.swift
//  Distill
//
//  The main window: file queue on the left, Markdown preview on the
//  right, drop-anywhere support, and a status bar along the bottom.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppModel.self) private var model

    @State private var isDropTargeted = false
    @State private var isImporterPresented = false

    @AppStorage(AppSettings.outputModeKey)
    private var outputModeRaw = AppSettings.OutputMode.alongsideSource.rawValue

    @AppStorage(AppSettings.customFolderPathKey)
    private var customFolderPath = ""

    var body: some View {
        // @Bindable lets us make bindings ($model.…) into the @Observable
        // model — needed for the List selection.
        @Bindable var model = model

        NavigationSplitView {
            List(selection: $model.selectedFileID) {
                ForEach(model.files) { file in
                    FileRowView(file: file)
                        .tag(file.id)
                        .contextMenu { contextMenu(for: file) }
                }
            }
            .overlay {
                if model.files.isEmpty { emptyState }
            }
            .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 480)
        } detail: {
            PreviewPane(file: model.selectedFile)
        }
        .navigationTitle("Distill")
        // Dropping works anywhere in the window, not just the sidebar.
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .overlay { if isDropTargeted { dropHighlight } }
        .toolbar { toolbarContent }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: Self.importableTypes,
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                model.addFiles(urls)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { statusBar }
    }

    /// .text covers txt/md/csv already, but listing the specific types
    /// keeps the open panel's enabled-files behavior predictable. The
    /// Office types have no UTType constants; they're looked up by
    /// extension (nil on systems that somehow don't know them — hence
    /// compactMap).
    private static let importableTypes: [UTType] = [
        .pdf, .plainText, .text, .html, .commaSeparatedText, .tabSeparatedText, .rtf,
    ] + ["docx", "pptx", "xlsx", "doc"].compactMap { UTType(filenameExtension: $0) }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                isImporterPresented = true
            } label: {
                Label("Add Files…", systemImage: "plus")
            }
            .help("Add files to the queue (or just drop them anywhere)")

            Button {
                model.clearQueue()
            } label: {
                Label("Clear", systemImage: "trash")
            }
            .help("Remove all files from the queue")
            .disabled(model.files.isEmpty || model.isConverting)

            Button {
                model.convertAll()
            } label: {
                Label("Convert", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: .command)
            .help("Convert all pending files (⌘↩)")
            .disabled(model.pendingCount == 0 || model.isConverting)
        }
    }

    // MARK: - Row context menu

    @ViewBuilder
    private func contextMenu(for file: QueuedFile) -> some View {
        if case .done(let outputURL) = file.status {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([outputURL])
            }
            Button("Convert Again") { model.requeue(id: file.id) }
                .disabled(model.isConverting)
        }
        if case .failed = file.status {
            Button("Retry") { model.requeue(id: file.id) }
                .disabled(model.isConverting || file.type == nil)
        }
        Button("Remove", role: .destructive) { model.removeFile(id: file.id) }
            .disabled(model.isConverting)
    }

    // MARK: - Empty & drop states

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Drop Files Here", systemImage: "arrow.down.doc")
        } description: {
            Text("PDF · TXT · MD · CSV · TSV · HTML")
        } actions: {
            Button("Add Files…") { isImporterPresented = true }
        }
    }

    private var dropHighlight: some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
            .foregroundStyle(.tint)
            .background(
                RoundedRectangle(cornerRadius: 12).fill(.tint.opacity(0.08))
            )
            .overlay {
                Label("Drop to add to the queue", systemImage: "plus.circle.fill")
                    .font(.title3)
                    .padding(10)
                    .background(.regularMaterial, in: Capsule())
            }
            .padding(10)
            // Let the drop fall through to the onDrop modifier underneath.
            .allowsHitTesting(false)
    }

    // MARK: - Status bar

    private var statusBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
            Text(outputDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            if let flash = model.statusFlash {
                Label(flash, systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
                    .transition(.opacity)
            } else if model.isConverting {
                ProgressView(value: Double(model.runCompleted), total: Double(model.runTotal))
                    .frame(width: 140)
                Text("Converting \(min(model.runCompleted + 1, model.runTotal)) of \(model.runTotal)…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else if !model.files.isEmpty {
                Text(queueSummary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var outputDescription: String {
        if outputModeRaw == AppSettings.OutputMode.customFolder.rawValue {
            if customFolderPath.isEmpty {
                return "No output folder chosen — pick one in Settings (⌘,)"
            }
            return "Saving to \((customFolderPath as NSString).abbreviatingWithTildeInPath)"
        }
        return "Saving next to the original files"
    }

    private var queueSummary: String {
        var parts: [String] = []
        if model.pendingCount > 0 { parts.append("\(model.pendingCount) pending") }
        if model.doneCount > 0 { parts.append("\(model.doneCount) converted") }
        if model.failedCount > 0 { parts.append("\(model.failedCount) failed") }
        return parts.isEmpty ? "\(model.files.count) files" : parts.joined(separator: " · ")
    }

    // MARK: - Drop handling

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            accepted = true
            // loadItem's completion runs on a background queue; capture the
            // (Sendable, MainActor) model and hop back to add the file.
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [model] item, _ in
                var url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let itemURL = item as? URL {
                    url = itemURL
                }
                guard let url, url.isFileURL else { return }
                Task { @MainActor in
                    model.addFiles([url])
                }
            }
        }
        return accepted
    }
}

#Preview {
    ContentView()
        .environment(AppModel())
}
