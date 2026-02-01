import SwiftUI

struct ConnectionRowView: View {
    let connection: DBConnection
    let status: ConnectionStatus
    let validationIssues: [ValidationIssue]
    let isOperationPending: Bool
    let onToggle: () -> Void

    @State private var isHovering = false

    private var hasValidationErrors: Bool {
        validationIssues.contains { $0.isError }
    }

    private var isDisabled: Bool {
        hasValidationErrors || isOperationPending
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

    /// Primary validation error message for inline display
    private var primaryErrorMessage: String? {
        validationIssues.first { $0.isError }?.message
    }

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 10) {
                StatusIndicator(status: status)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(connection.name)
                            .font(.system(.body, weight: .medium))
                            .strikethrough(hasValidationErrors, color: .red.opacity(0.5))

                        if hasValidationErrors {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.body)
                                .foregroundStyle(.red)
                                .help(validationTooltip)
                        } else if hasValidationWarnings {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .help(validationTooltip)
                        }
                    }

                    if let errorMessage = primaryErrorMessage {
                        // Show validation error inline for visibility
                        Text(errorMessage)
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .lineLimit(1)
                    } else {
                        Text(connection.displayPort)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if connection.autoConnect && !hasValidationErrors {
                    Image(systemName: "autostartstop")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help("Auto-connects on launch")
                }

                statusLabel
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                hasValidationErrors
                    ? Color.red.opacity(0.08)
                    : (isHovering ? Color.primary.opacity(0.05) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1.0)
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
            case .error:
                Text("Retry")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }
}
