import Foundation

/// An estimate of the dominant sound, not separation of a classified event.
/// Quality measures coherence and stability; it is not an accuracy probability.
struct SpatialDirectionResult: Equatable, Sendable {
    let angle: Double?
    let quality: Double?
    let reason: String
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
        guard power >= minimumRMS * minimumRMS else { return unknown("quiet") }
        vector = vector.scaled(by: 1 / Double(frames))
        let magnitude = vector.length
        let energy = power + directionalPower / Double(frames)
        let coherence = min(1, 2 * magnitude / max(energy, 1e-20))
        let horizontal = hypot(vector.x, vector.y) / max(magnitude, 1e-20)
        guard horizontal >= 0.5 else { return unknown("vertical_or_diffuse") }
        let stability = validBlocks == 0 ? 0 : normalizedBlocks.length / Double(validBlocks)
        let quality = min(1, max(0, coherence * horizontal * stability))
        guard quality >= minimumQuality else { return unknown("diffuse_or_moving") }
        let angle = wrapAngle(-atan2(vector.y, vector.x) * 180 / .pi - zero)
        return SpatialDirectionResult(angle: angle, quality: quality, reason: "direction_ready")
    }

    /// [-180, 180), with positive angles to the listener's right after calibration.
    static func wrapAngle(_ angle: Double) -> Double {
        guard angle.isFinite else { return .nan }
        var result = angle.truncatingRemainder(dividingBy: 360)
        if result >= 180 { result -= 360 }
        if result < -180 { result += 360 }
        return result
    }

    private static func unknown(_ reason: String) -> SpatialDirectionResult {
        SpatialDirectionResult(angle: nil, quality: nil, reason: reason)
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

/// A one-second continuous, coherent front reference. Use a monotonic clock.
/// Reset on capture gaps, route changes, rotation, and every new recording session.
struct FrontCalibration: Sendable {
    private(set) var zero: Double?
    private(set) var calibrating = false
    private(set) var failed = false
    private var startedAt: TimeInterval = 0
    private var lastTime: TimeInterval = 0
    private var duration = 0.0
    private var x = 0.0
    private var y = 0.0

    mutating func start(now: TimeInterval) {
        reset()
        guard now.isFinite, now >= 0 else {
            failed = true
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
        startedAt = 0
        lastTime = 0
        clearAccumulation()
    }

    mutating func consume(samples: [Float], sampleRate: Int, now: TimeInterval) {
        guard calibrating else { return }
        guard now.isFinite, now >= lastTime, now - startedAt <= 10,
              SpatialDirection.supportedSampleRates.contains(sampleRate),
              !samples.isEmpty, samples.count.isMultiple(of: 4),
              samples.count / 4 <= sampleRate / 4 else {
            fail()
            return
        }
        lastTime = now
        let result = SpatialDirection.estimate(samples: samples, sampleRate: sampleRate)
        if result.reason == "invalid_input" {
            fail()
            return
        }
        guard let angle = result.angle else {
            clearAccumulation()
            return
        }
        if duration > 0 {
            let previousAngle = atan2(y, x) * 180 / .pi
            if abs(SpatialDirection.wrapAngle(angle - previousAngle)) > 15 {
                clearAccumulation()
            }
        }
        let seconds = Double(samples.count / 4) / Double(sampleRate)
        let radians = angle * .pi / 180
        x += cos(radians) * seconds
        y += sin(radians) * seconds
        duration += seconds
        if duration + 1e-8 >= 1 {
            zero = SpatialDirection.wrapAngle(atan2(y, x) * 180 / .pi)
            calibrating = false
            clearAccumulation()
        }
    }

    private mutating func clearAccumulation() {
        duration = 0
        x = 0
        y = 0
    }

    private mutating func fail() {
        reset()
        failed = true
    }
}
