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
}
