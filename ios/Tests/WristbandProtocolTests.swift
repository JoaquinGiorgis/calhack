import Foundation
import XCTest
@testable import FortWatchListener

final class WristbandProtocolTests: XCTestCase {
    private func text(_ data: Data?) throws -> String {
        try XCTUnwrap(String(data: XCTUnwrap(data), encoding: .ascii))
    }

    func testFirmwareUUIDsAndGoldenMessages() throws {
        XCTAssertEqual(WristbandProtocol.serviceUUID, "6b1a0001-5d1e-4c3b-9a7e-50554e445345")
        XCTAssertEqual(WristbandProtocol.receiveUUID, "6b1a0002-5d1e-4c3b-9a7e-50554e445345")
        XCTAssertEqual(try text(WristbandProtocol.alert(event: "KNOCK", score: 0.62, angle: -35, quality: 0.81)),
                       "E,KNOCK,0.62,-35,0.81")
        XCTAssertEqual(try text(WristbandProtocol.alert(event: "CAR_HORN", score: 1, angle: 180, quality: 1)),
                       "E,CAR_HORN,1.00,180,1.00")
        XCTAssertEqual(try text(WristbandProtocol.alert(event: "ALARM", score: 0, angle: -180, quality: 0.60)),
                       "E,ALARM,0.00,-180,0.60")
        XCTAssertEqual(try text(WristbandProtocol.alert(event: "ALARM", score: 0.75, angle: -0.1, quality: 0.85)),
                       "E,ALARM,0.75,0,0.85")
    }

    func testInvalidDirectionPreservesAlertWithoutInventingZeroDegrees() throws {
        let invalid: [(Double?, Double?)] = [
            (nil, nil), (nil, 0.9), (35, nil), (.nan, 0.9), (.infinity, 0.9),
            (-.infinity, 0.9), (-180.01, 0.9), (180.01, 0.9),
            (35, .nan), (35, .infinity), (35, -0.1), (35, 1.01), (35, 0.59),
        ]
        for (angle, quality) in invalid {
            XCTAssertEqual(try text(WristbandProtocol.alert(event: "ALARM", score: 0.9, angle: angle, quality: quality)),
                           "E,ALARM,0.90")
        }
    }

    func testRejectsInvalidBaseFieldsInsteadOfSendingPartialMessages() {
        for event in ["", "knock", "KNOCK,ALARM", "ALARM\n", "ALARM\0", "ÁLARM", "A B", String(repeating: "A", count: 24)] {
            XCTAssertNil(WristbandProtocol.alert(event: event, score: 0.9, angle: 0, quality: 1), event)
        }
        for score in [Double.nan, .infinity, -.infinity, -0.001, 1.001] {
            XCTAssertNil(WristbandProtocol.alert(event: "ALARM", score: score, angle: 0, quality: 1))
        }
    }

    func testMaximumEventStaysWithinFirmwareBufferAndUsesASCIIOnly() throws {
        let message = try XCTUnwrap(WristbandProtocol.alert(event: String(repeating: "A", count: 23),
                                                          score: 0.12345, angle: -179.9, quality: 0.999))
        XCTAssertLessThanOrEqual(message.count, 63)
        XCTAssertTrue(message.allSatisfy { $0 >= 32 && $0 < 127 })
        let wire = try text(message)
        XCTAssertEqual(wire.split(separator: ",").count, 5)
        XCTAssertTrue(wire.hasSuffix(",0.12,-180,1.00"))
        XCTAssertEqual(try text(WristbandProtocol.alert(event: "WATER_TAP2", score: 0.75, angle: nil, quality: nil)),
                       "E,WATER_TAP2,0.75")
    }

    func testAbsoluteFreshnessDeadlineDoesNotRestartAtSendTime() {
        let captureFinishedAt = 100.0
        let expiresAt = captureFinishedAt + 0.75
        XCTAssertTrue(WristbandProtocol.isFresh(validUntil: expiresAt, now: captureFinishedAt))
        XCTAssertTrue(WristbandProtocol.isFresh(validUntil: expiresAt, now: 100.74))
        XCTAssertFalse(WristbandProtocol.isFresh(validUntil: expiresAt, now: 100.75))
        XCTAssertFalse(WristbandProtocol.isFresh(validUntil: expiresAt, now: 101.0))
        for invalid in [Double.nan, .infinity, -.infinity] {
            XCTAssertFalse(WristbandProtocol.isFresh(validUntil: invalid, now: 100))
            XCTAssertFalse(WristbandProtocol.isFresh(validUntil: 101, now: invalid))
        }
        XCTAssertFalse(WristbandProtocol.isFresh(validUntil: 1, now: -1))
    }

    func testLevelClampingAndClockMatchFirmwareCommands() throws {
        XCTAssertEqual(try text(WristbandProtocol.level(-3)), "L,0")
        XCTAssertEqual(try text(WristbandProtocol.level(42)), "L,42")
        XCTAssertEqual(try text(WristbandProtocol.level(101)), "L,100")
        let utc = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        XCTAssertEqual(try text(WristbandProtocol.time(date: Date(timeIntervalSince1970: 0), timeZone: utc)),
                       "T,00:00,Thu, Jan 1")
    }
}
