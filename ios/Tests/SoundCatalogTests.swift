import Foundation
import SoundAnalysis
import UIKit
import XCTest
@testable import FortWatchListener

/// Catalog/policy contracts use synthetic scores. They do not measure acoustic
/// recognition, physical direction, or whether people distinguish the rhythms.
final class SoundCatalogTests: XCTestCase {
    private let expectedAliases: [String: Set<String>] = [
        "ALARM": ["alarm_clock", "siren", "civil_defense_siren", "smoke_detector",
                  "police_siren", "ambulance_siren", "fire_engine_siren"],
        "CAR_HORN": ["car_horn", "air_horn"],
        "GLASS": ["glass_breaking"],
        "SHOUT": ["shout", "yell", "children_shouting", "screaming"],
        "BABY": ["baby_crying"],
        "KNOCK": ["knock"],
        "DOORBELL": ["door_bell"],
        "PHONE": ["telephone_bell_ringing", "ringtone"],
        "DOG": ["dog_bark", "dog_bow_wow"],
        "SPEECH": ["speech"]
    ]

    func testCatalogSelectorAndHapticsCoverExactlyTheSameTenEvents() {
        let identities = SoundIdentity.all
        let policies = SoundEventSelector.defaultPolicies
        let patterns = SoundHapticPattern.all
        let expected = Set(expectedAliases.keys)
        XCTAssertEqual(expected.count, 10)
        XCTAssertEqual(Set(identities.map(\.event)), expected)
        XCTAssertEqual(Set(policies.map(\.event)), expected)
        XCTAssertEqual(Set(patterns.map(\.event)), expected)
        // Set equality alone would hide duplicate entries in a displayed list.
        XCTAssertEqual(identities.count, expected.count)
        XCTAssertEqual(policies.count, expected.count)
        XCTAssertEqual(patterns.count, expected.count)
    }

    func testVisibleIdentitiesHaveDistinctIconsTitlesAndSpecificCopy() {
        let identities = SoundIdentity.all
        XCTAssertEqual(Set(identities.map(\.icon)).count, identities.count)
        XCTAssertEqual(Set(identities.map { $0.title.lowercased() }).count, identities.count)
        XCTAssertEqual(Set(identities.map(\.index)).count, identities.count)
        XCTAssertEqual(Set(identities.map(\.summary)).count, identities.count)
        XCTAssertEqual(Set(identities.map(\.examples)).count, identities.count)
        for identity in identities {
            for (field, value) in [("title", identity.title), ("icon", identity.icon),
                                   ("category", identity.category), ("summary", identity.summary),
                                   ("examples", identity.examples)] {
                XCTAssertFalse(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                               "\(identity.event) has no \(field)")
                XCTAssertEqual(value, value.trimmingCharacters(in: .whitespacesAndNewlines),
                               "\(identity.event) \(field) contains surrounding whitespace")
                XCTAssertFalse(["TODO", "TBD", "UNKNOWN"].contains(value.uppercased()),
                               "\(identity.event) \(field) still contains placeholder copy")
            }
            XCTAssertNotEqual(identity.summary.lowercased(), identity.title.lowercased(),
                              "\(identity.event) needs an explanation, not a repeated title")
            XCTAssertNotEqual(identity.examples.lowercased(), identity.title.lowercased(),
                              "\(identity.event) needs examples, not a repeated title")
        }
    }

    func testEventLookupPreservesTheCatalogIdentityAndHapticAssociation() {
        for identity in SoundIdentity.all {
            let lookup = SoundIdentity(event: identity.event)
            XCTAssertEqual(lookup.event, identity.event)
            XCTAssertEqual(lookup.title, identity.title)
            XCTAssertEqual(lookup.icon, identity.icon)
            XCTAssertEqual(lookup.category, identity.category)
            XCTAssertEqual(lookup.summary, identity.summary)
            XCTAssertEqual(lookup.examples, identity.examples)
            XCTAssertEqual(lookup.index, identity.index)
            XCTAssertEqual(lookup.colorHex, identity.colorHex)
            XCTAssertEqual(lookup.signalHex, identity.signalHex)
            XCTAssertEqual(SoundHapticPattern.forEvent(identity.event).event, identity.event)
        }
    }

    @MainActor
    func testEveryCatalogIconExistsOnTheTargetOperatingSystem() {
        for identity in SoundIdentity.all {
            XCTAssertNotNil(UIImage(systemName: identity.icon),
                            "\(identity.event) would display a missing symbol: \(identity.icon)")
        }
    }

    func testCategoryColorsMeetTextAndSignalContrastTargets() {
        let white: UInt32 = 0xFFFFFF
        let brandInk: UInt32 = 0x12141F
        for identity in SoundIdentity.all {
            XCTAssertLessThanOrEqual(identity.colorHex, 0xFFFFFF, "Expected opaque RGB for \(identity.event)")
            XCTAssertLessThanOrEqual(identity.signalHex, 0xFFFFFF, "Expected opaque RGB for \(identity.event)")
            XCTAssertGreaterThanOrEqual(contrast(white, identity.colorHex), 4.5,
                                        "White text needs 4.5:1 on \(identity.event)'s color")
            XCTAssertGreaterThanOrEqual(contrast(identity.signalHex, brandInk), 4.5,
                                        "\(identity.event)'s signal needs 4.5:1 on brand ink")
        }
    }

    func testEveryConfiguredAliasExistsInAppleClassifierAndSelectsItsCategory() throws {
        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        let known = Set(request.knownClassifications)
        let configuredAliases = SoundEventSelector.defaultPolicies.flatMap(\.identifiers)
        let expected = Set(expectedAliases.values.flatMap { $0 })
        XCTAssertEqual(expected.count, 22)
        XCTAssertEqual(Set(configuredAliases), expected)
        XCTAssertEqual(configuredAliases.count, expected.count, "An alias belongs to more than one category")
        XCTAssertTrue(expected.subtracting(known).isEmpty,
                      "Unsupported Apple identifiers: \(expected.subtracting(known).sorted())")

        for (event, aliases) in expectedAliases {
            let policy = try XCTUnwrap(SoundEventSelector.defaultPolicies.first { $0.event == event })
            XCTAssertEqual(policy.identifiers, aliases)
            for alias in aliases {
                // Each alias gets independent history and cooldown state.
                var selector = SoundEventSelector()
                let scores = [alias: 0.99]
                if event == "SPEECH" {
                    XCTAssertNil(selector.select(scores: scores, at: 1), alias)
                    XCTAssertNil(selector.select(scores: scores, at: 1.5), alias)
                    XCTAssertEqual(selector.select(scores: scores, at: 2)?.event, event, alias)
                    // A previous sustained hit cannot classify a silent current window.
                    XCTAssertNil(selector.select(scores: [:], at: 18), alias)
                } else {
                    XCTAssertEqual(selector.select(scores: scores, at: 1)?.event, event, alias)
                }
            }
        }
    }

    private func contrast(_ first: UInt32, _ second: UInt32) -> Double {
        let a = luminance(first), b = luminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    private func luminance(_ rgb: UInt32) -> Double {
        func linear(_ component: UInt32) -> Double {
            let value = Double(component) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear((rgb >> 16) & 0xFF)
            + 0.7152 * linear((rgb >> 8) & 0xFF)
            + 0.0722 * linear(rgb & 0xFF)
    }
}
