//
//  AboutView.swift
//  Distill
//
//  A small custom About window (the standard one can't show a tagline
//  or layout of our choosing). Opened via Distill → About Distill.
//

import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)

            Text("Distill.md")
                .font(.title.bold())

            Text("Version \(Self.version)")
                .font(.callout)
                .foregroundStyle(.secondary)

            Text("Documents in. AI-ready Markdown out.")
                .font(.callout)
                .padding(.top, 2)

            Divider()
                .padding(.vertical, 4)

            Text("Made by Rakan Hamadeh")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("PDF · Word · PowerPoint · Excel · HTML · CSV · ZIP — fully on-device")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(width: 320)
    }

    private static var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}

#Preview {
    AboutView()
}
