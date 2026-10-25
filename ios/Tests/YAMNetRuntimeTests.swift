import Foundation
import XCTest
@testable import FortWatchListener

final class YAMNetRuntimeTests: XCTestCase {
    func testBundledModelMatchesOriginalTensorFlowAcrossAll521Outputs() throws {
        struct Fixture: Decodable {
            struct Case: Decodable { let name: String; let referenceScores: [Double] }
            let maximumAbsoluteTolerance: Double
            let cases: [Case]
        }
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "yamnet-reference-fixtures", withExtension: "json"))
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        let classifier = try YAMNetClassifier()
        for testCase in fixture.cases {
            let waveform = (0..<15600).map { index -> Float in
                switch testCase.name {
                case "silence": return 0
                case "tone_440Hz": return Float(0.1 * sin(2 * .pi * 440 * Double(index) / 16000))
                case "triangle_64": return Float(abs((index % 64) - 32) - 16) / 128
                default: XCTFail("Unexpected fixture: " + testCase.name); return .nan
                }
            }
            let start = ProcessInfo.processInfo.systemUptime
            let result = try classifier.predict(waveform: waveform)
            let duration = ProcessInfo.processInfo.systemUptime - start
            XCTAssertEqual(result.count, 521)
            XCTAssertEqual(testCase.referenceScores.count, 521)
            let worst = zip(result, testCase.referenceScores).map { abs($0 - $1) }.max() ?? .infinity
            XCTAssertLessThanOrEqual(worst, fixture.maximumAbsoluteTolerance, testCase.name)
            let actualBest = result.indices.max { result[$0] < result[$1] }
            let expectedBest = testCase.referenceScores.indices.max { testCase.referenceScores[$0] < testCase.referenceScores[$1] }
            XCTAssertEqual(actualBest, expectedBest, testCase.name)
            // Functional timing gate on the test host; real microphone latency
            // still includes capture, resampling, queueing and Bluetooth.
            XCTAssertLessThan(duration, 0.75, testCase.name)
            print("YAMNET PARITY \(testCase.name): max error \(worst), prediction \(duration * 1000)ms")
        }
        XCTAssertThrowsError(try classifier.predict(waveform: [0]))
        XCTAssertThrowsError(try classifier.predict(waveform: [Float](repeating: .nan, count: 15600)))
    }

    func testResamplingKeepsPitchLengthAndRejectsAliasesAtEverySupportedRate() throws {
        for rate in SpatialPCM.sampleRates.sorted() {
            func wave(_ frequency: Double) -> [Float] {
                (0..<YAMNetWindowSchedule.windowFrames(at: rate)).flatMap { index -> [Float] in
                    let value = Float(0.25 * sin(2 * .pi * frequency * Double(index) / Double(rate)))
                    return [value, 0.9, -0.5, 0.8] // Y/Z/X must not affect recognition.
                }
            }
            let result = try YAMNetClassifier.waveform(spatial: wave(1000), sampleRate: rate)
            XCTAssertEqual(result.count, 15600)
            let middle = Array(result[800..<14800])
            let rms = sqrt(middle.reduce(0.0) { $0 + Double($1 * $1) } / Double(middle.count))
            XCTAssertEqual(rms, 0.25 / sqrt(2), accuracy: 0.008, "Rate \(rate)")
            let positiveCrossings = zip(middle, middle.dropFirst()).filter { $0 <= 0 && $1 > 0 }.count
            XCTAssertEqual(Double(positiveCrossings) / (Double(middle.count) / 16000), 1000, accuracy: 3)
            if rate >= 24000 {
                let high = try YAMNetClassifier.waveform(spatial: wave(10000), sampleRate: rate)
                let filtered = Array(high[800..<14800])
                let highRMS = sqrt(filtered.reduce(0.0) { $0 + Double($1 * $1) } / Double(filtered.count))
                XCTAssertLessThan(highRMS, 0.015, "Aliasing at source rate \(rate)")
            }
        }
    }

    func testScheduleUsesExactWindowsAndSkipsStaleWork() throws {
        for rate in SpatialPCM.sampleRates {
            var schedule = YAMNetWindowSchedule()
            let count = Int64(YAMNetWindowSchedule.windowFrames(at: rate))
            let hop = Int64((Double(rate) * 0.48).rounded())
            XCTAssertNil(schedule.take(availableFrames: count - 1, sampleRate: rate))
            let first = try XCTUnwrap(schedule.take(availableFrames: count, sampleRate: rate))
            XCTAssertEqual(first.start, 0)
            XCTAssertEqual(first.count, count)
            XCTAssertNil(schedule.take(availableFrames: count + hop - 1, sampleRate: rate))
            let skipped = try XCTUnwrap(schedule.take(availableFrames: count + 4 * hop, sampleRate: rate))
            XCTAssertEqual(skipped.start, 4 * hop)
            XCTAssertNil(schedule.take(availableFrames: count + 4 * hop, sampleRate: rate))
            XCTAssertLessThanOrEqual(abs(Double(count) / Double(rate) - 0.975), 0.51 / Double(rate))
        }
    }
}
