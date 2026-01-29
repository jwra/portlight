import SwiftUI

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @Bindable var manager: ConnectionManager
    @State private var showDisconnectAllConfirmation = false

    private var validationResult: ConfigValidationResult? {
        manager.configManager.lastValidationResult
    }

    private var hasValidationErrors: Bool {
        validationResult?.isValid == false
    }

    private var activeConnectionCount: Int {
        manager.statuses.values.filter { $0.isActive }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let error = manager.lastError {
                errorBanner(name: error.connectionName, message: error.message)
                Divider()
            }
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
    private func errorBanner(name: String, message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(.caption, weight: .medium))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button {
                manager.clearError()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.1))
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
                Text("Open Manage Connections to fix")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Fix") {
                openWindow(id: "manage-connections")
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
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
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
            .frame(maxHeight: 350)
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 0) {
            MenuButton(title: "Manage Connections...", icon: "slider.horizontal.3") {
                // macOS WindowGroup with matching ID brings existing window to front
                // if already open, rather than creating multiple instances
                openWindow(id: "manage-connections")
            }

            MenuButton(title: "Reload Config", icon: "arrow.clockwise") {
                manager.reloadConfig()
            }

            if manager.hasActiveConnections {
                MenuButton(title: "Disconnect All", icon: "xmark.circle") {
                    // Show confirmation when multiple connections are active
                    if activeConnectionCount > 1 {
                        showDisconnectAllConfirmation = true
                    } else {
                        manager.disconnectAll()
                    }
                }
            }
        }
        .confirmationDialog(
            "Disconnect all connections?",
            isPresented: $showDisconnectAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Disconnect All", role: .destructive) {
                manager.disconnectAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will disconnect \(activeConnectionCount) active connections.")
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
