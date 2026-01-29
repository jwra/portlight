import SwiftUI

struct ConnectionRowView: View {
    let connection: DBConnection
    let status: ConnectionStatus
    let validationIssues: [ValidationIssue]
    let onToggle: () -> Void

    @State private var isHovering = false

    private var hasValidationErrors: Bool {
        validationIssues.contains { $0.isError }
    }

    private var hasValidationWarnings: Bool {
        validationIssues.contains { !$0.isError }
    }

    private var validationTooltip: String {
        validationIssues.map { issue in
            let prefix = issue.isError ? "Error" : "Warning"
            return "\(prefix): \(issue.message)"
        }.joined(separator: "\n")
    }

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 10) {
                StatusIndicator(status: status)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(connection.name)
                            .font(.system(.body, weight: .medium))

                        if hasValidationErrors {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                                .help(validationTooltip)
                        } else if hasValidationWarnings {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .help(validationTooltip)
                        }
                    }

                    Text(connection.displayPort)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if connection.autoConnect {
                    Image(systemName: "autostartstop")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help("Auto-connects on launch")
                }

                statusLabel
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isHovering ? Color.primary.opacity(0.05) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(hasValidationErrors)
        .opacity(hasValidationErrors ? 0.6 : 1.0)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        if hasValidationErrors {
            Text("Invalid")
                .font(.caption)
                .foregroundStyle(.red)
        } else {
            switch status {
            case .disconnected:
                Text("Connect")
                    .font(.caption)
                    .foregroundStyle(.blue)
            case .connecting:
                Text("Connecting...")
                    .font(.caption)
                    .foregroundStyle(.orange)
            case .connected:
                Text("Disconnect")
                    .font(.caption)
                    .foregroundStyle(.red)
            case .error(let message):
                Text("Error")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .help(message)
            }
        }
    }
}
