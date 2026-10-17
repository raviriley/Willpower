import XCTest
@testable import WillpowerKit

final class ProcessTimeoutTests: XCTestCase {
    func testMissingExecutableThrowsWithoutWaiting() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/nonexistent-willpower-command")
        XCTAssertThrowsError(try process.runWithTimeout())
    }

    func testHungCommandIsKilled() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]
        let start = Date()
        XCTAssertThrowsError(try process.runWithTimeout(0.1))
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
        XCTAssertFalse(process.isRunning)
    }

    func testNonzeroExitIsReported() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/false")
        XCTAssertThrowsError(try process.runWithTimeout())
    }

    func testLargeOutputDoesNotDeadlock() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/dd")
        process.arguments = ["if=/dev/zero", "bs=1024", "count=1024"]
        process.standardOutput = Pipe()
        process.standardError = FileHandle.nullDevice
        let data = try process.runWithTimeout()
        XCTAssertEqual(data.count, 1024 * 1024)
    }
}
