import XCTest
@testable import PortLight

final class AppConfigTests: XCTestCase {

    // MARK: - Default Config Tests

    func testDefaultConfigHasDefaultBinaryPath() {
        let config = AppConfig.defaultConfig

        XCTAssertEqual(config.binaryPath, "/usr/local/bin/cloud-sql-proxy")
    }

    func testDefaultConfigHasExampleConnection() {
        let config = AppConfig.defaultConfig

        XCTAssertEqual(config.connections.count, 1)
        XCTAssertEqual(config.connections.first?.name, "example-db")
    }

    // MARK: - Binary Path Validation Tests

    func testEmptyBinaryPathProducesError() {
        let config = AppConfig(binaryPath: "", connections: [])
        let result = config.validate()

        let binaryErrors = result.issues["binaryPath"]?.filter { $0.isError } ?? []
        XCTAssertEqual(binaryErrors.count, 1)
        XCTAssertTrue(binaryErrors.first?.message.contains("empty") ?? false)
    }

    func testWhitespaceBinaryPathProducesError() {
        let config = AppConfig(binaryPath: "   ", connections: [])
        let result = config.validate()

        let binaryErrors = result.issues["binaryPath"]?.filter { $0.isError } ?? []
        XCTAssertEqual(binaryErrors.count, 1)
    }

    func testNonExistentBinaryPathProducesError() {
        let config = AppConfig(binaryPath: "/nonexistent/path/to/binary", connections: [])
        let result = config.validate()

        let binaryErrors = result.issues["binaryPath"]?.filter { $0.isError } ?? []
        XCTAssertEqual(binaryErrors.count, 1)
        XCTAssertTrue(binaryErrors.first?.message.contains("not found") ?? false)
    }

    func testNonExecutableBinaryPathProducesError() {
        // Use a file that exists but is not executable (like /etc/hosts on macOS)
        let config = AppConfig(binaryPath: "/etc/hosts", connections: [])
        let result = config.validate()

        let binaryErrors = result.issues["binaryPath"]?.filter { $0.isError } ?? []
        XCTAssertEqual(binaryErrors.count, 1)
        XCTAssertTrue(binaryErrors.first?.message.contains("not executable") ?? false)
    }

    func testValidExecutableBinaryPath() {
        // Use a known executable that exists on macOS
        let config = AppConfig(binaryPath: "/bin/ls", connections: [])
        let result = config.validate()

        let binaryIssues = result.issues["binaryPath"] ?? []
        XCTAssertTrue(binaryIssues.isEmpty)
    }

    // MARK: - Empty Connections Warning Tests

    func testEmptyConnectionsProducesWarning() {
        let config = AppConfig(binaryPath: "/bin/ls", connections: [])
        let result = config.validate()

        let connectionWarnings = result.issues["connections"]?.filter { !$0.isError } ?? []
        XCTAssertEqual(connectionWarnings.count, 1)
        XCTAssertTrue(connectionWarnings.first?.message.contains("No connections") ?? false)
    }

    func testNonEmptyConnectionsNoWarning() {
        let connection = DBConnection(
            name: "Test",
            instanceConnectionName: "proj:region:inst",
            port: 5432
        )
        let config = AppConfig(binaryPath: "/bin/ls", connections: [connection])
        let result = config.validate()

        let connectionWarnings = result.issues["connections"]?.filter { !$0.isError } ?? []
        XCTAssertTrue(connectionWarnings.isEmpty)
    }

    // MARK: - Connection Validation Propagation Tests

    func testInvalidConnectionProducesError() {
        let invalidConnection = DBConnection(
            id: "test-conn",
            name: "",  // Invalid: empty name
            instanceConnectionName: "proj:region:inst",
            port: 5432
        )
        let config = AppConfig(binaryPath: "/bin/ls", connections: [invalidConnection])
        let result = config.validate()

        let connectionErrors = result.issues["test-conn"]?.filter { $0.isError } ?? []
        XCTAssertFalse(connectionErrors.isEmpty)
    }

    func testMultipleConnectionsValidatedIndependently() {
        let validConnection = DBConnection(
            id: "valid-conn",
            name: "Valid",
            instanceConnectionName: "proj:region:inst",
            port: 5432
        )
        let invalidConnection = DBConnection(
            id: "invalid-conn",
            name: "",  // Invalid
            instanceConnectionName: "invalid",  // Also invalid
            port: 0  // Also invalid
        )
        let config = AppConfig(binaryPath: "/bin/ls", connections: [validConnection, invalidConnection])
        let result = config.validate()

        // Valid connection should have no issues
        XCTAssertTrue(result.issues["valid-conn"]?.isEmpty ?? true)

        // Invalid connection should have issues
        let invalidErrors = result.issues["invalid-conn"]?.filter { $0.isError } ?? []
        XCTAssertGreaterThanOrEqual(invalidErrors.count, 3)
    }

    // MARK: - Overall Validation Result Tests

    func testFullyValidConfigIsValid() {
        let connection = DBConnection(
            name: "Production",
            instanceConnectionName: "myproject:us-central1:mydb",
            port: 5432
        )
        let config = AppConfig(binaryPath: "/bin/ls", connections: [connection])
        let result = config.validate()

        XCTAssertTrue(result.isValid)
    }

    func testConfigWithOnlyWarningsIsValid() {
        // Empty connections produces warning but not error
        let config = AppConfig(binaryPath: "/bin/ls", connections: [])
        let result = config.validate()

        XCTAssertTrue(result.isValid)
        XCTAssertTrue(result.hasWarnings)
    }

    func testConfigWithErrorsIsNotValid() {
        let config = AppConfig(binaryPath: "/nonexistent/path", connections: [])
        let result = config.validate()

        XCTAssertFalse(result.isValid)
    }

    // MARK: - Duplicate Port Handling Tests

    func testDuplicatePortsAllowed() {
        // Design decision: duplicate ports are allowed in config
        // Runtime check prevents both from being active simultaneously
        let conn1 = DBConnection(
            id: "conn-1",
            name: "Connection 1",
            instanceConnectionName: "proj:region:inst1",
            port: 5432
        )
        let conn2 = DBConnection(
            id: "conn-2",
            name: "Connection 2",
            instanceConnectionName: "proj:region:inst2",
            port: 5432  // Same port
        )
        let config = AppConfig(binaryPath: "/bin/ls", connections: [conn1, conn2])
        let result = config.validate()

        // Should not produce port conflict errors - that's handled at runtime
        XCTAssertTrue(result.isValid)
    }

    // MARK: - Codable Tests

    func testEncodeDecode() throws {
        let connection = DBConnection(
            id: "test-id",
            name: "Test",
            instanceConnectionName: "proj:region:inst",
            port: 5432,
            autoConnect: true
        )
        let original = AppConfig(binaryPath: "/usr/local/bin/proxy", connections: [connection])

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: encoded)

        XCTAssertEqual(decoded.binaryPath, original.binaryPath)
        XCTAssertEqual(decoded.connections.count, original.connections.count)
        XCTAssertEqual(decoded.connections.first?.id, original.connections.first?.id)
    }
}
