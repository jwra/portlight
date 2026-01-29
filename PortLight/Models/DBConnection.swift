import Foundation

struct DBConnection: Codable, Identifiable, Equatable {
    /// Unique identifier for this connection (auto-generated if not provided)
    var id: String
    var name: String
    var instanceConnectionName: String
    var port: Int
    var autoConnect: Bool

    var displayPort: String {
        "localhost:\(port)"
    }

    init(id: String = UUID().uuidString, name: String, instanceConnectionName: String, port: Int, autoConnect: Bool = false) {
        self.id = id
        self.name = name
        self.instanceConnectionName = instanceConnectionName
        self.port = port
        self.autoConnect = autoConnect
    }

    // Custom decoding to handle configs without 'id' field (backward compatibility)
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        self.name = try container.decode(String.self, forKey: .name)
        self.instanceConnectionName = try container.decode(String.self, forKey: .instanceConnectionName)
        self.port = try container.decode(Int.self, forKey: .port)
        self.autoConnect = try container.decodeIfPresent(Bool.self, forKey: .autoConnect) ?? false
    }

    func requiresReconnect(comparedTo old: DBConnection) -> Bool {
        port != old.port || instanceConnectionName != old.instanceConnectionName
    }

    func validate() -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        // Validate name
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            issues.append(.error("Connection name cannot be empty", field: "name"))
        } else if name.count > 100 {
            issues.append(.warning("Connection name is unusually long", field: "name"))
        }

        // Validate port
        if port < 1 || port > 65535 {
            issues.append(.error("Port must be between 1 and 65535", field: "port"))
        } else if port < 1024 {
            issues.append(.warning("Port \(port) is privileged and may require admin access", field: "port"))
        }

        // Validate instance connection name format: project:region:instance
        if !Self.isValidInstanceConnectionName(instanceConnectionName) {
            issues.append(.error(
                "Instance connection name must be in format 'project:region:instance'",
                field: "instanceConnectionName"
            ))
        }

        return issues
    }

    /// Validates GCP instance connection name format: project:region:instance
    private static func isValidInstanceConnectionName(_ name: String) -> Bool {
        let components = name.split(separator: ":")
        guard components.count == 3 else { return false }

        // Each component should be non-empty and contain valid characters
        // GCP project IDs: lowercase letters, digits, hyphens (6-30 chars)
        // Region: lowercase letters, digits, hyphens
        // Instance: lowercase letters, digits, hyphens
        let validPattern = "^[a-z][a-z0-9-]*$"
        guard let regex = try? NSRegularExpression(pattern: validPattern) else { return false }

        for component in components {
            let str = String(component)
            let range = NSRange(str.startIndex..., in: str)
            if regex.firstMatch(in: str, range: range) == nil {
                return false
            }
        }

        return true
    }
}

struct ValidationIssue: Equatable {
    enum Severity: Equatable {
        case warning
        case error
    }

    let severity: Severity
    let message: String
    let field: String

    static func warning(_ message: String, field: String) -> ValidationIssue {
        ValidationIssue(severity: .warning, message: message, field: field)
    }

    static func error(_ message: String, field: String) -> ValidationIssue {
        ValidationIssue(severity: .error, message: message, field: field)
    }

    var isError: Bool { severity == .error }
}
