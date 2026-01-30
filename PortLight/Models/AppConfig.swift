import Foundation

struct AppConfig: Codable {
    var binaryPath: String
    var connections: [DBConnection]

    static let defaultBinaryPath = "/usr/local/bin/cloud-sql-proxy"

    static var defaultConfig: AppConfig {
        AppConfig(
            binaryPath: defaultBinaryPath,
            connections: [
                DBConnection(
                    name: "example-db",
                    instanceConnectionName: "your-project:your-region:your-instance",
                    port: 5432,
                    autoConnect: false
                )
            ]
        )
    }

    func validate() -> ConfigValidationResult {
        var issues: [String: [ValidationIssue]] = [:]

        // Validate binary path
        var binaryIssues: [ValidationIssue] = []
        if binaryPath.trimmingCharacters(in: .whitespaces).isEmpty {
            binaryIssues.append(.error("Binary path cannot be empty", field: "binaryPath"))
        } else if !FileManager.default.fileExists(atPath: binaryPath) {
            binaryIssues.append(.error("Binary not found at \(binaryPath)", field: "binaryPath"))
        } else if !FileManager.default.isExecutableFile(atPath: binaryPath) {
            binaryIssues.append(.error("Binary at \(binaryPath) is not executable", field: "binaryPath"))
        }
        if !binaryIssues.isEmpty {
            issues["binaryPath"] = binaryIssues
        }

        // Validate connections
        if connections.isEmpty {
            issues["connections"] = [.warning("No connections configured", field: "connections")]
        }

        // Validate each connection
        for connection in connections {
            let connectionIssues = connection.validate()
            if !connectionIssues.isEmpty {
                issues[connection.id] = connectionIssues
            }
        }

        // Note: Duplicate ports are allowed in config - users may want to switch
        // between connections on the same port. Runtime port conflict detection
        // in ConnectionManager.connect() handles the case where both are active.

        return ConfigValidationResult(issues: issues)
    }
}

struct ConfigValidationResult {
    let issues: [String: [ValidationIssue]]

    var isValid: Bool {
        !issues.values.flatMap { $0 }.contains { $0.isError }
    }

    var hasWarnings: Bool {
        issues.values.flatMap { $0 }.contains { !$0.isError }
    }

    var allErrors: [ValidationIssue] {
        issues.values.flatMap { $0 }.filter { $0.isError }
    }

    var allWarnings: [ValidationIssue] {
        issues.values.flatMap { $0 }.filter { !$0.isError }
    }

    func issues(for connectionId: String) -> [ValidationIssue] {
        issues[connectionId] ?? []
    }
}
