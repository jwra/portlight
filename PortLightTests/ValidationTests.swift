import XCTest
@testable import PortLight

final class ValidationIssueTests: XCTestCase {

    // MARK: - Factory Method Tests

    func testWarningFactory() {
        let issue = ValidationIssue.warning("Test warning", field: "testField")

        XCTAssertEqual(issue.severity, .warning)
        XCTAssertEqual(issue.message, "Test warning")
        XCTAssertEqual(issue.field, "testField")
        XCTAssertFalse(issue.isError)
    }

    func testErrorFactory() {
        let issue = ValidationIssue.error("Test error", field: "testField")

        XCTAssertEqual(issue.severity, .error)
        XCTAssertEqual(issue.message, "Test error")
        XCTAssertEqual(issue.field, "testField")
        XCTAssertTrue(issue.isError)
    }

    // MARK: - Equatable Tests

    func testEqualIssues() {
        let issue1 = ValidationIssue.error("Same message", field: "sameField")
        let issue2 = ValidationIssue.error("Same message", field: "sameField")

        XCTAssertEqual(issue1, issue2)
    }

    func testDifferentSeverityNotEqual() {
        let warning = ValidationIssue.warning("Message", field: "field")
        let error = ValidationIssue.error("Message", field: "field")

        XCTAssertNotEqual(warning, error)
    }

    func testDifferentMessageNotEqual() {
        let issue1 = ValidationIssue.error("Message 1", field: "field")
        let issue2 = ValidationIssue.error("Message 2", field: "field")

        XCTAssertNotEqual(issue1, issue2)
    }

    func testDifferentFieldNotEqual() {
        let issue1 = ValidationIssue.error("Message", field: "field1")
        let issue2 = ValidationIssue.error("Message", field: "field2")

        XCTAssertNotEqual(issue1, issue2)
    }
}

final class ConfigValidationResultTests: XCTestCase {

    // MARK: - isValid Tests

    func testEmptyIssuesIsValid() {
        let result = ConfigValidationResult(issues: [:])

        XCTAssertTrue(result.isValid)
    }

    func testOnlyWarningsIsValid() {
        let issues: [String: [ValidationIssue]] = [
            "field1": [.warning("Warning 1", field: "field1")],
            "field2": [.warning("Warning 2", field: "field2")]
        ]
        let result = ConfigValidationResult(issues: issues)

        XCTAssertTrue(result.isValid)
    }

    func testWithErrorsNotValid() {
        let issues: [String: [ValidationIssue]] = [
            "field1": [.error("Error", field: "field1")]
        ]
        let result = ConfigValidationResult(issues: issues)

        XCTAssertFalse(result.isValid)
    }

    func testMixedIssuesNotValid() {
        let issues: [String: [ValidationIssue]] = [
            "field1": [.warning("Warning", field: "field1")],
            "field2": [.error("Error", field: "field2")]
        ]
        let result = ConfigValidationResult(issues: issues)

        XCTAssertFalse(result.isValid)
    }

    // MARK: - hasWarnings Tests

    func testNoWarnings() {
        let issues: [String: [ValidationIssue]] = [
            "field1": [.error("Error", field: "field1")]
        ]
        let result = ConfigValidationResult(issues: issues)

        XCTAssertFalse(result.hasWarnings)
    }

    func testHasWarnings() {
        let issues: [String: [ValidationIssue]] = [
            "field1": [.warning("Warning", field: "field1")]
        ]
        let result = ConfigValidationResult(issues: issues)

        XCTAssertTrue(result.hasWarnings)
    }

    func testEmptyHasNoWarnings() {
        let result = ConfigValidationResult(issues: [:])

        XCTAssertFalse(result.hasWarnings)
    }

    // MARK: - allErrors Tests

    func testAllErrorsEmpty() {
        let result = ConfigValidationResult(issues: [:])

        XCTAssertTrue(result.allErrors.isEmpty)
    }

    func testAllErrorsCollectsFromMultipleFields() {
        let issues: [String: [ValidationIssue]] = [
            "field1": [.error("Error 1", field: "field1")],
            "field2": [.error("Error 2", field: "field2"), .warning("Warning", field: "field2")]
        ]
        let result = ConfigValidationResult(issues: issues)

        XCTAssertEqual(result.allErrors.count, 2)
        XCTAssertTrue(result.allErrors.allSatisfy { $0.isError })
    }

    func testAllErrorsExcludesWarnings() {
        let issues: [String: [ValidationIssue]] = [
            "field1": [.warning("Warning 1", field: "field1")],
            "field2": [.warning("Warning 2", field: "field2")]
        ]
        let result = ConfigValidationResult(issues: issues)

        XCTAssertTrue(result.allErrors.isEmpty)
    }

    // MARK: - allWarnings Tests

    func testAllWarningsEmpty() {
        let result = ConfigValidationResult(issues: [:])

        XCTAssertTrue(result.allWarnings.isEmpty)
    }

    func testAllWarningsCollectsFromMultipleFields() {
        let issues: [String: [ValidationIssue]] = [
            "field1": [.warning("Warning 1", field: "field1")],
            "field2": [.warning("Warning 2", field: "field2"), .error("Error", field: "field2")]
        ]
        let result = ConfigValidationResult(issues: issues)

        XCTAssertEqual(result.allWarnings.count, 2)
        XCTAssertTrue(result.allWarnings.allSatisfy { !$0.isError })
    }

    func testAllWarningsExcludesErrors() {
        let issues: [String: [ValidationIssue]] = [
            "field1": [.error("Error 1", field: "field1")],
            "field2": [.error("Error 2", field: "field2")]
        ]
        let result = ConfigValidationResult(issues: issues)

        XCTAssertTrue(result.allWarnings.isEmpty)
    }

    // MARK: - issues(for:) Tests

    func testIssuesForExistingConnection() {
        let issues: [String: [ValidationIssue]] = [
            "conn-1": [.error("Error", field: "name")],
            "conn-2": [.warning("Warning", field: "port")]
        ]
        let result = ConfigValidationResult(issues: issues)

        let conn1Issues = result.issues(for: "conn-1")
        XCTAssertEqual(conn1Issues.count, 1)
        XCTAssertEqual(conn1Issues.first?.message, "Error")
    }

    func testIssuesForNonExistentConnection() {
        let issues: [String: [ValidationIssue]] = [
            "conn-1": [.error("Error", field: "name")]
        ]
        let result = ConfigValidationResult(issues: issues)

        let unknownIssues = result.issues(for: "unknown")
        XCTAssertTrue(unknownIssues.isEmpty)
    }

    func testIssuesForMultipleIssuesSameConnection() {
        let issues: [String: [ValidationIssue]] = [
            "conn-1": [
                .error("Name error", field: "name"),
                .error("Port error", field: "port"),
                .warning("Instance warning", field: "instanceConnectionName")
            ]
        ]
        let result = ConfigValidationResult(issues: issues)

        let conn1Issues = result.issues(for: "conn-1")
        XCTAssertEqual(conn1Issues.count, 3)
    }
}
