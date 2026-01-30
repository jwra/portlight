import Foundation
import AppKit
import OSLog

@Observable
final class ConfigManager {
    private let logger = Logger(subsystem: "net.jwra.PortLight", category: "Config")
    private let fileManager = FileManager.default

    // UserDefaults keys
    private let connectionsKey = "connections"
    private let binaryPathKey = "binaryPath"

    static let defaultBinaryPath = "/usr/local/bin/cloud-sql-proxy"

    /// Last validation result from config loading - publicly readable for UI
    var lastValidationResult: ConfigValidationResult?

    /// Callback fired when config changes (connections or binaryPath) for ConnectionManager to observe
    var onConfigChanged: (() -> Void)?

    // MARK: - Stored Properties

    var connections: [DBConnection] {
        get {
            guard let data = UserDefaults.standard.data(forKey: connectionsKey) else {
                return []
            }
            do {
                return try JSONDecoder().decode([DBConnection].self, from: data)
            } catch {
                logger.error("Failed to decode connections: \(error.localizedDescription)")
                return []
            }
        }
        set {
            do {
                let data = try JSONEncoder().encode(newValue)
                UserDefaults.standard.set(data, forKey: connectionsKey)
                logger.info("Saved \(newValue.count) connections")
                revalidate()
                onConfigChanged?()
            } catch {
                logger.error("Failed to encode connections: \(error.localizedDescription)")
            }
        }
    }

    var binaryPath: String {
        get {
            UserDefaults.standard.string(forKey: binaryPathKey) ?? Self.defaultBinaryPath
        }
        set {
            UserDefaults.standard.set(newValue, forKey: binaryPathKey)
            logger.info("Binary path updated to: \(newValue)")
            revalidate()
            onConfigChanged?()
        }
    }

    // MARK: - Initialization

    init() {
        revalidate()
    }

    // MARK: - CRUD Operations

    func addConnection(_ connection: DBConnection) {
        var current = connections
        current.append(connection)
        connections = current
        logger.info("Added connection: \(connection.name)")
    }

    func updateConnection(_ connection: DBConnection) {
        var current = connections
        if let index = current.firstIndex(where: { $0.id == connection.id }) {
            current[index] = connection
            connections = current
            logger.info("Updated connection: \(connection.name)")
        } else {
            logger.warning("Connection not found for update: \(connection.id)")
        }
    }

    func deleteConnection(id: String) {
        var current = connections
        if let index = current.firstIndex(where: { $0.id == id }) {
            let removed = current.remove(at: index)
            connections = current
            logger.info("Deleted connection: \(removed.name)")
        } else {
            logger.warning("Connection not found for deletion: \(id)")
        }
    }

    func connection(byId id: String) -> DBConnection? {
        connections.first { $0.id == id }
    }

    // MARK: - Validation

    private func revalidate() {
        let result = validate()
        lastValidationResult = result
        logValidationIssues(result)
    }

    func validate() -> ConfigValidationResult {
        var issues: [String: [ValidationIssue]] = [:]

        // Validate binary path
        var binaryIssues: [ValidationIssue] = []
        let path = binaryPath
        if path.trimmingCharacters(in: .whitespaces).isEmpty {
            binaryIssues.append(.error("Binary path cannot be empty", field: "binaryPath"))
        } else if !fileManager.fileExists(atPath: path) {
            binaryIssues.append(.error("Binary not found at \(path)", field: "binaryPath"))
        } else if !fileManager.isExecutableFile(atPath: path) {
            binaryIssues.append(.error("Binary at \(path) is not executable", field: "binaryPath"))
        }
        if !binaryIssues.isEmpty {
            issues["binaryPath"] = binaryIssues
        }

        // Validate connections
        let conns = connections
        if conns.isEmpty {
            issues["connections"] = [.warning("No connections configured", field: "connections")]
        }

        // Validate each connection
        for connection in conns {
            let connectionIssues = connection.validate()
            if !connectionIssues.isEmpty {
                issues[connection.id] = connectionIssues
            }
        }

        return ConfigValidationResult(issues: issues)
    }

    private func logValidationIssues(_ result: ConfigValidationResult) {
        for error in result.allErrors {
            logger.error("Config error [\(error.field)]: \(error.message)")
        }
        for warning in result.allWarnings {
            logger.warning("Config warning [\(warning.field)]: \(warning.message)")
        }
        if result.isValid && !result.hasWarnings {
            logger.info("Config validation passed")
        }
    }

    // MARK: - Legacy Compatibility (for transition period)

    /// Returns an AppConfig for compatibility with existing ConnectionManager code
    func loadConfig() -> AppConfig {
        let config = AppConfig(binaryPath: binaryPath, connections: connections)
        let result = config.validate()
        lastValidationResult = result
        logValidationIssues(result)
        return config
    }

    /// Saves an AppConfig for compatibility with existing code
    func saveConfig(_ config: AppConfig) {
        binaryPath = config.binaryPath
        connections = config.connections
    }
}
