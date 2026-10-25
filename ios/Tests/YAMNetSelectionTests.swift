import Foundation
import XCTest
@testable import FortWatchListener

final class YAMNetSelectionTests: XCTestCase {
    private func scores(_ items: [(String, Double)]) -> [Double] {
        var values = [Double](repeating: 0, count: 521)
        for (name, score) in items {
            guard let entry = SoundCatalog.all.first(where: { $0.name == name }) else { XCTFail(name); continue }
            values[entry.index] = score
        }
        return values
    }

    func testEveryNonSilentModelClassCanReachAnExactNamedAlert() {
        for entry in SoundCatalog.all {
            var selector = YAMNetEventSelector()
            var input = [Double](repeating: 0, count: 521)
            input[entry.index] = 0.99
            var output: SoundEventCandidate?
            var notified = false
            for hop in 0..<3 {
                output = selector.select(scores: input, at: 1 + Double(hop) * 0.48)
                notified = notified || output?.shouldNotify == true
            }
            if entry.isQuiet { XCTAssertNil(output) }
            else {
                XCTAssertEqual(output?.event, entry.event, entry.name)
                XCTAssertTrue(notified, entry.name)
            }
        }
    }

    func testSpecificChildReplacesGenericAncestorsAndCooldownCannotPromoteThem() {
        var selector = YAMNetEventSelector()
        let input = scores([("Animal", 0.99), ("Cat", 0.95), ("Meow", 0.80)])
        XCTAssertEqual(selector.select(scores: input, at: 1)?.shouldNotify, false)
        XCTAssertEqual(selector.select(scores: input, at: 1.48)?.event,
                       SoundCatalog.all.first { $0.name == "Meow" }?.event)
        let duringPause = selector.select(scores: input, at: 1.96)
        XCTAssertEqual(duringPause?.event, SoundCatalog.all.first { $0.name == "Meow" }?.event)
        XCTAssertEqual(duringPause?.shouldNotify, false)
        XCTAssertEqual(selector.select(scores: input, at: 2.44)?.shouldNotify, false)
    }

    func testAlarmPriorityAndDifferentFamilyRemainAvailable() {
        var selector = YAMNetEventSelector()
        let mixed = scores([("Meow", 0.99), ("Alarm", 0.70)])
        XCTAssertEqual(selector.select(scores: mixed, at: 1)?.event,
                       SoundCatalog.all.first { $0.name == "Alarm" }?.event)
        XCTAssertEqual(selector.select(scores: mixed, at: 1.48)?.shouldNotify, false)
        XCTAssertEqual(selector.select(scores: scores([("Meow", 0.99)]), at: 1.96)?.event,
                       SoundCatalog.all.first { $0.name == "Meow" }?.event)
    }

    func testFreshnessInvalidScoresQuietAndDiscontinuityCannotCreateAlerts() {
        var selector = YAMNetEventSelector()
        let meow = scores([("Meow", 0.99)])
        XCTAssertEqual(selector.select(scores: meow, at: 1)?.shouldNotify, false)
        XCTAssertEqual(selector.select(scores: meow, at: 3)?.shouldNotify, false) // Gap resets sustained history.
        XCTAssertNil(selector.select(scores: meow, at: 3))
        XCTAssertNil(selector.select(scores: meow, at: .nan))
        XCTAssertNil(selector.select(scores: [], at: 3.1))
        var invalid = meow; invalid[0] = .nan
        XCTAssertNil(selector.select(scores: invalid, at: 3.1))
        XCTAssertEqual(selector.select(scores: meow, at: 3.48)?.shouldNotify, true)
        selector.reset()
        XCTAssertNil(selector.select(scores: scores([("Silence", 1)]), at: 1))
        XCTAssertNil(selector.select(scores: scores([("Silence", 1)]), at: 1.48))
    }

    func testSpecificNewNameCanUpdateWhileItsFamilyVibrationCoolsDown() {
        var selector = YAMNetEventSelector()
        let water = scores([("Water", 0.99)])
        _ = selector.select(scores: water, at: 1)
        XCTAssertEqual(selector.select(scores: water, at: 1.48)?.shouldNotify, true)
        let rain = selector.select(scores: scores([("Water", 0.99), ("Rain", 0.90)]), at: 1.96)
        XCTAssertEqual(rain?.event, SoundCatalog.all.first { $0.name == "Rain" }?.event)
        XCTAssertEqual(rain?.shouldNotify, false)
        // Visual changes preserve the original source window, not an earlier E.
        XCTAssertEqual(String(data: WristbandProtocol.display(event: rain!.event, score: rain!.score,
                                                              angle: 90, quality: 0.9)!, encoding: .ascii),
                       "D," + rain!.event + ",0.90,90,0.90")
    }

    func testAllCatalogMessagesFitAndInvalidReservedIDsAreRejected() throws {
        for entry in SoundCatalog.all {
            let data = try XCTUnwrap(WristbandProtocol.alert(event: entry.event, score: 0.95, angle: -180, quality: 1))
            XCTAssertLessThanOrEqual(data.count, 63)
            XCTAssertEqual(String(data: data, encoding: .ascii), "E,\(entry.event),0.95,-180,1.00")
            XCTAssertEqual(String(data: try XCTUnwrap(WristbandProtocol.display(event: entry.event, score: 0.95, angle: -180, quality: 1)), encoding: .ascii), "D,\(entry.event),0.95,-180,1.00")
            XCTAssertEqual(String(data: try XCTUnwrap(WristbandProtocol.patternTest(event: entry.event)), encoding: .ascii), "P," + entry.event)
        }
        for invalid in ["Y521", "Y999", "Y00", "Y0000", "Y-01", "y001", "Y001,ALARM"] {
            XCTAssertNil(WristbandProtocol.patternTest(event: invalid))
        }
        for invalid in ["Y521", "Y999", "Y00", "Y0000", "YBAD", "Y", "Y_01"] {
            XCTAssertNil(WristbandProtocol.alert(event: invalid, score: 1, angle: nil, quality: nil))
        }
    }
}
