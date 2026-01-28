import SwiftUI

struct ConnectionRowView: View {
    let connection: DBConnection
    let status: ConnectionStatus
    let onToggle: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 10) {
                StatusIndicator(status: status)

                VStack(alignment: .leading, spacing: 2) {
                    Text(connection.name)
                        .font(.system(.body, weight: .medium))

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
        .onHover { hovering in
            isHovering = hovering
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
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
