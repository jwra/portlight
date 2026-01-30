import XCTest
@testable import PortLight

final class DBConnectionTests: XCTestCase {

    // MARK: - Initialization Tests

    func testDefaultInitGeneratesUniqueID() {
        let conn1 = DBConnection(name: "Test", instanceConnectionName: "proj:region:inst", port: 5432)
        let conn2 = DBConnection(name: "Test", instanceConnectionName: "proj:region:inst", port: 5432)

        XCTAssertNotEqual(conn1.id, conn2.id)
    }

    func testCustomIDPreserved() {
        let customID = "custom-id-123"
        let conn = DBConnection(id: customID, name: "Test", instanceConnectionName: "proj:region:inst", port: 5432)

        XCTAssertEqual(conn.id, customID)
    }

    func testAutoConnectDefaultsFalse() {
        let conn = DBConnection(name: "Test", instanceConnectionName: "proj:region:inst", port: 5432)

        XCTAssertFalse(conn.autoConnect)
    }

    // MARK: - Display Port Tests

    func testDisplayPortFormatsCorrectly() {
        let conn = DBConnection(name: "Test", instanceConnectionName: "proj:region:inst", port: 5432)

        XCTAssertEqual(conn.displayPort, "localhost:5432")
    }

    // MARK: - Requires Reconnect Tests

    func testPortChangeRequiresReconnect() {
        let old = DBConnection(id: "1", name: "Test", instanceConnectionName: "proj:region:inst", port: 5432)
        let new = DBConnection(id: "1", name: "Test", instanceConnectionName: "proj:region:inst", port: 5433)

        XCTAssertTrue(new.requiresReconnect(comparedTo: old))
    }

    func testInstanceNameChangeRequiresReconnect() {
        let old = DBConnection(id: "1", name: "Test", instanceConnectionName: "proj:region:inst1", port: 5432)
        let new = DBConnection(id: "1", name: "Test", instanceConnectionName: "proj:region:inst2", port: 5432)

        XCTAssertTrue(new.requiresReconnect(comparedTo: old))
    }

    func testNameChangeDoesNotRequireReconnect() {
        let old = DBConnection(id: "1", name: "Old Name", instanceConnectionName: "proj:region:inst", port: 5432)
        let new = DBConnection(id: "1", name: "New Name", instanceConnectionName: "proj:region:inst", port: 5432)

        XCTAssertFalse(new.requiresReconnect(comparedTo: old))
    }

    func testAutoConnectChangeDoesNotRequireReconnect() {
        let old = DBConnection(id: "1", name: "Test", instanceConnectionName: "proj:region:inst", port: 5432, autoConnect: false)
        let new = DBConnection(id: "1", name: "Test", instanceConnectionName: "proj:region:inst", port: 5432, autoConnect: true)

        XCTAssertFalse(new.requiresReconnect(comparedTo: old))
    }

    // MARK: - Name Validation Tests

    func testEmptyNameProducesError() {
        let conn = DBConnection(name: "", instanceConnectionName: "proj:region:inst", port: 5432)
        let issues = conn.validate()

        let nameErrors = issues.filter { $0.field == "name" && $0.isError }
        XCTAssertEqual(nameErrors.count, 1)
        XCTAssertTrue(nameErrors.first?.message.contains("empty") ?? false)
    }

    func testWhitespaceOnlyNameProducesError() {
        let conn = DBConnection(name: "   ", instanceConnectionName: "proj:region:inst", port: 5432)
        let issues = conn.validate()

        let nameErrors = issues.filter { $0.field == "name" && $0.isError }
        XCTAssertEqual(nameErrors.count, 1)
    }

    func testLongNameProducesWarning() {
        let longName = String(repeating: "a", count: 101)
        let conn = DBConnection(name: longName, instanceConnectionName: "proj:region:inst", port: 5432)
        let issues = conn.validate()

        let nameWarnings = issues.filter { $0.field == "name" && !$0.isError }
        XCTAssertEqual(nameWarnings.count, 1)
        XCTAssertTrue(nameWarnings.first?.message.contains("long") ?? false)
    }

    func testValidNameProducesNoIssues() {
        let conn = DBConnection(name: "Production DB", instanceConnectionName: "proj:region:inst", port: 5432)
        let issues = conn.validate()

        let nameIssues = issues.filter { $0.field == "name" }
        XCTAssertTrue(nameIssues.isEmpty)
    }

    // MARK: - Port Validation Tests

    func testPortZeroProducesError() {
        let conn = DBConnection(name: "Test", instanceConnectionName: "proj:region:inst", port: 0)
        let issues = conn.validate()

        let portErrors = issues.filter { $0.field == "port" && $0.isError }
        XCTAssertEqual(portErrors.count, 1)
    }

    func testNegativePortProducesError() {
        let conn = DBConnection(name: "Test", instanceConnectionName: "proj:region:inst", port: -1)
        let issues = conn.validate()

        let portErrors = issues.filter { $0.field == "port" && $0.isError }
        XCTAssertEqual(portErrors.count, 1)
    }

    func testPortAboveMaxProducesError() {
        let conn = DBConnection(name: "Test", instanceConnectionName: "proj:region:inst", port: 65536)
        let issues = conn.validate()

        let portErrors = issues.filter { $0.field == "port" && $0.isError }
        XCTAssertEqual(portErrors.count, 1)
    }

    func testPrivilegedPortProducesWarning() {
        let conn = DBConnection(name: "Test", instanceConnectionName: "proj:region:inst", port: 443)
        let issues = conn.validate()

        let portWarnings = issues.filter { $0.field == "port" && !$0.isError }
        XCTAssertEqual(portWarnings.count, 1)
        XCTAssertTrue(portWarnings.first?.message.contains("privileged") ?? false)
    }

    func testPort1024NoWarning() {
        let conn = DBConnection(name: "Test", instanceConnectionName: "proj:region:inst", port: 1024)
        let issues = conn.validate()

        let portIssues = issues.filter { $0.field == "port" }
        XCTAssertTrue(portIssues.isEmpty)
    }

    func testStandardPostgresPortValid() {
        let conn = DBConnection(name: "Test", instanceConnectionName: "proj:region:inst", port: 5432)
        let issues = conn.validate()

        let portIssues = issues.filter { $0.field == "port" }
        XCTAssertTrue(portIssues.isEmpty)
    }

    // MARK: - Instance Connection Name Validation Tests

    func testValidInstanceConnectionNamePasses() {
        let validNames = [
            "myproject:us-central1:myinstance",
            "my-project:europe-west1:my-instance",
            "a:b:c",  // Single character components
            "project123:region456:instance789",
        ]

        for name in validNames {
            let conn = DBConnection(name: "Test", instanceConnectionName: name, port: 5432)
            let issues = conn.validate()
            let instanceIssues = issues.filter { $0.field == "instanceConnectionName" }
            XCTAssertTrue(instanceIssues.isEmpty, "Expected '\(name)' to be valid")
        }
    }

    func testMissingColonProducesError() {
        let conn = DBConnection(name: "Test", instanceConnectionName: "project-region-instance", port: 5432)
        let issues = conn.validate()

        let instanceErrors = issues.filter { $0.field == "instanceConnectionName" && $0.isError }
        XCTAssertEqual(instanceErrors.count, 1)
    }

    func testTooFewComponentsProducesError() {
        let conn = DBConnection(name: "Test", instanceConnectionName: "project:instance", port: 5432)
        let issues = conn.validate()

        let instanceErrors = issues.filter { $0.field == "instanceConnectionName" && $0.isError }
        XCTAssertEqual(instanceErrors.count, 1)
    }

    func testTooManyComponentsProducesError() {
        let conn = DBConnection(name: "Test", instanceConnectionName: "a:b:c:d", port: 5432)
        let issues = conn.validate()

        let instanceErrors = issues.filter { $0.field == "instanceConnectionName" && $0.isError }
        XCTAssertEqual(instanceErrors.count, 1)
    }

    func testEmptyComponentProducesError() {
        let conn = DBConnection(name: "Test", instanceConnectionName: "project::instance", port: 5432)
        let issues = conn.validate()

        let instanceErrors = issues.filter { $0.field == "instanceConnectionName" && $0.isError }
        XCTAssertEqual(instanceErrors.count, 1)
    }

    func testUppercaseProducesError() {
        let conn = DBConnection(name: "Test", instanceConnectionName: "MyProject:us-central1:instance", port: 5432)
        let issues = conn.validate()

        let instanceErrors = issues.filter { $0.field == "instanceConnectionName" && $0.isError }
        XCTAssertEqual(instanceErrors.count, 1)
    }

    func testInvalidCharactersProduceError() {
        let invalidNames = [
            "project_name:region:instance",  // Underscore
            "project:region:instance!",      // Exclamation
            "project:region:instance.name",  // Period
        ]

        for name in invalidNames {
            let conn = DBConnection(name: "Test", instanceConnectionName: name, port: 5432)
            let issues = conn.validate()
            let instanceErrors = issues.filter { $0.field == "instanceConnectionName" && $0.isError }
            XCTAssertEqual(instanceErrors.count, 1, "Expected '\(name)' to be invalid")
        }
    }

    // MARK: - Full Validation Tests

    func testValidConnectionProducesNoErrors() {
        let conn = DBConnection(
            name: "Production",
            instanceConnectionName: "myproject:us-central1:mydb",
            port: 5432,
            autoConnect: true
        )
        let issues = conn.validate()

        let errors = issues.filter { $0.isError }
        XCTAssertTrue(errors.isEmpty)
    }

    func testMultipleErrorsCollected() {
        let conn = DBConnection(
            name: "",
            instanceConnectionName: "invalid",
            port: 0
        )
        let issues = conn.validate()

        let errors = issues.filter { $0.isError }
        XCTAssertGreaterThanOrEqual(errors.count, 3)
    }

    // MARK: - Codable Tests

    func testEncodeDecode() throws {
        let original = DBConnection(
            id: "test-id",
            name: "Test DB",
            instanceConnectionName: "proj:region:inst",
            port: 5432,
            autoConnect: true
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DBConnection.self, from: encoded)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.instanceConnectionName, original.instanceConnectionName)
        XCTAssertEqual(decoded.port, original.port)
        XCTAssertEqual(decoded.autoConnect, original.autoConnect)
    }

    func testDecodeWithoutIDGeneratesUUID() throws {
        let json = """
        {
            "name": "Test",
            "instanceConnectionName": "proj:region:inst",
            "port": 5432
        }
        """

        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(DBConnection.self, from: data)

        XCTAssertFalse(decoded.id.isEmpty)
        XCTAssertEqual(decoded.name, "Test")
        XCTAssertFalse(decoded.autoConnect) // Default value
    }

    func testDecodeWithoutAutoConnectDefaultsToFalse() throws {
        let json = """
        {
            "id": "test-id",
            "name": "Test",
            "instanceConnectionName": "proj:region:inst",
            "port": 5432
        }
        """

        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(DBConnection.self, from: data)

        XCTAssertFalse(decoded.autoConnect)
    }
}
