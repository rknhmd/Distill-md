//
//  ContentView.swift
//  Distill
//
//  The main window: file queue on the left, Markdown preview on the
//  right, drop-anywhere support, and a status bar along the bottom.
//

import SwiftUI
import DistillCore
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppModel.self) private var model

    @State private var isDropTargeted = false
    @State private var isImporterPresented = false
    @State private var isClearConfirmationPresented = false

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
        .navigationTitle("Distill.md")
        // Dropping works anywhere in the window, not just the sidebar.
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .overlay { if isDropTargeted { dropHighlight } }
        .toolbar { toolbarContent }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: FileType.importableUTTypes,
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                model.addFiles(urls)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { statusBar }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Clear sits in its own group, away from "+" — an accidental
        // click can't wipe the session anyway: it asks first.
        ToolbarItem {
            Button {
                isClearConfirmationPresented = true
            } label: {
                Label("Clear", systemImage: "trash")
            }
            .help("Remove all files from the queue…")
            .disabled(model.files.isEmpty || model.isConverting)
            .confirmationDialog(
                "Remove all \(model.files.count) files from the queue?",
                isPresented: $isClearConfirmationPresented
            ) {
                Button("Clear Queue", role: .destructive) { model.clearQueue() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Converted Markdown files on disk are not affected.")
            }
        }

        ToolbarItemGroup {
            Button {
                isImporterPresented = true
            } label: {
                Label("Add Files…", systemImage: "plus")
            }
            .help("Add files to the queue (or just drop them anywhere)")

            // The app's primary action: a labeled prominent button, not
            // an icon that reads as media playback.
            Button("Convert All") {
                model.convertAll()
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
            Text("PDF · Word · PowerPoint · Excel · CSV · HTML · ZIP & more")
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
            // The destination readout is a control: click to override the
            // output location for this session only (Settings keeps the
            // persistent default; next launch returns to it).
            outputLocationMenu

            if model.watchFolder.isWatching, let name = model.watchFolder.watchedFolderName {
                Label("Watching “\(name)”", systemImage: "binoculars")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .help("New files in this folder are converted automatically (Settings → Watch Folder)")
            }

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

    /// Effective destination, derived from the reactive @AppStorage
    /// defaults plus the observable session override — so both Settings
    /// changes and override changes refresh the status bar.
    private var effectiveOutput: (text: String, isOverride: Bool) {
        if let override = model.sessionOutputOverride {
            switch override {
            case .alongsideSource:
                return ("Saving next to the original files — this session", true)
            case .folder(let url):
                return ("Saving to \((url.path as NSString).abbreviatingWithTildeInPath) — this session", true)
            }
        }
        if outputModeRaw == AppSettings.OutputMode.customFolder.rawValue {
            if customFolderPath.isEmpty {
                return ("No output folder chosen — pick one in Settings (⌘,)", false)
            }
            return ("Saving to \((customFolderPath as NSString).abbreviatingWithTildeInPath)", false)
        }
        return ("Saving next to the original files", false)
    }

    private var outputLocationMenu: some View {
        let effective = effectiveOutput
        return Menu {
            Button("Next to original files") {
                // Picking the value that equals the default just means
                // "use the default" — no phantom override.
                if outputModeRaw == AppSettings.OutputMode.alongsideSource.rawValue {
                    model.sessionOutputOverride = nil
                } else {
                    model.sessionOutputOverride = .alongsideSource
                }
            }
            Button("Choose folder for this session…") {
                if let url = FolderAccessManager.shared.chooseSessionFolder() {
                    model.sessionOutputOverride = .folder(url)
                }
            }
            if model.sessionOutputOverride != nil {
                Divider()
                Button("Reset to default") {
                    model.sessionOutputOverride = nil
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: effective.isOverride ? "folder.badge.gearshape" : "folder")
                Text(effective.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .font(.callout)
            .foregroundStyle(effective.isOverride ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Where converted Markdown is saved. Click to override for this session; the default lives in Settings (⌘,).")
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
