import XCTest
import SwiftUI
@testable import PortLight

final class ConnectionStatusTests: XCTestCase {

    // MARK: - Icon Tests

    func testDisconnectedIcon() {
        let status = ConnectionStatus.disconnected
        XCTAssertEqual(status.icon, "circle")
    }

    func testConnectingIcon() {
        let status = ConnectionStatus.connecting
        XCTAssertEqual(status.icon, "circle.dotted")
    }

    func testConnectedIcon() {
        let status = ConnectionStatus.connected
        XCTAssertEqual(status.icon, "circle.fill")
    }

    func testErrorIcon() {
        let status = ConnectionStatus.error("Some error")
        XCTAssertEqual(status.icon, "exclamationmark.circle.fill")
    }

    // MARK: - Color Tests

    func testDisconnectedColor() {
        let status = ConnectionStatus.disconnected
        XCTAssertEqual(status.color, .secondary)
    }

    func testConnectingColor() {
        let status = ConnectionStatus.connecting
        XCTAssertEqual(status.color, .orange)
    }

    func testConnectedColor() {
        let status = ConnectionStatus.connected
        XCTAssertEqual(status.color, .green)
    }

    func testErrorColor() {
        let status = ConnectionStatus.error("Some error")
        XCTAssertEqual(status.color, .red)
    }

    // MARK: - isActive Tests

    func testDisconnectedNotActive() {
        let status = ConnectionStatus.disconnected
        XCTAssertFalse(status.isActive)
    }

    func testConnectingIsActive() {
        let status = ConnectionStatus.connecting
        XCTAssertTrue(status.isActive)
    }

    func testConnectedIsActive() {
        let status = ConnectionStatus.connected
        XCTAssertTrue(status.isActive)
    }

    func testErrorNotActive() {
        let status = ConnectionStatus.error("Some error")
        XCTAssertFalse(status.isActive)
    }

    // MARK: - Equatable Tests

    func testSameStatusesEqual() {
        XCTAssertEqual(ConnectionStatus.disconnected, ConnectionStatus.disconnected)
        XCTAssertEqual(ConnectionStatus.connecting, ConnectionStatus.connecting)
        XCTAssertEqual(ConnectionStatus.connected, ConnectionStatus.connected)
    }

    func testDifferentStatusesNotEqual() {
        XCTAssertNotEqual(ConnectionStatus.disconnected, ConnectionStatus.connecting)
        XCTAssertNotEqual(ConnectionStatus.connecting, ConnectionStatus.connected)
        XCTAssertNotEqual(ConnectionStatus.connected, ConnectionStatus.error("test"))
    }

    func testErrorsWithSameMessageEqual() {
        let error1 = ConnectionStatus.error("Connection failed")
        let error2 = ConnectionStatus.error("Connection failed")
        XCTAssertEqual(error1, error2)
    }

    func testErrorsWithDifferentMessagesNotEqual() {
        let error1 = ConnectionStatus.error("Connection failed")
        let error2 = ConnectionStatus.error("Timeout")
        XCTAssertNotEqual(error1, error2)
    }

    func testErrorWithEmptyMessage() {
        let error = ConnectionStatus.error("")
        XCTAssertEqual(error.icon, "exclamationmark.circle.fill")
        XCTAssertEqual(error.color, .red)
        XCTAssertFalse(error.isActive)
    }
}
