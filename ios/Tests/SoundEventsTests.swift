import Foundation
import AVFoundation
import SoundAnalysis
import XCTest
@testable import FortWatchListener

final class SoundEventsTests: XCTestCase {
#if FORTWATCH_CAPTURE_PROBE
    /// Opt-in physical smoke test. Uses the production pipeline, retains no
    /// audio, and stops after 50 decoded updates. Never runs by default.
    @MainActor
    func testPhysicalSpatialCaptureProvidesValidAudio() async throws {
#if targetEnvironment(simulator)
        throw XCTSkip("Requires a physical iPhone with spatial capture.")
#else
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            XCTFail("Microphone permission was not granted.")
            return
        }
        let outcome = CaptureProbeOutcome()
        let finished = expectation(description: "50 spatial audio updates or a capture error")
        let capture = SpatialCapture { event in
            switch event {
            case .started: break
            case .update:
                if outcome.receiveAudio() { finished.fulfill() }
            case .stopped(let message):
                if outcome.finish(error: message) { finished.fulfill() }
            }
        }
        capture.start()
        defer { capture.stop(message: "Physical capture probe finished.") }
        await fulfillment(of: [finished], timeout: 30)
        XCTAssertNil(outcome.error, outcome.error ?? "")
#endif
    }
#endif
    func testDirectionMarkerStaysWithItsOwnClassificationWindow() {
        let alert = SoundEventDetection(event: "ALARM", score: 0.9, angle: -70, quality: 0.8, expiresAt: 101)
        XCTAssertEqual(SoundDirectionCue.current(liveAngle: 85, alert: alert, at: 100.5),
                       SoundDirectionCue(angle: -70, event: "ALARM"))
        // Once the classified window expires, a newer direction has no category attached.
        XCTAssertEqual(SoundDirectionCue.current(liveAngle: 85, alert: alert, at: 101),
                       SoundDirectionCue(angle: 85, event: nil))
        XCTAssertEqual(SoundDirectionCue.current(liveAngle: nil, alert: alert, at: 102),
                       SoundDirectionCue(angle: nil, event: nil))
    }

    func testUncertainAlertCannotBorrowTheLiveDirection() {
        for (angle, quality): (Double?, Double?) in [(nil, nil), (20, 0.59), (.nan, 0.9),
                                                    (20, .infinity), (181, 0.9), (20, nil)] {
            let alert = SoundEventDetection(event: "KNOCK", score: 0.9, angle: angle,
                                            quality: quality, expiresAt: 101)
            XCTAssertEqual(SoundDirectionCue.current(liveAngle: 85, alert: alert, at: 100),
                           SoundDirectionCue(angle: nil, event: "KNOCK"))
        }
        for angle in [Double.nan, .infinity, -181, 181] {
            XCTAssertNil(SoundDirectionCue.current(liveAngle: angle, alert: nil, at: 100).angle)
        }
    }

    func testEveryEventUsesIdentifiersPresentInApplesBuiltInClassifier() throws {
        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        let selector = SoundEventSelector()
        XCTAssertTrue(selector.missingClassifications(from: Set(request.knownClassifications)).isEmpty)
        XCTAssertEqual(Set(selector.policies.map(\.event)),
                       ["ALARM", "CAR_HORN", "GLASS", "SHOUT", "BABY", "KNOCK", "DOORBELL", "PHONE", "DOG", "SPEECH"])
        let known = Set(selector.policies.flatMap(\.identifiers)).subtracting(["door_bell"])
        XCTAssertEqual(selector.missingClassifications(from: known), ["door_bell"])
    }

    func testMappingsAndPriorityUseExactAppleIdentifiers() {
        let fixtures = [("smoke_detector", "ALARM"), ("air_horn", "CAR_HORN"),
                        ("glass_breaking", "GLASS"), ("children_shouting", "SHOUT"),
                        ("baby_crying", "BABY"), ("knock", "KNOCK"), ("door_bell", "DOORBELL"),
                        ("ringtone", "PHONE"), ("dog_bow_wow", "DOG")]
        for (identifier, event) in fixtures {
            var selector = SoundEventSelector()
            XCTAssertEqual(selector.select(scores: [identifier: 0.95], at: 1)?.event, event)
        }
        var selector = SoundEventSelector()
        XCTAssertEqual(selector.select(scores: ["dog_bark": 0.99, "smoke_detector": 0.70], at: 1)?.event, "ALARM")
        // Only the selected event enters cooldown; a different event may follow.
        XCTAssertEqual(selector.select(scores: ["dog_bark": 0.99, "smoke_detector": 0.70], at: 1.5)?.event, "DOG")
    }

    func testCooldownUsesAudioWindowTimeAndResetClearsHistory() {
        var selector = SoundEventSelector()
        XCTAssertEqual(selector.select(scores: ["knock": 0.9], at: 100)?.event, "KNOCK")
        XCTAssertNil(selector.select(scores: ["knock": 0.9], at: 100.5))
        XCTAssertNil(selector.select(scores: ["knock": 0.9], at: 101.99))
        XCTAssertEqual(selector.select(scores: ["knock": 0.9], at: 102)?.event, "KNOCK")
        selector.reset()
        XCTAssertEqual(selector.select(scores: ["knock": 0.9], at: 0)?.event, "KNOCK")
    }

    func testSpeechRequiresCurrentHitAndThreeOfFourRecentWindows() {
        var selector = SoundEventSelector()
        XCTAssertNil(selector.select(scores: ["speech": 0.9], at: 1))
        XCTAssertNil(selector.select(scores: ["speech": 0.9], at: 1.5))
        XCTAssertNil(selector.select(scores: [:], at: 2))
        XCTAssertEqual(selector.select(scores: ["speech": 0.9], at: 2.5)?.event, "SPEECH")
        XCTAssertNil(selector.select(scores: ["speech": 0.9], at: 3))
        // Existing hit history cannot manufacture a speech event in a silent window.
        XCTAssertNil(selector.select(scores: [:], at: 20))
        selector.reset()
        XCTAssertNil(selector.select(scores: ["speech": 0.9], at: 21))
    }

    func testInvalidScoresAndOutOfOrderResultsCannotGenerateAlerts() {
        var selector = SoundEventSelector()
        for (index, score) in [Double.nan, .infinity, -0.1, 1.01, 0.64].enumerated() {
            XCTAssertNil(selector.select(scores: ["knock": score], at: Double(index)))
        }
        XCTAssertNil(selector.select(scores: ["knock": 1], at: .nan))
        XCTAssertNil(selector.select(scores: ["knock": 1], at: -1))
        XCTAssertNil(selector.select(scores: ["knock": 1], at: 4))
        XCTAssertNil(selector.select(scores: ["knock": 1], at: 3))
        XCTAssertEqual(selector.select(scores: ["knock": 1], at: 5)?.event, "KNOCK")
    }

    func testRingSelectsExactCrossBufferWindowAndItsCaptureDeadline() throws {
        var ring = SpatialSampleRing()
        let rate = 16_000
        let a = [Float](repeating: 0.1, count: 1_600 * 4)
        let b = [Float](repeating: 0.2, count: 1_600 * 4)
        XCTAssertTrue(ring.append(samples: a, sampleRate: rate, startFrame: 0, endUptime: 100.1))
        XCTAssertTrue(ring.append(samples: b, sampleRate: rate, startFrame: 1_600, endUptime: 100.2))
        let window = try XCTUnwrap(ring.window(startFrame: 800, frameCount: 1_600))
        XCTAssertEqual(window.samples, Array(a.suffix(800 * 4)) + Array(b.prefix(800 * 4)))
        XCTAssertEqual(window.endUptime, 100.15, accuracy: 1e-8)
        // A late callback does not acquire a new 750ms validity budget.
        XCTAssertEqual(window.endUptime + 0.75, 100.9, accuracy: 1e-8)
        XCTAssertNil(ring.window(startFrame: 0, frameCount: 3_201))
        XCTAssertNil(ring.window(startFrame: Int64.max, frameCount: 1))
    }

    func testRingIsBoundedAndCannotBridgeMissingAudioOrRateChanges() {
        var ring = SpatialSampleRing()
        let samples = [Float](repeating: 0.1, count: 1_600 * 4)
        for index in 0..<50 {
            XCTAssertTrue(ring.append(samples: samples, sampleRate: 16_000,
                                      startFrame: Int64(index * 1_600), endUptime: Double(index + 1) / 10))
            XCTAssertLessThanOrEqual(ring.storedFrames, 64_000)
        }
        XCTAssertNil(ring.window(startFrame: 0, frameCount: 1_600))
        XCTAssertNotNil(ring.window(startFrame: 16_000, frameCount: 16_000))
        XCTAssertTrue(ring.append(samples: samples, sampleRate: 16_000, startFrame: 81_600, endUptime: 5.2))
        XCTAssertEqual(ring.storedFrames, 1_600)
        XCTAssertNil(ring.window(startFrame: 78_400, frameCount: 4_800))
        XCTAssertTrue(ring.append(samples: samples, sampleRate: 32_000, startFrame: 83_200, endUptime: 5.25))
        XCTAssertEqual(ring.sampleRate, 32_000)
        XCTAssertEqual(ring.storedFrames, 1_600)
        XCTAssertNil(ring.window(startFrame: 81_600, frameCount: 3_200))
        XCTAssertFalse(ring.append(samples: [.nan, 0, 0, 0], sampleRate: 32_000, startFrame: 84_800, endUptime: 5.3))
        XCTAssertEqual(ring.storedFrames, 0)
    }

    func testAlertWindowKeepsOldSoundDirectionWhenNewSoundComesFromOppositeSide() throws {
        // Synthetic FOA: this validates time alignment, not microphone accuracy.
        let rate = 16_000
        func plane(_ angle: Double) -> [Float] {
            let radians = -angle * .pi / 180
            return (0..<1_600).flatMap { frame -> [Float] in
                let w = 0.1 * sin(2 * .pi * 431 * Double(frame) / Double(rate))
                return [Float(w), Float(w * sin(radians)), 0, Float(w * cos(radians))]
            }
        }
        var ring = SpatialSampleRing()
        for index in 0..<10 {
            ring.append(samples: plane(-90), sampleRate: rate,
                        startFrame: Int64(index * 1_600), endUptime: 100 + Double(index + 1) / 10)
        }
        ring.append(samples: plane(90), sampleRate: rate, startFrame: 16_000, endUptime: 101.1)
        let classified = try XCTUnwrap(ring.window(startFrame: 0, frameCount: 16_000))
        let recent = try XCTUnwrap(ring.window(startFrame: 16_000, frameCount: 1_600))
        XCTAssertEqual(try XCTUnwrap(SpatialDirection.estimate(samples: classified.samples, sampleRate: rate).angle), -90, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(SpatialDirection.estimate(samples: recent.samples, sampleRate: rate).angle), 90, accuracy: 0.001)
        XCTAssertEqual(classified.endUptime, 101, accuracy: 1e-8)
        XCTAssertEqual(recent.endUptime, 101.1, accuracy: 1e-8)
    }
}

#if FORTWATCH_CAPTURE_PROBE
private final class CaptureProbeOutcome: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    private var failure: String?
    private var updates = 0
    var error: String? { lock.lock(); defer { lock.unlock() }; return failure }
    func receiveAudio() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !completed else { return false }
        updates += 1
        guard updates >= 50 else { return false }
        completed = true
        return true
    }
    func finish(error: String?) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !completed else { return false }
        completed = true
        failure = error
        return true
    }
}
#endif
