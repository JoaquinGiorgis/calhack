import CryptoKit
import Foundation
import UIKit
import XCTest
@testable import FortWatchListener

/// Data and presentation contracts only. These tests do not establish acoustic
/// accuracy, direction accuracy, or perceptual recognition of vibration rhythms.
final class YAMNetCatalogTests: XCTestCase {
    private struct ClassRow {
        let index: Int
        let mid: String
        let name: String
    }

    private enum CSVError: Error {
        case invalidHeader
        case malformedRow(String)
    }

    func testAll521EntriesMatchTheBundledOriginalClassMap() throws {
        let fixture = try classMapData()
        let normalized = Data(String(decoding: fixture, as: UTF8.self)
            .replacingOccurrences(of: "\r\n", with: "\n").utf8)
        let digest = SHA256.hash(data: normalized).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(digest, "b03d48f9ebe23f69ea825193de7e736934086a12410f0af47babe897b78bc0d3",
                       "Do not silently regenerate the model-label ground truth")
        let rows = try parseClassMap(fixture)
        XCTAssertEqual(rows.count, 521)
        XCTAssertEqual(SoundCatalog.all.count, rows.count)
        guard SoundCatalog.all.count == rows.count else { return }

        for (position, row) in rows.enumerated() {
            let entry = SoundCatalog.all[position]
            XCTAssertEqual(row.index, position, "The model output order must not change")
            XCTAssertEqual(entry.index, row.index)
            XCTAssertEqual(entry.mid, row.mid, entry.event)
            XCTAssertEqual(entry.name, row.name, "Keep the exact model label for \(entry.event)")
            XCTAssertEqual(entry.event, String(format: "Y%03d", row.index))
            XCTAssertEqual(SoundCatalog.forEvent(entry.event), entry)
        }
    }

    func testClassIDsNamesAndShortTitlesAreUniqueAndWellFormed() {
        let entries = SoundCatalog.all
        XCTAssertEqual(Set(entries.map(\.event)).count, 521)
        XCTAssertEqual(Set(entries.map(\.index)).count, 521)
        XCTAssertEqual(Set(entries.map(\.mid)).count, 521)
        XCTAssertEqual(Set(entries.map { $0.name.lowercased() }).count, 521)
        XCTAssertEqual(Set(entries.map { $0.title.lowercased() }).count, 521)
        for entry in entries {
            for value in [entry.event, entry.name, entry.title, entry.family, entry.icon, entry.hapticEvent] {
                XCTAssertFalse(value.isEmpty, entry.event)
                XCTAssertEqual(value, value.trimmingCharacters(in: .whitespacesAndNewlines), entry.event)
                XCTAssertFalse(["TODO", "TBD", "UNKNOWN"].contains(value), entry.event)
            }
            XCTAssertTrue(entry.name.utf8.allSatisfy { $0 >= 32 && $0 <= 126 }, entry.event)
            XCTAssertTrue(entry.title.utf8.allSatisfy { $0 >= 32 && $0 <= 126 }, entry.event)
        }
        for invalid in ["", "Y", "Y00", "Y0000", "Y521", "Y999", "Y-01", "y000",
                        " Y000", "Y000 ", "Y00x", "Y１２３", "ALARM"] {
            XCTAssertNil(SoundCatalog.forEvent(invalid), "Reject malformed class ID \(invalid)")
        }
    }

    func testEveryIdentityKeepsItsSpecificModelNameAndMetadata() throws {
        XCTAssertEqual(SoundIdentity.all.count, 521)
        XCTAssertEqual(Set(SoundIdentity.all.map(\.event)), Set(SoundCatalog.all.map(\.event)))
        XCTAssertEqual(SoundIdentity.library.count, 10)
        XCTAssertEqual(Set(SoundIdentity.library.map(\.event)), Set(SoundIdentity.legacy.map(\.event)))
        for identity in SoundIdentity.all {
            let entry = try XCTUnwrap(SoundCatalog.forEvent(identity.event))
            XCTAssertEqual(identity.index, entry.index)
            XCTAssertEqual(identity.title, entry.title)
            // A shortened heading must leave the complete class label visible
            // in its supporting text, rather than collapse to a family name.
            XCTAssertTrue(identity.title == entry.name || identity.summary == entry.name,
                          "\(identity.event) loses its exact class name: \(entry.name)")
            XCTAssertEqual(identity.icon, entry.icon)
            XCTAssertEqual(identity.colorHex, entry.colorHex)
            XCTAssertEqual(identity.signalHex, entry.signalHex)
            XCTAssertEqual(identity.category, entry.familyTitle.uppercased())
            XCTAssertEqual(SoundIdentity(event: identity.event).event, identity.event)
        }
        XCTAssertEqual(SoundIdentity.legacy.count, 10)
        XCTAssertTrue(Set(SoundIdentity.legacy.map(\.event)).isDisjoint(with: Set(SoundIdentity.all.map(\.event))))
        XCTAssertEqual(SoundIdentity(event: "ALARM").title, "ALARM")
        XCTAssertEqual(SoundIdentity(event: "Y521").event, "UNKNOWN")
    }

    @MainActor
    func testEveryCatalogSymbolExistsOnTheTargetOS() {
        for entry in SoundCatalog.all {
            XCTAssertNotNil(UIImage(systemName: entry.icon), "Missing \(entry.icon) for \(entry.event) \(entry.name)")
        }
    }

    func testCatalogColorsRemainReadableOnSolidAndBoundedGlassSurfaces() {
        let white = components(0xFFFFFF)
        let ink = components(0x12141F)
        for entry in SoundCatalog.all {
            XCTAssertLessThanOrEqual(entry.colorHex, 0xFFFFFF, entry.event)
            XCTAssertLessThanOrEqual(entry.signalHex, 0xFFFFFF, entry.event)
            let surface = components(entry.colorHex)
            XCTAssertGreaterThanOrEqual(contrast(white, surface), 4.5, entry.event)
            XCTAssertGreaterThanOrEqual(contrast(components(entry.signalHex), ink), 4.5, entry.event)

            // The photo/material can be as bright as white. The production card
            // bounds it with 86% ink, then overlays 58% category color.
            let boundedBackdrop = composite(ink, alpha: 0.86, over: white)
            let tintedGlass = composite(surface, alpha: 0.58, over: boundedBackdrop)
            let secondaryText = composite(white, alpha: 0.84, over: tintedGlass)
            XCTAssertGreaterThanOrEqual(contrast(secondaryText, tintedGlass), 4.5,
                                       "Secondary text over bright-photo glass: \(entry.event)")
        }
    }

    func testFamiliesAndHapticKeysResolveWithoutInventingOnePatternPerClass() throws {
        let expectedFamilies: Set<String> = ["HUMAN", "ANIMAL", "MUSIC", "NATURE", "VEHICLE", "HOUSEHOLD", "MACHINE", "OTHER"]
        XCTAssertEqual(Set(SoundCatalog.families), expectedFamilies)
        XCTAssertEqual(SoundCatalog.families.count, expectedFamilies.count)
        XCTAssertEqual(Set(SoundCatalog.all.map(\.family)), expectedFamilies)
        XCTAssertEqual(Set(SoundCatalog.families.map { SoundCatalog.familyTitle(for: $0) }).count, 8)
        let patterns = Dictionary(uniqueKeysWithValues: SoundHapticPattern.all.map { ($0.event, $0) })
        let allowedKeys = expectedFamilies.union(Set(SoundIdentity.legacy.map(\.event))).union(["QUIET"])
        for entry in SoundCatalog.all {
            XCTAssertTrue(allowedKeys.contains(entry.hapticEvent), entry.event)
            let configured = try XCTUnwrap(patterns[entry.hapticEvent], entry.event)
            XCTAssertTrue(SoundHapticPattern.supports(entry.event), entry.event)
            XCTAssertEqual(SoundHapticPattern.forEvent(entry.event), configured, entry.event)
            XCTAssertFalse(entry.familyTitle.isEmpty, entry.event)
            if !entry.isQuiet {
                let pattern = SoundHapticPattern.forEvent(entry.event)
                XCTAssertFalse(pattern.segments.isEmpty, entry.event)
                XCTAssertEqual(pattern.segments.count % 2, 1, entry.event)
                XCTAssertTrue(pattern.segments.allSatisfy { $0 > 0 }, entry.event)
            }
        }
    }

    func testSilenceIsTheOnlyQuietClassAndNeverHasAHapticPulse() throws {
        XCTAssertEqual(SoundCatalog.all.filter(\.isQuiet).map(\.event), ["Y494"])
        let silence = try XCTUnwrap(SoundCatalog.forEvent("Y494"))
        XCTAssertEqual(silence.name, "Silence")
        XCTAssertEqual(silence.hapticEvent, "QUIET")
        XCTAssertEqual(silence.icon, "speaker.slash")
        XCTAssertTrue(SoundHapticPattern.forEvent(silence.event).segments.isEmpty)
    }

    func testParentIndicesAreValidCompleteAndAcyclic() {
        let entries = SoundCatalog.all
        for entry in entries {
            XCTAssertEqual(entry.parentIndices, Array(Set(entry.parentIndices)).sorted(), entry.event)
            XCTAssertFalse(entry.parentIndices.contains(entry.index), entry.event)
            for parent in entry.parentIndices {
                guard entries.indices.contains(parent) else {
                    XCTFail("Out-of-range parent \(parent) for \(entry.event)")
                    continue
                }
                XCTAssertTrue(Set(entries[parent].parentIndices).isSubset(of: Set(entry.parentIndices)),
                              "Missing transitive ancestors of \(entries[parent].name) for \(entry.event)")
            }
        }
        var state = Array(repeating: 0, count: entries.count)
        func hasCycle(_ index: Int) -> Bool {
            guard entries.indices.contains(index) else { return false }
            if state[index] == 1 { return true }
            if state[index] == 2 { return false }
            state[index] = 1
            for parent in entries[index].parentIndices where hasCycle(parent) { return true }
            state[index] = 2
            return false
        }
        for index in entries.indices {
            XCTAssertFalse(hasCycle(index), "Cycle in ancestry starting at Y\(index)")
        }
    }

    func testSpecificClassesKeepMeaningfulFamiliesAndLegacyRhythmAssociations() throws {
        let expected: [(String, String, String, String)] = [
            ("Y000", "Speech", "HUMAN", "SPEECH"),
            ("Y006", "Shout", "HUMAN", "SHOUT"),
            ("Y020", "Baby cry, infant cry", "HUMAN", "BABY"),
            ("Y070", "Bark", "ANIMAL", "DOG"),
            ("Y074", "Growling", "ANIMAL", "ANIMAL"),
            ("Y132", "Music", "MUSIC", "MUSIC"),
            ("Y283", "Rain", "NATURE", "NATURE"),
            ("Y294", "Vehicle", "VEHICLE", "VEHICLE"),
            ("Y302", "Vehicle horn, car horn, honking", "VEHICLE", "CAR_HORN"),
            ("Y337", "Engine", "MACHINE", "MACHINE"),
            ("Y348", "Door", "HOUSEHOLD", "HOUSEHOLD"),
            ("Y349", "Doorbell", "HOUSEHOLD", "DOORBELL"),
            ("Y353", "Knock", "HOUSEHOLD", "KNOCK"),
            ("Y385", "Ringtone", "MACHINE", "PHONE"),
            ("Y390", "Siren", "MACHINE", "ALARM"),
            ("Y437", "Shatter", "OTHER", "GLASS"),
            ("Y520", "Field recording", "OTHER", "OTHER")
        ]
        for (event, name, family, haptic) in expected {
            let entry = try XCTUnwrap(SoundCatalog.forEvent(event))
            XCTAssertEqual(entry.name, name, event)
            XCTAssertEqual(entry.family, family, event)
            XCTAssertEqual(entry.hapticEvent, haptic, event)
        }
    }

    func testKnownSpecificityRelationshipsIncludeAllModeledBranches() throws {
        let expected: [String: [Int]] = [
            "Y001": [0],
            "Y070": [67, 68, 69],
            "Y136": [132, 133, 134, 135],
            "Y283": [282],
            "Y302": [294, 300, 301, 382],
            "Y339": [337, 338, 412, 418, 419],
            "Y349": [348, 382],
            "Y390": [382]
        ]
        for (event, indices) in expected {
            let entry = try XCTUnwrap(SoundCatalog.forEvent(event))
            XCTAssertEqual(entry.parentIndices, indices, "Specificity graph for \(event)")
        }
    }

    private func classMapData() throws -> Data {
        let bundle = Bundle(for: YAMNetCatalogTests.self)
        let url = try XCTUnwrap(bundle.url(forResource: "yamnet_class_map_expected", withExtension: "csv")
            ?? bundle.url(forResource: "yamnet_class_map_expected", withExtension: "csv", subdirectory: "Fixtures"),
                               "The original YAMNet CSV must be bundled with the test target")
        return try Data(contentsOf: url)
    }

    private func parseClassMap(_ data: Data) throws -> [ClassRow] {
        let lines = String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline)
        guard lines.first == "index,mid,display_name" else { throw CSVError.invalidHeader }
        return try lines.dropFirst().map { line in
            let characters = Array(line)
            var fields: [String] = []
            var field = ""
            var quoted = false
            var offset = 0
            while offset < characters.count {
                let character = characters[offset]
                if character == "\"" {
                    if quoted, offset + 1 < characters.count, characters[offset + 1] == "\"" {
                        field.append("\"")
                        offset += 1
                    } else {
                        quoted.toggle()
                    }
                } else if character == ",", !quoted {
                    fields.append(field)
                    field = ""
                } else {
                    field.append(character)
                }
                offset += 1
            }
            fields.append(field)
            guard !quoted, fields.count == 3, let index = Int(fields[0]) else {
                throw CSVError.malformedRow(String(line))
            }
            return ClassRow(index: index, mid: fields[1], name: fields[2])
        }
    }

    private func components(_ rgb: UInt32) -> [Double] {
        [Double((rgb >> 16) & 0xFF) / 255, Double((rgb >> 8) & 0xFF) / 255, Double(rgb & 0xFF) / 255]
    }

    private func composite(_ foreground: [Double], alpha: Double, over background: [Double]) -> [Double] {
        zip(foreground, background).map { $0 * alpha + $1 * (1 - alpha) }
    }

    private func contrast(_ a: [Double], _ b: [Double]) -> Double {
        func luminance(_ rgb: [Double]) -> Double {
            let linear = rgb.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
        }
        let first = luminance(a), second = luminance(b)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }
}
