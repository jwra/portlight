import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ManageConnectionsView: View {
    let configManager: ConfigManager

    @State private var connectionToEdit: DBConnection?
    @State private var showingAddSheet = false
    @State private var connectionToDelete: DBConnection?
    @State private var showingDeleteConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            // Header with title and add button
            header

            Divider()

            // Connections list
            if configManager.connections.isEmpty {
                emptyState
            } else {
                connectionsList
            }

            Divider()

            // Binary path configuration
            binaryPathSection
        }
        .frame(width: 450, height: 400)
        .sheet(isPresented: $showingAddSheet) {
            ConnectionFormView(configManager: configManager)
        }
        .sheet(item: $connectionToEdit) { connection in
            ConnectionFormView(configManager: configManager, existingConnection: connection)
        }
        .confirmationDialog(
            "Delete Connection",
            isPresented: $showingDeleteConfirmation,
            presenting: connectionToDelete
        ) { connection in
            Button("Delete", role: .destructive) {
                configManager.deleteConnection(id: connection.id)
                connectionToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                connectionToDelete = nil
            }
        } message: { connection in
            Text("Are you sure you want to delete \"\(connection.name)\"? This action cannot be undone.")
        }
    }

    private var header: some View {
        HStack {
            Text("Manage Connections")
                .font(.headline)
            Spacer()
            Button {
                showingAddSheet = true
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.bordered)
            .help("Add Connection")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "externaldrive.connected.to.line.below")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No Connections")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Click + to add your first connection")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var connectionsList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(configManager.connections) { connection in
                    ConnectionCard(
                        connection: connection,
                        onEdit: { connectionToEdit = connection },
                        onDelete: {
                            connectionToDelete = connection
                            showingDeleteConfirmation = true
                        }
                    )
                }
            }
            .padding(12)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var binaryPathSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cloud SQL Proxy Binary")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                Text(configManager.binaryPath)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(4)

                Button("Browse...") {
                    selectBinaryPath()
                }
                .buttonStyle(.bordered)
            }

            // Validation message for binary path
            if let result = configManager.lastValidationResult,
               let issues = result.issues["binaryPath"] {
                ForEach(issues, id: \.message) { issue in
                    HStack(spacing: 4) {
                        Image(systemName: issue.isError ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill")
                            .font(.caption)
                        Text(issue.message)
                            .font(.caption)
                    }
                    .foregroundStyle(issue.isError ? .red : .orange)
                }
            }
        }
        .padding(16)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func selectBinaryPath() {
        let panel = NSOpenPanel()
        panel.title = "Select Cloud SQL Proxy Binary"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.canCreateDirectories = false
        panel.allowedContentTypes = [.unixExecutable, .executable, .item]

        if panel.runModal() == .OK, let url = panel.url {
            configManager.binaryPath = url.path
        }
    }
}

private struct ConnectionCard: View {
    let connection: DBConnection
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(connection.name)
                    .font(.system(.body, weight: .medium))

                HStack(spacing: 4) {
                    Text(connection.instanceConnectionName)
                        .font(.system(.caption, design: .monospaced))
                    Text("→")
                        .foregroundStyle(.tertiary)
                    Text("localhost:\(connection.port)")
                        .font(.system(.caption, design: .monospaced))
                }
                .foregroundStyle(.secondary)

                if connection.autoConnect {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .font(.caption2)
                        Text("Auto-connect")
                            .font(.caption2)
                    }
                    .foregroundStyle(.blue)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Button("Edit") {
                    onEdit()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Delete") {
                    onDelete()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .foregroundStyle(.red)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}

