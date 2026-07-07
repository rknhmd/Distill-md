//
//  DistillApp.swift
//  Distill
//
//  App entry point: the main window plus the standard Settings scene (⌘,).
//

import SwiftUI

@main
struct DistillApp: App {

    /// One shared model for the whole app, injected into the environment.
    /// @State keeps it alive for the app's lifetime.
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .frame(minWidth: 720, minHeight: 420)
        }
        .defaultSize(width: 940, height: 560)

        Settings {
            SettingsView()
        }
    }
}
