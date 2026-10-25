import Foundation

struct SoundEventDetection: Sendable {
    let event: String
    let score: Double
    let angle: Double?
    let quality: Double?
    let expiresAt: TimeInterval
}

/// A category marker must use the direction measured in that category's own
/// audio window. A fresh but uncertain alert must never borrow a live angle.
struct SoundDirectionCue: Equatable {
    let angle: Double?
    let event: String?

    static func current(liveAngle: Double?, alert: SoundEventDetection?, at now: TimeInterval) -> Self {
        if let alert, now < alert.expiresAt {
            let valid = alert.angle.map { $0.isFinite && (-180...180).contains($0) } == true
                && alert.quality.map { $0.isFinite && (SpatialDirection.minimumQuality...1).contains($0) } == true
            return Self(angle: valid ? alert.angle : nil, event: alert.event)
        }
        let valid = liveAngle.map { $0.isFinite && (-180...180).contains($0) } == true
        return Self(angle: valid ? liveAngle : nil, event: nil)
    }
}

struct LocalAudioUpdate: Sendable {
    let angle: Double?
    let quality: Double?
    let calibrated: Bool
    let calibrating: Bool
    let level: Int
    let status: String
    let alert: SoundEventDetection?
    let expiresAt: TimeInterval
}

struct SoundEventPolicy: Sendable {
    let event: String
    let identifiers: Set<String>
    let threshold: Double
    let priority: Int
    let requiredHits: Int
    let historyLength: Int
    let cooldown: TimeInterval
}

struct SoundEventCandidate: Equatable, Sendable {
    let event: String
    let score: Double
}

/// Apple thresholds are provisional demo settings, not YAMNet's measured
/// thresholds. Tune only after testing real sounds on the actual phone.
struct SoundEventSelector {
    static let defaultPolicies: [SoundEventPolicy] = [
        policy("ALARM", ["alarm_clock", "siren", "civil_defense_siren", "smoke_detector",
                         "police_siren", "ambulance_siren", "fire_engine_siren"], priority: 3),
        policy("CAR_HORN", ["car_horn", "air_horn"], priority: 3),
        policy("GLASS", ["glass_breaking"], priority: 3),
        policy("SHOUT", ["shout", "yell", "children_shouting", "screaming"], threshold: 0.70, priority: 3),
        policy("BABY", ["baby_crying"], priority: 2),
        policy("KNOCK", ["knock"], priority: 2),
        policy("DOORBELL", ["door_bell"], priority: 2),
        policy("PHONE", ["telephone_bell_ringing", "ringtone"], priority: 2),
        policy("DOG", ["dog_bark", "dog_bow_wow"], priority: 1),
        SoundEventPolicy(event: "SPEECH", identifiers: ["speech"], threshold: 0.75, priority: 0,
                         requiredHits: 3, historyLength: 4, cooldown: 15)
    ]

    let policies: [SoundEventPolicy]
    private var history: [String: [Bool]] = [:]
    private var lastSent: [String: TimeInterval] = [:]
    private var lastWindow: TimeInterval?

    init(policies: [SoundEventPolicy] = Self.defaultPolicies) { self.policies = policies }

    private static func policy(_ event: String, _ identifiers: Set<String>, threshold: Double = 0.65,
                               priority: Int) -> SoundEventPolicy {
        SoundEventPolicy(event: event, identifiers: identifiers, threshold: threshold, priority: priority,
                         requiredHits: 1, historyLength: 1, cooldown: 2)
    }

    func missingClassifications(from known: Set<String>) -> [String] {
        Set(policies.flatMap(\.identifiers)).subtracting(known).sorted()
    }

    mutating func reset() {
        history.removeAll(keepingCapacity: true)
        lastSent.removeAll(keepingCapacity: true)
        lastWindow = nil
    }

    mutating func select(scores: [String: Double], at time: TimeInterval) -> SoundEventCandidate? {
        guard time.isFinite, time >= 0, lastWindow.map({ time > $0 }) ?? true else { return nil }
        lastWindow = time
        var candidates: [(policy: SoundEventPolicy, score: Double)] = []
        for policy in policies {
            let score = policy.identifiers.compactMap { identifier -> Double? in
                guard let score = scores[identifier], score.isFinite, (0...1).contains(score) else { return nil }
                return score
            }.max() ?? 0
            let hit = score >= policy.threshold
            var hits = history[policy.event, default: []]
            hits.append(hit)
            if hits.count > policy.historyLength { hits.removeFirst(hits.count - policy.historyLength) }
            history[policy.event] = hits
            let sustained = hits.filter { $0 }.count >= policy.requiredHits
            let cooled = lastSent[policy.event].map { time - $0 >= policy.cooldown } ?? true
            // Require a current hit so the event belongs to this exact audio window.
            if hit && sustained && cooled { candidates.append((policy, score)) }
        }
        let best = candidates.sorted {
            if $0.policy.priority != $1.policy.priority { return $0.policy.priority > $1.policy.priority }
            let left = $0.score / $0.policy.threshold, right = $1.score / $1.policy.threshold
            if left != right { return left > right }
            return $0.policy.event < $1.policy.event
        }.first
        guard let best else { return nil }
        lastSent[best.policy.event] = time
        return SoundEventCandidate(event: best.policy.event, score: best.score)
    }
}

struct AlignedSpatialSamples {
    let samples: [Float]
    let endUptime: TimeInterval
}

/// Bounded FOA history keyed by the same frame positions supplied to
/// SNAudioStreamAnalyzer. A classification never uses a newer live angle.
struct SpatialSampleRing {
    private struct Segment {
        let start: Int64
        let samples: [Float]
        let endUptime: TimeInterval
        var end: Int64 { start + Int64(samples.count / 4) }
    }
    private var segments: [Segment] = []
    private(set) var sampleRate = 0
    private(set) var storedFrames = 0

    mutating func reset() {
        segments.removeAll(keepingCapacity: true)
        sampleRate = 0
        storedFrames = 0
    }

    @discardableResult
    mutating func append(samples: [Float], sampleRate: Int, startFrame: Int64, endUptime: TimeInterval) -> Bool {
        guard !samples.isEmpty, samples.count.isMultiple(of: 4), SpatialDirection.supportedSampleRates.contains(sampleRate),
              samples.count / 4 <= sampleRate / 4, startFrame >= 0,
              startFrame <= Int64.max - Int64(samples.count / 4), endUptime.isFinite,
              samples.allSatisfy({ $0.isFinite && abs($0) <= 8 }) else { reset(); return false }
        if let last = segments.last, last.end != startFrame || self.sampleRate != sampleRate { reset() }
        self.sampleRate = sampleRate
        segments.append(Segment(start: startFrame, samples: samples, endUptime: endUptime))
        storedFrames += samples.count / 4
        while storedFrames > sampleRate * 4, let first = segments.first {
            storedFrames -= first.samples.count / 4
            segments.removeFirst()
        }
        return true
    }

    func window(startFrame: Int64, frameCount: Int64) -> AlignedSpatialSamples? {
        guard sampleRate > 0, startFrame >= 0, frameCount > 0, frameCount <= sampleRate * 2,
              startFrame <= Int64.max - frameCount else { return nil }
        let end = startFrame + frameCount
        guard let first = segments.first, let last = segments.last,
              startFrame >= first.start, end <= last.end else { return nil }
        var result: [Float] = []
        result.reserveCapacity(Int(frameCount) * 4)
        var next = startFrame
        var endUptime: TimeInterval?
        for segment in segments where segment.end > startFrame && segment.start < end {
            let from = max(segment.start, startFrame), to = min(segment.end, end)
            guard from == next else { return nil }
            result.append(contentsOf: segment.samples[Int(from - segment.start) * 4..<Int(to - segment.start) * 4])
            next = to
            if to == end { endUptime = segment.endUptime - Double(segment.end - end) / Double(sampleRate) }
        }
        guard next == end, let endUptime else { return nil }
        return AlignedSpatialSamples(samples: result, endUptime: endUptime)
    }
}
