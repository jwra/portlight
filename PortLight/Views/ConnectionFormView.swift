import SwiftUI

struct ConnectionFormView: View {
    @Environment(\.dismiss) private var dismiss

    let configManager: ConfigManager
    let existingConnection: DBConnection?

    @State private var name: String = ""
    @State private var instanceConnectionName: String = ""
    @State private var port: String = "5432"
    @State private var autoConnect: Bool = false

    private var isEditing: Bool {
        existingConnection != nil
    }

    private var title: String {
        isEditing ? "Edit Connection" : "Add Connection"
    }

    // Validation
    private var currentConnection: DBConnection {
        DBConnection(
            id: existingConnection?.id ?? UUID().uuidString,
            name: name,
            instanceConnectionName: instanceConnectionName,
            port: Int(port) ?? 0,
            autoConnect: autoConnect
        )
    }

    private var validationIssues: [ValidationIssue] {
        currentConnection.validate()
    }

    private var nameIssues: [ValidationIssue] {
        validationIssues.filter { $0.field == "name" }
    }

    private var instanceIssues: [ValidationIssue] {
        validationIssues.filter { $0.field == "instanceConnectionName" }
    }

    private var portIssues: [ValidationIssue] {
        validationIssues.filter { $0.field == "port" }
    }

    private var hasErrors: Bool {
        validationIssues.contains { $0.isError }
    }

    private var canSave: Bool {
        !hasErrors && !name.isEmpty && !instanceConnectionName.isEmpty && !port.isEmpty
    }

    init(configManager: ConfigManager, existingConnection: DBConnection? = nil) {
        self.configManager = configManager
        self.existingConnection = existingConnection
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Form content
            formContent
                .padding(20)

            Divider()

            // Footer buttons
            footer
        }
        .frame(width: 400)
        .onAppear {
            if let connection = existingConnection {
                name = connection.name
                instanceConnectionName = connection.instanceConnectionName
                port = String(connection.port)
                autoConnect = connection.autoConnect
            }
        }
    }

    private var header: some View {
        HStack {
            Text(title)
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var formContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Name field
            VStack(alignment: .leading, spacing: 4) {
                Text("Name")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("Production DB", text: $name)
                    .textFieldStyle(.roundedBorder)
                issueMessages(for: nameIssues)
            }

            // Instance Connection Name field
            VStack(alignment: .leading, spacing: 4) {
                Text("Instance Connection Name")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("project:region:instance", text: $instanceConnectionName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                Text("Format: project:region:instance")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                issueMessages(for: instanceIssues)
            }

            // Port field
            VStack(alignment: .leading, spacing: 4) {
                Text("Local Port")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("5432", text: $port)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                    .onChange(of: port) { _, newValue in
                        // Only allow numeric input
                        port = newValue.filter { $0.isNumber }
                    }
                issueMessages(for: portIssues)
            }

            // Auto-connect toggle
            Toggle("Auto-connect on launch", isOn: $autoConnect)
                .toggleStyle(.checkbox)
        }
    }

    @ViewBuilder
    private func issueMessages(for issues: [ValidationIssue]) -> some View {
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

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Button(isEditing ? "Save" : "Add") {
                saveConnection()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canSave)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func saveConnection() {
        let connection = currentConnection
        if isEditing {
            configManager.updateConnection(connection)
        } else {
            configManager.addConnection(connection)
        }
        dismiss()
    }
}
