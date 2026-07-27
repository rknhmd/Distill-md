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

    /// Receives files opened from Finder / the Quick Action extension.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .frame(minWidth: 720, minHeight: 420)
                .onAppear {
                    // Connect the delegate to the model (releases any
                    // files that arrived before the UI was up).
                    appDelegate.model = model
                }
        }
        .defaultSize(width: 940, height: 560)
        .commands {
            // Our own About window instead of the system one.
            CommandGroup(replacing: .appInfo) {
                Button("About Distill.md") { openWindow(id: "about") }
            }
            // File menu: ⌘N makes no sense here; ⌘O adds files.
            CommandGroup(replacing: .newItem) {
                Button("Add Files…") { model.presentOpenPanel() }
                    .keyboardShortcut("o", modifiers: .command)
                Divider()
                Button("Convert All") { model.convertAll() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(model.pendingCount == 0 || model.isConverting)
            }
            // Edit menu: rich clipboard content → Markdown, in place.
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Convert Clipboard to Markdown") { model.convertClipboard() }
                    .keyboardShortcut("v", modifiers: [.command, .shift])
            }
        }

        Window("About Distill.md", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}
