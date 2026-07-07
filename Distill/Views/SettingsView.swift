//
//  SettingsView.swift
//  Distill
//
//  The Settings window (⌘,). Everything here persists via @AppStorage,
//  which reads/writes the same UserDefaults keys the services use.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage(AppSettings.outputModeKey)
    private var outputModeRaw = AppSettings.OutputMode.alongsideSource.rawValue

    @AppStorage(AppSettings.customFolderPathKey)
    private var customFolderPath = ""

    @AppStorage(AppSettings.autoCopyKey)
    private var autoCopyToClipboard = false

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
            }

            Section("Clipboard") {
                Toggle("Copy result to clipboard after converting a single file",
                       isOn: $autoCopyToClipboard)
                Text("Applies when exactly one file is converted at a time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
}

#Preview {
    SettingsView()
}
