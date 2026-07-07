//
//  AppSettings.swift
//  Distill
//
//  Central home for the persisted settings: the UserDefaults keys (shared
//  by @AppStorage in views and direct reads in services) and typed
//  accessors so the rest of the code never deals in raw strings.
//

import Foundation

nonisolated enum AppSettings {

    // Keys — referenced by @AppStorage in SettingsView and read here.
    static let outputModeKey = "outputMode"
    static let customFolderPathKey = "customOutputFolderPath"
    static let customFolderBookmarkKey = "customOutputFolderBookmark"
    static let grantedBookmarksKey = "grantedFolderBookmarks"
    static let autoCopyKey = "autoCopyToClipboard"

    /// Where converted files are saved.
    enum OutputMode: String, CaseIterable, Identifiable {
        /// The .md file lands in the same folder as the original.
        case alongsideSource
        /// Everything goes to one folder the user picked in Settings.
        case customFolder

        var id: String { rawValue }

        var label: String {
            switch self {
            case .alongsideSource: "Next to the original file"
            case .customFolder: "A single folder I choose"
            }
        }
    }

    static var outputMode: OutputMode {
        let raw = UserDefaults.standard.string(forKey: outputModeKey) ?? ""
        return OutputMode(rawValue: raw) ?? .alongsideSource
    }

    static var customFolderPath: String? {
        guard let path = UserDefaults.standard.string(forKey: customFolderPathKey),
              !path.isEmpty else { return nil }
        return path
    }

    static var autoCopyToClipboard: Bool {
        UserDefaults.standard.bool(forKey: autoCopyKey)
    }
}
