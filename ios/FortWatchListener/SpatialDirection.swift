import Foundation

/// Numeric summaries only; no audio samples or source identity are retained.
struct SpatialDirectionMetrics: Equatable, Sendable {
    let rms: Double
    let coherence: Double
    let horizontalFraction: Double
    let stability: Double
    let quality: Double
    let directionalRMS: Double

    init?(rms: Double, coherence: Double, horizontalFraction: Double, stability: Double, quality: Double,
          directionalRMS: Double = 0) {
        guard [rms, coherence, horizontalFraction, stability, quality, directionalRMS].allSatisfy(\.isFinite) else { return nil }
        self.rms = rms
        self.coherence = coherence
        self.horizontalFraction = horizontalFraction
        self.stability = stability
        self.quality = quality
        self.directionalRMS = directionalRMS
    }
}

/// An estimate of the dominant sound, not separation of a classified event.
/// Quality measures coherence and stability; it is not an accuracy probability.
struct SpatialDirectionResult: Equatable, Sendable {
    let angle: Double?
    let quality: Double?
    let reason: String
    let metrics: SpatialDirectionMetrics?

    init(angle: Double?, quality: Double?, reason: String, metrics: SpatialDirectionMetrics? = nil) {
        self.angle = angle
        self.quality = quality
        self.reason = reason
        self.metrics = metrics
    }
}

enum SpatialDirection {
    static let minimumQuality = 0.60
    static let minimumRMS = 0.0001
    static let supportedSampleRates: Set<Int> = [16_000, 24_000, 32_000, 44_100, 48_000, 96_000]

    /// ACN/SN3D interleaved W,Y,Z,X. X/Y form the assumed horizontal plane.
    /// Keep the phone upright and fixed; verify physical axes before relying on it.
    static func estimate(samples: [Float], sampleRate: Int, zero: Double = 0) -> SpatialDirectionResult {
        guard zero.isFinite, supportedSampleRates.contains(sampleRate),
              samples.count.isMultiple(of: 4), samples.count <= sampleRate * 4 * 2 else {
            return unknown("invalid_input")
        }
        guard !samples.isEmpty else { return unknown("warming_up") }

        let frames = samples.count / 4
        let blockSize = max(1, Int(Double(sampleRate) * 0.025))
        var power = 0.0
        var directionalPower = 0.0
        var vector = Vector()
        var blockVector = Vector()
        var blockPower = 0.0
        var blockFrames = 0
        var normalizedBlocks = Vector()
        var validBlocks = 0

        for frame in 0..<frames {
            let offset = frame * 4
            let w = Double(samples[offset])
            let y = Double(samples[offset + 1])
            let z = Double(samples[offset + 2])
            let x = Double(samples[offset + 3])
            guard w.isFinite, x.isFinite, y.isFinite, z.isFinite,
                  abs(w) <= 8, abs(x) <= 8, abs(y) <= 8, abs(z) <= 8 else {
                return unknown("invalid_input")
            }
            let intensity = Vector(x: w * x, y: w * y, z: w * z)
            power += w * w
            directionalPower += x * x + y * y + z * z
            vector.add(intensity)
            blockVector.add(intensity)
            blockPower += w * w
            blockFrames += 1

            if blockFrames == blockSize || frame == frames - 1 {
                let length = blockVector.length
                if blockFrames >= blockSize / 2,
                   blockPower / Double(blockFrames) >= minimumRMS * minimumRMS,
                   length / Double(blockFrames) > 1e-20 {
                    normalizedBlocks.add(blockVector.scaled(by: 1 / length))
                    validBlocks += 1
                }
                blockVector = Vector()
                blockPower = 0
                blockFrames = 0
            }
        }

        power /= Double(frames)
        vector = vector.scaled(by: 1 / Double(frames))
        let magnitude = vector.length
        let energy = power + directionalPower / Double(frames)
        let coherence = min(1, 2 * magnitude / max(energy, 1e-20))
        let horizontal = hypot(vector.x, vector.y) / max(magnitude, 1e-20)
        let stability = validBlocks == 0 ? 0 : normalizedBlocks.length / Double(validBlocks)
        let quality = min(1, max(0, coherence * horizontal * stability))
        let metrics = SpatialDirectionMetrics(rms: sqrt(power), coherence: coherence,
                                              horizontalFraction: horizontal, stability: stability, quality: quality,
                                              directionalRMS: sqrt(directionalPower / Double(frames)))
        guard power >= minimumRMS * minimumRMS else { return unknown("quiet", metrics: metrics) }
        guard horizontal >= 0.5 else { return unknown("vertical_or_diffuse", metrics: metrics) }
        guard quality >= minimumQuality else { return unknown("diffuse_or_moving", metrics: metrics) }
        let angle = wrapAngle(-atan2(vector.y, vector.x) * 180 / .pi - zero)
        return SpatialDirectionResult(angle: angle, quality: quality, reason: "direction_ready", metrics: metrics)
    }

    /// [-180, 180), with positive angles to the listener's right after calibration.
    static func wrapAngle(_ angle: Double) -> Double {
        guard angle.isFinite else { return .nan }
        var result = angle.truncatingRemainder(dividingBy: 360)
        if result >= 180 { result -= 360 }
        if result < -180 { result += 360 }
        return result
    }

    private static func unknown(_ reason: String, metrics: SpatialDirectionMetrics? = nil) -> SpatialDirectionResult {
        SpatialDirectionResult(angle: nil, quality: nil, reason: reason, metrics: metrics)
    }

    private struct Vector {
        var x = 0.0
        var y = 0.0
        var z = 0.0
        var length: Double { sqrt(x * x + y * y + z * z) }

        mutating func add(_ other: Vector) {
            x += other.x
            y += other.y
            z += other.z
        }

        func scaled(by scale: Double) -> Vector {
            Vector(x: x * scale, y: y * scale, z: z * scale)
        }
    }
}

/// A coherent rolling second defines the front; one weak chunk does not erase it.
/// Reset on capture gaps, route changes, rotation, and every new recording session.
struct FrontCalibration: Sendable {
    private(set) var zero: Double?
    private(set) var calibrating = false
    private(set) var failed = false
    private(set) var lastResult: SpatialDirectionResult?
    private(set) var lastRejectionReason: String?
    /// Attempt-only statistics remain available after success or failure.
    private(set) var attemptedDuration: TimeInterval = 0
    private(set) var candidateWindows = 0
    private(set) var acceptedWindows = 0
    private(set) var bestQuality = 0.0
    private(set) var bufferedDuration: TimeInterval = 0

    private var startedAt: TimeInterval = 0
    private var lastTime: TimeInterval = 0
    private var rate: Int?
    private var samples: [Float] = []
    private var writeIndex = 0
    private var storedSamples = 0
    private var quietDuration: TimeInterval = 0

    mutating func start(now: TimeInterval) {
        reset()
        guard now.isFinite, now >= 0 else {
            failed = true
            lastResult = SpatialDirectionResult(angle: nil, quality: nil, reason: "calibration_invalid_time")
            return
        }
        startedAt = now
        lastTime = now
        calibrating = true
    }

    mutating func reset() {
        zero = nil
        calibrating = false
        failed = false
        lastResult = nil
        lastRejectionReason = nil
        attemptedDuration = 0
        candidateWindows = 0
        acceptedWindows = 0
        bestQuality = 0
        startedAt = 0
        lastTime = 0
        rate = nil
        clearBuffer()
    }

    mutating func consume(samples incoming: [Float], sampleRate: Int, now: TimeInterval) {
        guard calibrating else { return }
        guard now.isFinite, now >= lastTime else {
            fail("calibration_invalid_time")
            return
        }
        guard now - startedAt <= 10 else {
            fail("calibration_timeout")
            return
        }
        guard SpatialDirection.supportedSampleRates.contains(sampleRate),
              !incoming.isEmpty, incoming.count.isMultiple(of: 4),
              incoming.count / 4 <= sampleRate / 4 else {
            fail("invalid_input")
            return
        }
        guard rate == nil || rate == sampleRate else {
            fail("calibration_rate_changed")
            return
        }
        let observation = SpatialDirection.estimate(samples: incoming, sampleRate: sampleRate)
        lastResult = observation
        guard observation.reason != "invalid_input" else {
            fail("invalid_input")
            return
        }
        lastTime = now
        let seconds = Double(incoming.count / 4) / Double(sampleRate)
        attemptedDuration += seconds
        rate = sampleRate
        quietDuration = observation.reason == "quiet" ? quietDuration + seconds : 0
        if quietDuration > 0.2 + 1e-8 {
            lastRejectionReason = "calibration_insufficient_activity"
            clearBuffer()
            return
        }
        append(incoming, sampleRate: sampleRate)
        guard storedSamples == sampleRate * 4 else { return }

        candidateWindows += 1
        let window = orderedSamples()
        let result = SpatialDirection.estimate(samples: window, sampleRate: sampleRate)
        lastResult = result
        bestQuality = max(bestQuality, result.metrics?.quality ?? 0)
        // A short loud burst surrounded by silence can have perfect coherence.
        // Require at least 800 ms of active audio in this actual one-second window.
        guard activeFrames(in: window, sampleRate: sampleRate) >= Int(Double(sampleRate) * 0.8) else {
            reject("calibration_insufficient_activity", metrics: result.metrics)
            return
        }
        guard let angle = result.angle else {
            lastRejectionReason = result.reason
            return
        }

        // The same .60 quality, horizontal and silence gates apply to both halves.
        // Opposing or moving sources must not become a plausible averaged front.
        let midpoint = window.count / 2
        let first = SpatialDirection.estimate(samples: Array(window[..<midpoint]), sampleRate: sampleRate)
        let second = SpatialDirection.estimate(samples: Array(window[midpoint...]), sampleRate: sampleRate)
        guard let firstAngle = first.angle, let secondAngle = second.angle else {
            reject("calibration_halves_uncertain", metrics: result.metrics)
            return
        }
        guard abs(SpatialDirection.wrapAngle(firstAngle - secondAngle)) <= 15 else {
            reject("calibration_direction_changed", metrics: result.metrics)
            return
        }
        // Half-window means alone can hide alternating directions. Only clear
        // short-window estimates can veto; uncertain chunks do not reset progress.
        let step = sampleRate / 10 * 4
        for start in stride(from: 0, to: window.count, by: step) {
            let end = min(start + step, window.count)
            let part = SpatialDirection.estimate(samples: Array(window[start..<end]), sampleRate: sampleRate)
            if let partAngle = part.angle, abs(SpatialDirection.wrapAngle(partAngle - angle)) > 15 {
                reject("calibration_direction_changed", metrics: result.metrics)
                return
            }
        }
        zero = angle
        acceptedWindows += 1
        calibrating = false
        clearBuffer()
    }

    /// A fixed-size circular buffer keeps storage bounded and appends linear in
    /// the incoming chunk, without shifting a growing array on every callback.
    private mutating func append(_ incoming: [Float], sampleRate: Int) {
        let capacity = sampleRate * 4
        if samples.count != capacity {
            samples = [Float](repeating: 0, count: capacity)
            writeIndex = 0
            storedSamples = 0
        }
        for value in incoming {
            samples[writeIndex] = value
            writeIndex += 1
            if writeIndex == capacity { writeIndex = 0 }
        }
        storedSamples = min(capacity, storedSamples + incoming.count)
        bufferedDuration = Double(storedSamples / 4) / Double(sampleRate)
    }

    private func orderedSamples() -> [Float] {
        guard writeIndex != 0 else { return samples }
        return Array(samples[writeIndex...]) + samples[..<writeIndex]
    }

    private func activeFrames(in window: [Float], sampleRate: Int) -> Int {
        let frames = window.count / 4
        let block = max(1, Int(Double(sampleRate) * 0.025))
        var active = 0
        for start in stride(from: 0, to: frames, by: block) {
            let end = min(start + block, frames)
            var power = 0.0
            for frame in start..<end {
                let w = Double(window[frame * 4])
                power += w * w
            }
            if power / Double(end - start) >= SpatialDirection.minimumRMS * SpatialDirection.minimumRMS {
                active += end - start
            }
        }
        return active
    }

    private mutating func clearBuffer() {
        samples.removeAll(keepingCapacity: false)
        writeIndex = 0
        storedSamples = 0
        bufferedDuration = 0
        quietDuration = 0
    }

    private mutating func reject(_ reason: String, metrics: SpatialDirectionMetrics?) {
        lastRejectionReason = reason
        lastResult = SpatialDirectionResult(angle: nil, quality: nil, reason: reason, metrics: metrics)
    }

    private mutating func fail(_ reason: String) {
        let metrics = lastResult?.metrics
        zero = nil
        calibrating = false
        failed = true
        startedAt = 0
        lastTime = 0
        rate = nil
        clearBuffer()
        if reason != "calibration_timeout" { lastRejectionReason = reason }
        lastResult = SpatialDirectionResult(angle: nil, quality: nil, reason: reason, metrics: metrics)
    }
}
