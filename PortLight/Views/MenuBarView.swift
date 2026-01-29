import SwiftUI

struct MenuBarView: View {
    @Bindable var manager: ConnectionManager

    private var validationResult: ConfigValidationResult? {
        manager.configManager.lastValidationResult
    }

    private var hasValidationErrors: Bool {
        validationResult?.isValid == false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if hasValidationErrors {
                validationBanner
                Divider()
            }
            connectionsList
            Divider()
            actions
            Divider()
            quitButton
        }
        .frame(width: 280)
        .onAppear {
            manager.setup()
        }
    }

    @ViewBuilder
    private var validationBanner: some View {
        let errorCount = validationResult?.allErrors.count ?? 0
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Config has \(errorCount) error\(errorCount == 1 ? "" : "s")")
                    .font(.system(.caption, weight: .medium))
                Text("Edit config to fix")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Edit") {
                manager.openConfig()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.1))
    }

    @ViewBuilder
    private var connectionsList: some View {
        if manager.config.connections.isEmpty {
            Text("No connections configured")
                .foregroundStyle(.secondary)
                .padding()
        } else {
            ForEach(manager.config.connections) { connection in
                let connectionIssues = validationResult?.issues(for: connection.id) ?? []
                ConnectionRowView(
                    connection: connection,
                    status: manager.status(for: connection),
                    validationIssues: connectionIssues,
                    onToggle: { manager.toggle(connection) }
                )
            }
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 0) {
            MenuButton(title: "Reload Config", icon: "arrow.clockwise") {
                manager.reloadConfig()
            }

            MenuButton(title: "Edit Config...", icon: "pencil") {
                manager.openConfig()
            }

            MenuButton(title: "Reveal Config in Finder", icon: "folder") {
                manager.revealConfig()
            }

            if manager.hasActiveConnections {
                MenuButton(title: "Disconnect All", icon: "xmark.circle") {
                    manager.disconnectAll()
                }
            }
        }
    }

    private var quitButton: some View {
        MenuButton(title: "Quit PortLight", icon: "power") {
            manager.shutdown()
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

private struct MenuButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
