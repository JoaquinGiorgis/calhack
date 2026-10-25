import Foundation
import XCTest
@testable import FortWatchListener

/// Synthetic FOA validates the math, not the physical microphone accuracy.
final class SpatialDirectionTests: XCTestCase {
    private let rate = 16_000

    private func plane(_ angle: Double, seconds: Double = 0.1, elevation: Double = 0) -> [Float] {
        let azimuth = -angle * .pi / 180
        let altitude = elevation * .pi / 180
        let frames = Int(Double(rate) * seconds)
        var samples = [Float]()
        samples.reserveCapacity(frames * 4)
        for index in 0..<frames {
            let w = 0.1 * sin(2 * .pi * 431 * Double(index) / Double(rate))
            samples.append(contentsOf: [Float(w), Float(w * sin(azimuth) * cos(altitude)),
                                        Float(w * sin(altitude)), Float(w * cos(azimuth) * cos(altitude))])
        }
        return samples
    }

    func testFrontSidesBackAndWrap() throws {
        for angle: Double in [-180, -179, -135, -90, -45, 0, 45, 90, 135, 179, 180] {
            let result = SpatialDirection.estimate(samples: plane(angle, seconds: 1), sampleRate: rate)
            let measured = try XCTUnwrap(result.angle)
            XCTAssertEqual(SpatialDirection.wrapAngle(measured - angle), 0, accuracy: 0.0001)
            XCTAssertGreaterThan(try XCTUnwrap(result.quality), 0.99)
        }
        XCTAssertEqual(SpatialDirection.wrapAngle(540), -180)
        XCTAssertEqual(SpatialDirection.wrapAngle(-541), 179)
        XCTAssertTrue(SpatialDirection.wrapAngle(.infinity).isNaN)
    }

    func testRejectedDirectionKeepsDiagnosticsWithoutAnAngle() throws {
        let quiet = SpatialDirection.estimate(samples: [Float](repeating: 0, count: rate * 4), sampleRate: rate)
        XCTAssertNil(quiet.angle)
        XCTAssertNil(quiet.quality)
        XCTAssertEqual(try XCTUnwrap(quiet.metrics).rms, 0)
        let vertical = SpatialDirection.estimate(samples: plane(0, elevation: 89), sampleRate: rate)
        let metrics = try XCTUnwrap(vertical.metrics)
        XCTAssertEqual(vertical.reason, "vertical_or_diffuse")
        XCTAssertNil(vertical.angle)
        XCTAssertNil(vertical.quality)
        XCTAssertGreaterThan(metrics.coherence, 0.99)
        XCTAssertLessThan(metrics.horizontalFraction, 0.5)
        XCTAssertLessThan(metrics.quality, SpatialDirection.minimumQuality)
        XCTAssertNil(SpatialDirectionMetrics(rms: .nan, coherence: 1, horizontalFraction: 1, stability: 1, quality: 1))
    }

    func testCalibrationTimeoutKeepsItsFailureEvidenceUntilRetry() throws {
        var calibration = FrontCalibration()
        calibration.start(now: 10)
        calibration.consume(samples: plane(0, elevation: 89), sampleRate: rate, now: 10.1)
        let before = try XCTUnwrap(calibration.lastResult?.metrics)
        calibration.consume(samples: plane(0), sampleRate: rate, now: 20.1)
        XCTAssertTrue(calibration.failed)
        XCTAssertEqual(calibration.lastResult?.reason, "calibration_timeout")
        XCTAssertEqual(calibration.lastResult?.metrics, before)
        XCTAssertNil(calibration.lastResult?.angle)
        XCTAssertNil(calibration.zero)
        calibration.start(now: 21)
        XCTAssertFalse(calibration.failed)
        XCTAssertNil(calibration.lastResult)
    }

    func testRotatedZeroCrossesTheBackBoundary() throws {
        let result = SpatialDirection.estimate(samples: plane(-175), sampleRate: rate, zero: 175)
        XCTAssertEqual(try XCTUnwrap(result.angle), 10, accuracy: 0.0001)
        let result2 = SpatialDirection.estimate(samples: plane(75), sampleRate: rate, zero: 30)
        XCTAssertEqual(try XCTUnwrap(result2.angle), 45, accuracy: 0.0001)
    }

    func testSilenceDiffuseVerticalAndMovingSoundStayUnknown() {
        var diffuse = [Float]()
        for index in 0..<rate {
            let time = Double(index) / Double(rate)
            diffuse.append(contentsOf: [431.0, 619, 827, 1049].map { Float(0.1 * sin(2 * .pi * $0 * time)) })
        }
        let fixtures = [[Float](repeating: 0, count: rate * 4), diffuse,
                        plane(0, seconds: 1, elevation: 89),
                        plane(-90, seconds: 0.5) + plane(90, seconds: 0.5)]
        for samples in fixtures {
            let result = SpatialDirection.estimate(samples: samples, sampleRate: rate)
            XCTAssertNil(result.angle)
            XCTAssertNil(result.quality)
        }
    }

    func testInvalidSamplesRateAndZeroCannotProduceAnArrow() {
        for samples: [Float] in [[0, 1, 2], [.nan, 0, 0, 0], [0, .infinity, 0, 0],
                                 [0, 0, -9, 0], [Float](repeating: 0, count: rate * 4 * 3)] {
            XCTAssertEqual(SpatialDirection.estimate(samples: samples, sampleRate: rate).reason, "invalid_input")
        }
        for sampleRate in [0, -1, Int.max, 8_000] {
            XCTAssertNil(SpatialDirection.estimate(samples: plane(0), sampleRate: sampleRate).angle)
        }
        XCTAssertNil(SpatialDirection.estimate(samples: plane(0), sampleRate: rate, zero: .nan).angle)
        XCTAssertNil(SpatialDirection.estimate(samples: [], sampleRate: rate).angle)
    }

    func testCalibrationNeedsAFullStableSecondAndCanReset() throws {
        var calibration = FrontCalibration()
        calibration.start(now: 100)
        for index in 0..<9 {
            calibration.consume(samples: plane(30), sampleRate: rate, now: 100 + Double(index) * 0.1)
            XCTAssertNil(calibration.zero)
            XCTAssertTrue(calibration.calibrating)
        }
        calibration.consume(samples: plane(30), sampleRate: rate, now: 100.9)
        XCTAssertEqual(try XCTUnwrap(calibration.zero), 30, accuracy: 0.0001)
        XCTAssertFalse(calibration.calibrating)
        XCTAssertFalse(calibration.failed)
        calibration.reset()
        XCTAssertNil(calibration.zero)
        XCTAssertFalse(calibration.calibrating)
    }

    func testCalibrationUsesCircularMeanNearBack() throws {
        var calibration = FrontCalibration()
        calibration.start(now: 10)
        for index in 0..<10 {
            calibration.consume(samples: plane(index.isMultiple(of: 2) ? 179 : -179), sampleRate: rate,
                                now: 10 + Double(index) * 0.1)
        }
        let zero = try XCTUnwrap(calibration.zero)
        XCTAssertEqual(abs(zero), 180, accuracy: 0.0001)
    }

    func testMovementAndLongQuietCannotCalibrate() {
        var calibration = FrontCalibration()
        calibration.start(now: 0)
        for index in 0..<20 {
            calibration.consume(samples: plane(index.isMultiple(of: 2) ? -90 : 90), sampleRate: rate,
                                now: Double(index) * 0.1)
        }
        XCTAssertNil(calibration.zero)
        XCTAssertTrue(calibration.calibrating)
        for index in 0..<6 {
            calibration.consume(samples: plane(0), sampleRate: rate, now: 2 + Double(index) * 0.1)
        }
        // More than 200 ms without signal clears the rolling evidence.
        for index in 0..<3 {
            calibration.consume(samples: [Float](repeating: 0, count: 6400), sampleRate: rate,
                                now: 2.6 + Double(index) * 0.1)
        }
        calibration.consume(samples: plane(0), sampleRate: rate, now: 2.9)
        XCTAssertNil(calibration.zero)
        XCTAssertTrue(calibration.calibrating)
    }

    func testWeakChunkDoesNotEraseAnOtherwiseCoherentSecond() throws {
        var calibration = FrontCalibration()
        calibration.start(now: 0)
        // Same front source; one short interval has no directional component.
        // It cannot pass the per-chunk gate, but the complete second and halves can.
        var weak = plane(35)
        for frame in 0..<(weak.count / 4) {
            weak[frame * 4 + 1] = 0
            weak[frame * 4 + 2] = 0
            weak[frame * 4 + 3] = 0
        }
        XCTAssertNil(SpatialDirection.estimate(samples: weak, sampleRate: rate).angle)
        for index in 0..<10 {
            calibration.consume(samples: index == 4 ? weak : plane(35), sampleRate: rate,
                                now: Double(index) * 0.1)
            if index < 9 { XCTAssertNil(calibration.zero) }
        }
        XCTAssertEqual(try XCTUnwrap(calibration.zero), 35, accuracy: 0.0001)
        XCTAssertEqual(calibration.attemptedDuration, 1, accuracy: 1e-8)
        XCTAssertEqual(calibration.candidateWindows, 1)
        XCTAssertEqual(calibration.acceptedWindows, 1)
        XCTAssertGreaterThanOrEqual(calibration.bestQuality, SpatialDirection.minimumQuality)
        XCTAssertFalse(calibration.calibrating)
    }

    func testBriefSilenceCanPassButLoudShortBurstCannot() throws {
        var calibration = FrontCalibration()
        calibration.start(now: 0)
        for index in 0..<10 {
            calibration.consume(samples: index == 4 ? [Float](repeating: 0, count: 6400) : plane(20),
                                sampleRate: rate, now: Double(index) * 0.1)
        }
        XCTAssertEqual(try XCTUnwrap(calibration.zero), 20, accuracy: 0.0001)

        calibration.start(now: 10)
        // Repeated 100 ms bursts keep the buffer from seeing >200 ms continuous
        // silence, but still supply far less than 800 ms of active audio per second.
        let loud = plane(20).map { $0 * 50 }
        for index in 0..<30 {
            calibration.consume(samples: index.isMultiple(of: 3) ? loud : [Float](repeating: 0, count: 6400),
                                sampleRate: rate, now: 10 + Double(index) * 0.1)
        }
        XCTAssertNil(calibration.zero)
        XCTAssertTrue(calibration.calibrating)
        XCTAssertEqual(calibration.acceptedWindows, 0)
        XCTAssertEqual(calibration.lastRejectionReason, "calibration_insufficient_activity")
    }

    func testWholeWindowAverageCannotHideChangingOrAlternatingDirections() {
        for alternating in [false, true] {
            var calibration = FrontCalibration()
            calibration.start(now: 0)
            for index in 0..<10 {
                let angle: Double = alternating ? (index.isMultiple(of: 2) ? -30 : 30) : (index < 5 ? -20 : 20)
                calibration.consume(samples: plane(angle), sampleRate: rate, now: Double(index) * 0.1)
            }
            XCTAssertGreaterThan(calibration.bestQuality, SpatialDirection.minimumQuality)
            XCTAssertNil(calibration.zero)
            XCTAssertEqual(calibration.lastRejectionReason, "calibration_direction_changed")
        }
    }

    func testUncertainHalfCannotBorrowTheOtherHalfsDirection() {
        var calibration = FrontCalibration()
        calibration.start(now: 0)
        for index in 0..<10 {
            // Three of the first five chunks have no directional component;
            // the full second is acceptable, but its first half is not.
            var samples = plane(0)
            if index < 3 {
                for frame in 0..<(samples.count / 4) {
                    samples[frame * 4 + 1] = 0
                    samples[frame * 4 + 2] = 0
                    samples[frame * 4 + 3] = 0
                }
            }
            calibration.consume(samples: samples, sampleRate: rate, now: Double(index) * 0.1)
        }
        XCTAssertGreaterThan(calibration.bestQuality, SpatialDirection.minimumQuality)
        XCTAssertNil(calibration.zero)
        XCTAssertEqual(calibration.lastRejectionReason, "calibration_halves_uncertain")
    }

    func testRollingWindowRecoversAndAttemptStatisticsEndAtTimeout() throws {
        var calibration = FrontCalibration()
        calibration.start(now: 0)
        for index in 0..<20 {
            calibration.consume(samples: plane(index.isMultiple(of: 2) ? -30 : 30), sampleRate: rate,
                                now: Double(index) * 0.1)
        }
        XCTAssertNil(calibration.zero)
        XCTAssertEqual(calibration.bufferedDuration, 1, accuracy: 1e-8)
        for index in 0..<10 {
            calibration.consume(samples: plane(0), sampleRate: rate, now: 2 + Double(index) * 0.1)
        }
        XCTAssertEqual(try XCTUnwrap(calibration.zero), 0, accuracy: 0.0001)
        XCTAssertEqual(calibration.acceptedWindows, 1)

        calibration.start(now: 10)
        for index in 0..<10 {
            calibration.consume(samples: plane(index.isMultiple(of: 2) ? -30 : 30), sampleRate: rate,
                                now: 10 + Double(index) * 0.1)
        }
        let duration = calibration.attemptedDuration
        let candidates = calibration.candidateWindows
        let peak = calibration.bestQuality
        calibration.consume(samples: plane(0), sampleRate: rate, now: 20.1)
        XCTAssertTrue(calibration.failed)
        XCTAssertEqual(calibration.lastResult?.reason, "calibration_timeout")
        XCTAssertEqual(calibration.lastRejectionReason, "calibration_direction_changed")
        calibration.consume(samples: plane(0), sampleRate: rate, now: 21)
        XCTAssertEqual(calibration.attemptedDuration, duration)
        XCTAssertEqual(calibration.candidateWindows, candidates)
        XCTAssertEqual(calibration.bestQuality, peak)
        XCTAssertEqual(calibration.acceptedWindows, 0)
        calibration.start(now: 22)
        XCTAssertEqual(calibration.attemptedDuration, 0)
        XCTAssertEqual(calibration.candidateWindows, 0)
        XCTAssertEqual(calibration.acceptedWindows, 0)
        XCTAssertEqual(calibration.bestQuality, 0)
        XCTAssertNil(calibration.lastRejectionReason)
        XCTAssertEqual(calibration.bufferedDuration, 0)
    }

    func testRateChangeCannotMixCalibrationEvidence() {
        var calibration = FrontCalibration()
        calibration.start(now: 0)
        calibration.consume(samples: plane(0), sampleRate: rate, now: 0.1)
        calibration.consume(samples: plane(0), sampleRate: 48_000, now: 0.2)
        XCTAssertTrue(calibration.failed)
        XCTAssertNil(calibration.zero)
        XCTAssertEqual(calibration.lastResult?.reason, "calibration_rate_changed")
        XCTAssertEqual(calibration.bufferedDuration, 0)
    }

    func testTimeoutAndInvalidInputFailWithoutKeepingOldZero() {
        var calibration = FrontCalibration()
        calibration.start(now: 1)
        calibration.consume(samples: plane(0), sampleRate: rate, now: 11.01)
        XCTAssertTrue(calibration.failed)
        XCTAssertFalse(calibration.calibrating)
        XCTAssertNil(calibration.zero)

        for now in [Double.nan, .infinity, -1] {
            calibration.start(now: now)
            XCTAssertTrue(calibration.failed)
            XCTAssertFalse(calibration.calibrating)
        }
        calibration.start(now: 10)
        calibration.consume(samples: plane(0), sampleRate: rate, now: 9)
        XCTAssertTrue(calibration.failed)
        calibration.start(now: 10)
        calibration.consume(samples: [.nan, 0, 0, 0], sampleRate: rate, now: 10.1)
        XCTAssertTrue(calibration.failed)
        XCTAssertNil(calibration.zero)
    }
}
