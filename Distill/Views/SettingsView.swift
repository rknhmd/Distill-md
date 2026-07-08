//
//  SettingsView.swift
//  Distill
//
//  The Settings window (⌘,). Everything here persists via @AppStorage,
//  which reads/writes the same UserDefaults keys the services use.
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    @AppStorage(AppSettings.outputModeKey)
    private var outputModeRaw = AppSettings.OutputMode.alongsideSource.rawValue

    @AppStorage(AppSettings.customFolderPathKey)
    private var customFolderPath = ""

    @AppStorage(AppSettings.autoCopyKey)
    private var autoCopyToClipboard = false

    @AppStorage(AppSettings.includeFrontMatterKey)
    private var includeFrontMatter = false

    @AppStorage(AppSettings.extractImagesKey)
    private var extractImages = false

    @AppStorage(AppSettings.watchFolderEnabledKey)
    private var watchFolderEnabled = false

    @AppStorage(AppSettings.watchFolderPathKey)
    private var watchFolderPath = ""

    var body: some View {
        Form {
            Section("Output") {
                Picker("Save converted Markdown:", selection: $outputModeRaw) {
                    ForEach(AppSettings.OutputMode.allCases) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.radioGroup)

                if outputModeRaw == AppSettings.OutputMode.customFolder.rawValue {
                    LabeledContent("Folder:") {
                        HStack(spacing: 8) {
                            Text(displayPath)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(customFolderPath.isEmpty ? .secondary : .primary)
                            Button("Choose…") {
                                if let url = FolderAccessManager.shared.chooseCustomOutputFolder() {
                                    customFolderPath = url.path
                                }
                            }
                        }
                    }
                }

                Toggle("Include metadata header", isOn: $includeFrontMatter)
                Text("Prepends YAML front matter (source, date, format, pages, tokens) to converted files. Markdown inputs that already have front matter keep their own.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Extract embedded images", isOn: $extractImages)
                Text("Saves images from Word, PowerPoint, and PDF files into a “name-assets” folder next to the Markdown, linked in place. Identical images are stored once.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Clipboard") {
                Toggle("Copy result to clipboard after converting a single file",
                       isOn: $autoCopyToClipboard)
                Text("Applies when exactly one file is converted at a time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Watch Folder") {
                Toggle("Automatically convert files added to a folder",
                       isOn: $watchFolderEnabled)
                    .onChange(of: watchFolderEnabled) {
                        model.watchFolder.applySettings()
                    }

                if watchFolderEnabled {
                    LabeledContent("Folder:") {
                        HStack(spacing: 8) {
                            Text(watchDisplayPath)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(watchFolderPath.isEmpty ? .secondary : .primary)
                            Button("Choose…") {
                                if let url = FolderAccessManager.shared.chooseWatchFolder() {
                                    watchFolderPath = url.path
                                    model.watchFolder.applySettings()
                                }
                            }
                        }
                    }
                    Text("Runs while Distill is open. Markdown files in the folder are skipped, so converted output doesn't re-convert.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize()
    }

    private var displayPath: String {
        if customFolderPath.isEmpty { return "No folder chosen" }
        return (customFolderPath as NSString).abbreviatingWithTildeInPath
    }

    private var watchDisplayPath: String {
        if watchFolderPath.isEmpty { return "No folder chosen" }
        return (watchFolderPath as NSString).abbreviatingWithTildeInPath
    }
}

#Preview {
    SettingsView()
}
