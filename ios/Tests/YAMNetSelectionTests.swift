import Foundation
import XCTest
@testable import FortWatchListener

final class YAMNetSelectionTests: XCTestCase {
    private func scores(_ items: [(String, Double)]) -> [Double] {
        var values = [Double](repeating: 0, count: 521)
        for (name, score) in items {
            guard let entry = SoundCatalog.all.first(where: { $0.name == name }) else {
                XCTFail(name)
                continue
            }
            values[entry.index] = score
        }
        return values
    }

    func testSelectorExposesExactlyTheSameTenAlertsAsTheMac() {
        let expected = Set(SoundIdentity.legacy.map(\.event))
        XCTAssertEqual(expected.count, 10)
        XCTAssertEqual(Set(YAMNetEventSelector.policies.map(\.event)), expected)
        XCTAssertEqual(YAMNetEventSelector.policies.count, 10)
        XCTAssertEqual(YAMNetEventSelector.policies.reduce(0) { $0 + $1.classNames.count }, 36)
        XCTAssertTrue(YAMNetEventSelector.missingClassNames.isEmpty)
    }

    func testEveryConfiguredYAMNetClassMapsToItsLegacyAlert() {
        for policy in YAMNetEventSelector.policies {
            for className in policy.classNames {
                var selector = YAMNetEventSelector()
                let input = scores([(className, 0.99)])
                var output: SoundEventCandidate?
                for hop in 0..<policy.requiredHits {
                    output = selector.select(scores: input, at: 1 + Double(hop) * 0.48)
                }
                XCTAssertEqual(output?.event, policy.event, className)
                XCTAssertEqual(output?.shouldNotify, true, className)
            }
        }
    }

    func testUnconfiguredModelClassesDoNotCreateAlerts() {
        var selector = YAMNetEventSelector()
        for name in ["Meow", "Piano", "Rain", "Typing", "Silence"] {
            XCTAssertNil(selector.select(scores: scores([(name, 0.99)]),
                                         at: 1 + Double(SoundCatalog.all.firstIndex { $0.name == name }!) * 0.01),
                         name)
        }
    }

    func testPriorityCooldownAndKnockGlassVetoMatchMacBehavior() {
        var selector = YAMNetEventSelector()
        let alarmAndDog = scores([("Alarm", 0.60), ("Bark", 0.99)])
        XCTAssertEqual(selector.select(scores: alarmAndDog, at: 1)?.event, "ALARM")
        XCTAssertEqual(selector.select(scores: alarmAndDog, at: 1.48)?.shouldNotify, false)

        selector.reset()
        let woodenImpact = scores([("Glass", 0.70), ("Knock", 0.80)])
        XCTAssertEqual(selector.select(scores: woodenImpact, at: 1)?.event, "KNOCK")
        XCTAssertEqual(selector.select(scores: scores([("Glass", 0.70)]), at: 3.5)?.event, "GLASS")
    }

    func testSpeechNeedsThreeOfFourFreshWindows() {
        var selector = YAMNetEventSelector()
        let speech = scores([("Speech", 0.90)])
        XCTAssertEqual(selector.select(scores: speech, at: 1)?.shouldNotify, false)
        XCTAssertEqual(selector.select(scores: speech, at: 1.48)?.shouldNotify, false)
        XCTAssertEqual(selector.select(scores: speech, at: 1.96)?.shouldNotify, true)
        XCTAssertNil(selector.select(scores: scores([]), at: 2.44))

        selector.reset()
        XCTAssertEqual(selector.select(scores: speech, at: 1)?.shouldNotify, false)
        XCTAssertEqual(selector.select(scores: speech, at: 3)?.shouldNotify, false)
    }

    func testInvalidInputCannotCreateAlerts() {
        var selector = YAMNetEventSelector()
        let alarm = scores([("Alarm", 0.99)])
        XCTAssertNotNil(selector.select(scores: alarm, at: 1))
        XCTAssertNil(selector.select(scores: alarm, at: 1))
        XCTAssertNil(selector.select(scores: alarm, at: .nan))
        XCTAssertNil(selector.select(scores: [], at: 1.1))
        var invalid = alarm
        invalid[0] = .nan
        XCTAssertNil(selector.select(scores: invalid, at: 1.1))
    }

    func testAllCatalogMessagesFitAndInvalidReservedIDsAreRejected() throws {
        for entry in SoundCatalog.all {
            let data = try XCTUnwrap(WristbandProtocol.alert(event: entry.event, score: 0.95,
                                                             angle: -180, quality: 1))
            XCTAssertLessThanOrEqual(data.count, 63)
            XCTAssertEqual(String(data: data, encoding: .ascii), "E,\(entry.event),0.95,-180,1.00")
            XCTAssertEqual(String(data: try XCTUnwrap(WristbandProtocol.display(
                event: entry.event, score: 0.95, angle: -180, quality: 1)), encoding: .ascii),
                           "D,\(entry.event),0.95,-180,1.00")
            XCTAssertEqual(String(data: try XCTUnwrap(WristbandProtocol.patternTest(event: entry.event)),
                                  encoding: .ascii), "P," + entry.event)
        }
        for invalid in ["Y521", "Y999", "Y00", "Y0000", "Y-01", "y001", "Y001,ALARM"] {
            XCTAssertNil(WristbandProtocol.patternTest(event: invalid))
        }
        for invalid in ["Y521", "Y999", "Y00", "Y0000", "YBAD", "Y", "Y_01"] {
            XCTAssertNil(WristbandProtocol.alert(event: invalid, score: 1, angle: nil, quality: nil))
        }
    }
}
