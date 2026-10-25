#if FORTWATCH_BAND_PROBE
import AVFoundation
import Foundation
import XCTest
@testable import FortWatchListener

/// Explicit physical diagnostic. Passing means valid FOA was collected and
/// summarized, never that an angle, calibration, or frequency band is accurate.
final class SpatialBandProbeTests: XCTestCase {
    @MainActor
    func testPhysicalSpatialBandsProduceNumericReport() async throws {
#if targetEnvironment(simulator)
        throw XCTSkip("Requires a physical iPhone with spatial capture.")
#else
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            XCTFail("Microphone permission was not granted.")
            return
        }
        let finished = expectation(description: "Eight seconds of FOA and a numeric band report")
        let outcome = BandProbeOutcome()
        let probe = SpatialBandProbe { result in
            outcome.store(result)
            finished.fulfill()
        }
        probe.start()
        defer { probe.stopAndWait() }
        await fulfillment(of: [finished], timeout: 25)
        let result = try XCTUnwrap(outcome.result, "The capture probe did not finish.")
        let url = try result.get()
        let report = try JSONDecoder().decode(BandProbeReport.self, from: Data(contentsOf: url))
        XCTAssertEqual(report.layout, "ACN_SN3D_W_Y_Z_X")
        XCTAssertEqual(report.capturedFrames, report.sampleRate * 8)
        XCTAssertEqual(report.rows.count, 7 * 4)
        XCTAssertGreaterThan(report.captureUpdates, 0)
        XCTAssertFalse(report.physicalDirectionValidated)
        print("FORTWATCH_BAND_PROBE_REPORT \(url.path)")
#endif
    }
}

private final class BandProbeOutcome: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Result<URL, Error>?
    var result: Result<URL, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
    func store(_ result: Result<URL, Error>) {
        lock.lock()
        defer { lock.unlock() }
        stored = result
    }
}

/// Session and all mutable audio state have one serial owner. The maximum
/// retained PCM is 8 * 48,000 * 4 * 4 = 6,144,000 bytes. Analysis starts only
/// after capture stops and adds one one-second output buffer at a time.
private final class SpatialBandProbe: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.fortwatch.diagnostics.bands", qos: .userInitiated)
    private let session = AVCaptureSession()
    private let output = AVCaptureAudioDataOutput()
    private let completion: (Result<URL, Error>) -> Void
    private var observers: [NSObjectProtocol] = []
    private var watchdog: DispatchSourceTimer?
    private var completed = false
    private var receiving = false
    private var samples: [Float] = []
    private var rate: Int?
    private var firstPTS: Double?
    private var nextPTS: Double?
    private var updates = 0
    private var updatesBySecond = [Int](repeating: 0, count: 8)
    private var startedAt = 0.0

    init(completion: @escaping (Result<URL, Error>) -> Void) {
        self.completion = completion
        super.init()
    }

    func start() {
        queue.async { [self] in
            do {
                startedAt = Date().timeIntervalSince1970
                let previousReport = try reportURL()
                if FileManager.default.fileExists(atPath: previousReport.path) {
                    try FileManager.default.removeItem(at: previousReport)
                }
                session.automaticallyConfiguresApplicationAudioSession = true
                try configure()
                // Observe errors before startRunning, including startup errors.
                for name in [AVCaptureSession.runtimeErrorNotification, AVCaptureSession.wasInterruptedNotification,
                             AVAudioSession.interruptionNotification] {
                    observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                        self?.queue.async { [weak self] in
                            self?.finish(.failure(ListenerError.message("Spatial band probe capture was interrupted.")))
                        }
                    })
                }
                receiving = true
                session.startRunning()
                guard session.isRunning else { throw ListenerError.message("Could not start the spatial band probe.") }
                let timer = DispatchSource.makeTimerSource(queue: queue)
                timer.schedule(deadline: .now() + 15)
                timer.setEventHandler { [weak self] in
                    self?.finish(.failure(ListenerError.message("Spatial band probe timed out before eight seconds of continuous FOA.")))
                }
                watchdog = timer
                timer.resume()
            } catch {
                finish(.failure(error))
            }
        }
    }

    func stopAndWait() {
        queue.sync {
            completed = true
            stopCapture()
            samples.removeAll(keepingCapacity: false)
        }
    }

    private func configure() throws {
        guard let device = AVCaptureDevice.default(for: .audio) else {
            throw ListenerError.message("No microphone is available for the band probe.")
        }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw ListenerError.message("Cannot attach the probe microphone.") }
        session.addInput(input)
        guard input.isMultichannelAudioModeSupported(.firstOrderAmbisonics) else {
            throw ListenerError.message("The microphone does not support first-order Ambisonics.")
        }
        input.multichannelAudioMode = .firstOrderAmbisonics
        if #available(iOS 26.4, *), input.isAudioZoomSupported { input.isAudioZoomEnabled = false }
        output.spatialAudioChannelLayoutTag = SpatialPCM.layoutTag
        guard session.canAddOutput(output) else { throw ListenerError.message("Cannot attach the FOA probe output.") }
        session.addOutput(output)
        output.setSampleBufferDelegate(self, queue: queue)
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard receiving, !completed else { return }
        do {
            let inputs = AVAudioSession.sharedInstance().currentRoute.inputs
            guard inputs.count == 1, inputs[0].portType == .builtInMic else {
                throw ListenerError.message("The band probe requires the built-in microphone throughout capture.")
            }
            let decoded = try SpatialPCM.decode(sampleBuffer)
            // A 96 kHz eight-second recording would exceed the diagnostic RAM
            // budget. Do not silently resample or change production negotiation.
            guard decoded.rate <= 48_000 else {
                throw ListenerError.message("The bounded band probe supports capture rates up to 48 kHz.")
            }
            if let rate, rate != decoded.rate {
                throw ListenerError.message("The sample rate changed during the band probe.")
            }
            if let nextPTS, abs(decoded.pts - nextPTS) > 2.0 / Double(decoded.rate) {
                throw ListenerError.message("Audio was discontinuous during the band probe.")
            }
            if rate == nil {
                rate = decoded.rate
                firstPTS = decoded.pts
                samples.reserveCapacity(decoded.rate * 8 * 4)
            }
            nextPTS = decoded.pts + Double(decoded.samples.count / 4) / Double(decoded.rate)
            let firstFrame = samples.count / 4
            let remainingSamples = decoded.rate * 8 * 4 - samples.count
            let appended = min(remainingSamples, decoded.samples.count)
            guard appended > 0 else { return }
            samples.append(contentsOf: decoded.samples.prefix(appended))
            updates += 1
            let lastFrame = samples.count / 4 - 1
            for second in (firstFrame / decoded.rate)...(lastFrame / decoded.rate) {
                updatesBySecond[second] += 1
            }
            if samples.count == decoded.rate * 8 * 4 {
                stopCapture()
                // Release the final decoded callback buffer before analysis.
                queue.async { [self] in
                    guard !completed else { return }
                    do { finish(.success(try writeReport())) }
                    catch { finish(.failure(error)) }
                }
            }
        } catch {
            finish(.failure(error))
        }
    }

    private func stopCapture() {
        receiving = false
        watchdog?.cancel()
        watchdog = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        output.setSampleBufferDelegate(nil, queue: nil)
        if session.isRunning { session.stopRunning() }
    }

    private func finish(_ result: Result<URL, Error>) {
        guard !completed else { return }
        completed = true
        stopCapture()
        samples.removeAll(keepingCapacity: false)
        completion(result)
    }

    private func reportURL() throws -> URL {
        try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: true)
            .appendingPathComponent("fortwatch-band-probe.json")
    }

    private func writeReport() throws -> URL {
        guard let rate, let firstPTS, samples.count == rate * 8 * 4 else {
            throw ListenerError.message("The band probe did not collect eight complete seconds.")
        }
        var bands = [ProbeBand(name: "fullband", low: nil, high: nil, rate: rate),
                     ProbeBand(name: "300_4000_Hz", low: 300, high: 4_000, rate: rate),
                     ProbeBand(name: "800_4000_Hz", low: 800, high: 4_000, rate: rate),
                     ProbeBand(name: "1500_6000_Hz", low: 1_500, high: 6_000, rate: rate)]
        var rows: [BandProbeRow] = []
        rows.reserveCapacity(28)
        for second in 0..<8 {
            let start = second * rate * 4
            let raw = samples[start..<(start + rate * 4)]
            for index in bands.indices {
                let filtered = bands[index].process(raw)
                // Every filter sees the entire first second before comparisons.
                guard second > 0 else { continue }
                rows.append(BandProbeRow(samples: filtered, rate: rate, band: bands[index].name,
                                         second: second, pts: firstPTS + Double(second),
                                         sourceUpdates: updatesBySecond[second]))
            }
        }
        let report = BandProbeReport(startedAt: startedAt, sampleRate: rate, capturedFrames: samples.count / 4,
                                     captureUpdates: updates, rows: rows)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        let url = try reportURL()
        try data.write(to: url, options: .atomic)
        return url
    }
}

/// Matched one-pole high-pass followed by one-pole low-pass. These are gentle
/// diagnostic bands, not brick-wall filters or proposed production tuning.
private struct ProbeBand {
    let name: String
    private let highPassPole: Double?
    private let lowPassPole: Double?
    private var previousInput = [Double](repeating: 0, count: 4)
    private var highPass = [Double](repeating: 0, count: 4)
    private var lowPass = [Double](repeating: 0, count: 4)

    init(name: String, low: Double?, high: Double?, rate: Int) {
        self.name = name
        highPassPole = low.map { exp(-2 * .pi * $0 / Double(rate)) }
        lowPassPole = high.map { exp(-2 * .pi * $0 / Double(rate)) }
    }

    mutating func process(_ samples: ArraySlice<Float>) -> [Float] {
        var result = [Float](repeating: 0, count: samples.count)
        for (index, sample) in samples.enumerated() {
            let channel = index % 4
            let input = Double(sample)
            var value = input
            if let pole = highPassPole {
                value = pole * (highPass[channel] + input - previousInput[channel])
                previousInput[channel] = input
                highPass[channel] = value
            }
            if let pole = lowPassPole {
                value = (1 - pole) * value + pole * lowPass[channel]
                lowPass[channel] = value
            }
            result[index] = Float(value)
        }
        return result
    }
}

private struct BandProbeReport: Codable {
    var version = 1
    var layout = "ACN_SN3D_W_Y_Z_X"
    var physicalDirectionValidated = false
    var diagnosticOnly = true
    var capturedSeconds = 8
    var filterWarmupSeconds = 1
    var note = "No calibration applied. Raw azimuth is diagnostic only, even when estimator gates pass. No audio is saved."
    let startedAt: Double
    let sampleRate: Int
    let capturedFrames: Int
    let captureUpdates: Int
    let rows: [BandProbeRow]
}

private struct BandProbeRow: Codable {
    let band: String
    let second: Int
    let startPTS: Double
    let endPTS: Double
    let sourceUpdates: Int
    let frames: Int
    let rmsWYZX: [Double]
    let meanWX: Double
    let meanWY: Double
    let meanWZ: Double
    let diagnosticRawAzimuthDegrees: Double?
    let passesEstimatorGates: Bool
    let estimatorReason: String
    let metrics: ProbeMetrics?

    init(samples: [Float], rate: Int, band: String, second: Int, pts: Double, sourceUpdates: Int) {
        self.band = band
        self.second = second
        startPTS = pts
        endPTS = pts + 1
        self.sourceUpdates = sourceUpdates
        frames = samples.count / 4
        var powers = [Double](repeating: 0, count: 4)
        var wx = 0.0, wy = 0.0, wz = 0.0
        for frame in 0..<frames {
            let offset = frame * 4
            let w = Double(samples[offset])
            for channel in 0..<4 {
                let value = Double(samples[offset + channel])
                powers[channel] += value * value
            }
            wy += w * Double(samples[offset + 1])
            wz += w * Double(samples[offset + 2])
            wx += w * Double(samples[offset + 3])
        }
        let count = Double(frames)
        rmsWYZX = powers.map { sqrt($0 / count) }
        meanWX = wx / count
        meanWY = wy / count
        meanWZ = wz / count
        diagnosticRawAzimuthDegrees = hypot(meanWX, meanWY) > 1e-20
            ? SpatialDirection.wrapAngle(-atan2(meanWY, meanWX) * 180 / .pi) : nil
        let estimate = SpatialDirection.estimate(samples: samples, sampleRate: rate)
        passesEstimatorGates = estimate.angle != nil
        estimatorReason = estimate.reason
        metrics = estimate.metrics.map(ProbeMetrics.init)
    }
}

private struct ProbeMetrics: Codable {
    let rms: Double
    let directionalRMS: Double
    let coherence: Double
    let horizontalFraction: Double
    let stability: Double
    let quality: Double

    init(_ metrics: SpatialDirectionMetrics) {
        rms = metrics.rms
        directionalRMS = metrics.directionalRMS
        coherence = metrics.coherence
        horizontalFraction = metrics.horizontalFraction
        stability = metrics.stability
        quality = metrics.quality
    }
}
#endif
