import Foundation

/// Maps the complete YAMNet score vector to the same ten user-facing alerts as
/// the Mac listener. The model still returns 521 scores; only these validated
/// groups are eligible to reach the UI, Bluetooth link and wristband.
struct YAMNetEventSelector {
    struct Policy {
        let event: String
        let classNames: Set<String>
        let threshold: Double
        let priority: Int
        let requiredHits: Int
        let historyLength: Int
        let cooldown: TimeInterval
        let vetoClassNames: Set<String>
    }

    private static let knockClasses: Set<String> = [
        "Knock", "Door", "Wood", "Chop", "Hammer", "Whack, thwack", "Tap"
    ]

    static let policies: [Policy] = [
        Policy(event: "ALARM", classNames: [
            "Alarm", "Alarm clock", "Smoke detector, smoke alarm", "Fire alarm", "Car alarm",
            "Buzzer", "Siren", "Civil defense siren", "Police car (siren)",
            "Ambulance (siren)", "Fire engine, fire truck (siren)"
        ], threshold: 0.50, priority: 3, requiredHits: 1, historyLength: 1,
               cooldown: 2, vetoClassNames: []),
        Policy(event: "CAR_HORN", classNames: [
            "Vehicle horn, car horn, honking", "Air horn, truck horn"
        ], threshold: 0.30, priority: 3, requiredHits: 1, historyLength: 1,
               cooldown: 2, vetoClassNames: []),
        Policy(event: "GLASS", classNames: ["Glass", "Shatter", "Breaking", "Smash, crash"],
               threshold: 0.50, priority: 3, requiredHits: 1, historyLength: 1,
               cooldown: 2, vetoClassNames: knockClasses),
        Policy(event: "SHOUT", classNames: ["Shout", "Yell", "Screaming", "Children shouting"],
               threshold: 0.40, priority: 3, requiredHits: 1, historyLength: 1,
               cooldown: 2, vetoClassNames: []),
        Policy(event: "BABY", classNames: ["Baby cry, infant cry"], threshold: 0.50,
               priority: 2, requiredHits: 1, historyLength: 1, cooldown: 2,
               vetoClassNames: []),
        Policy(event: "KNOCK", classNames: knockClasses, threshold: 0.30,
               priority: 2, requiredHits: 1, historyLength: 1, cooldown: 2,
               vetoClassNames: []),
        Policy(event: "DOORBELL", classNames: ["Doorbell", "Ding-dong"], threshold: 0.30,
               priority: 2, requiredHits: 1, historyLength: 1, cooldown: 2,
               vetoClassNames: []),
        Policy(event: "PHONE", classNames: ["Telephone", "Telephone bell ringing", "Ringtone"],
               threshold: 0.50, priority: 2, requiredHits: 1, historyLength: 1,
               cooldown: 2, vetoClassNames: []),
        Policy(event: "DOG", classNames: ["Bark"], threshold: 0.30,
               priority: 1, requiredHits: 1, historyLength: 1, cooldown: 2,
               vetoClassNames: []),
        Policy(event: "SPEECH", classNames: ["Speech"], threshold: 0.50,
               priority: 0, requiredHits: 3, historyLength: 4, cooldown: 15,
               vetoClassNames: [])
    ]

    private static let indexByName = Dictionary(
        uniqueKeysWithValues: SoundCatalog.all.map { ($0.name, $0.index) }
    )

    static var missingClassNames: [String] {
        let configured = policies.flatMap { $0.classNames.union($0.vetoClassNames) }
        return Set(configured).subtracting(indexByName.keys).sorted()
    }

    private var history: [String: [Bool]] = [:]
    private var lastNotified: [String: TimeInterval] = [:]
    private var lastWindow: TimeInterval?

    mutating func reset() {
        history.removeAll(keepingCapacity: true)
        lastNotified.removeAll(keepingCapacity: true)
        lastWindow = nil
    }

    mutating func select(scores: [Double], at time: TimeInterval) -> SoundEventCandidate? {
        guard time.isFinite, time >= 0, lastWindow.map({ time > $0 }) ?? true,
              scores.count == SoundCatalog.all.count,
              scores.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { return nil }
        if let lastWindow, time - lastWindow > 0.75 { history.removeAll(keepingCapacity: true) }
        lastWindow = time

        var candidates: [(policy: Policy, score: Double, sustained: Bool, cooled: Bool)] = []
        for policy in Self.policies {
            var score = Self.score(for: policy.classNames, in: scores)
            if !policy.vetoClassNames.isEmpty,
               Self.score(for: policy.vetoClassNames, in: scores) >= score {
                score = 0
            }
            let hit = score >= policy.threshold
            var hits = history[policy.event, default: []]
            hits.append(hit)
            if hits.count > policy.historyLength { hits.removeFirst(hits.count - policy.historyLength) }
            history[policy.event] = hits
            guard hit else { continue }
            candidates.append((policy, score,
                               hits.filter { $0 }.count >= policy.requiredHits,
                               lastNotified[policy.event].map { time - $0 >= policy.cooldown } ?? true))
        }

        let winner = candidates.sorted {
            if $0.policy.priority != $1.policy.priority { return $0.policy.priority > $1.policy.priority }
            let left = $0.score / $0.policy.threshold
            let right = $1.score / $1.policy.threshold
            if left != right { return left > right }
            return $0.policy.event < $1.policy.event
        }.first
        guard let winner else { return nil }
        let shouldNotify = winner.sustained && winner.cooled
        if shouldNotify { lastNotified[winner.policy.event] = time }
        return SoundEventCandidate(event: winner.policy.event, score: winner.score,
                                   shouldNotify: shouldNotify)
    }

    private static func score(for names: Set<String>, in scores: [Double]) -> Double {
        names.compactMap { indexByName[$0].map { scores[$0] } }.max() ?? 0
    }
}
