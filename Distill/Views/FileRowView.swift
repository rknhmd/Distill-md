//
//  FileRowView.swift
//  Distill
//
//  One row in the queue: type icon, name, size, and a status indicator.
//

import SwiftUI

struct FileRowView: View {
    let file: QueuedFile

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: file.type?.symbolName ?? "questionmark.square.dashed")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.fileName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                subtitle
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 8)

            statusIndicator
        }
        .padding(.vertical, 3)
        .help(helpText)
    }

    /// Second line: normally "type · size" (plus the token estimate once
    /// converted); when something went wrong the reason is more useful
    /// than the size, so it takes over the line.
    @ViewBuilder
    private var subtitle: some View {
        switch file.status {
        case .failed(let reason):
            Text(reason).foregroundStyle(.orange)
        default:
            let base = "\(file.type?.displayName ?? "Unknown") · \(file.formattedSize)"
            if let tokens = file.formattedTokenEstimate {
                Text("\(base) · \(tokens)").foregroundStyle(.secondary)
            } else {
                Text(base).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch file.status {
        case .pending:
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
        case .converting:
            ProgressView()
                .controlSize(.small)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    /// Tooltip with the full story (file names and reasons get truncated
    /// in the row itself).
    private var helpText: String {
        switch file.status {
        case .pending: "\(file.fileName) — waiting to convert"
        case .converting: "\(file.fileName) — converting…"
        case .done(let url): "Saved to \(url.path)"
        case .failed(let reason): "\(file.fileName) — \(reason)"
        }
    }
}
