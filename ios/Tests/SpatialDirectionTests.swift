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

    func testMovementAndQuietRestartCalibrationAccumulation() {
        var calibration = FrontCalibration()
        calibration.start(now: 0)
        for index in 0..<20 {
            calibration.consume(samples: plane(index.isMultiple(of: 2) ? -90 : 90), sampleRate: rate,
                                now: Double(index) * 0.1)
        }
        XCTAssertNil(calibration.zero)
        XCTAssertTrue(calibration.calibrating)
        for index in 0..<9 {
            calibration.consume(samples: plane(0), sampleRate: rate, now: 2 + Double(index) * 0.1)
        }
        calibration.consume(samples: [Float](repeating: 0, count: 6400), sampleRate: rate, now: 2.9)
        calibration.consume(samples: plane(0), sampleRate: rate, now: 3)
        XCTAssertNil(calibration.zero)
        XCTAssertTrue(calibration.calibrating)
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
