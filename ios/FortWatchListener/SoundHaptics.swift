import Foundation

/// Learned rhythms identify sound types, not their physical direction.
/// Alternating on/off milliseconds, starting and ending with an on segment.
/// Kept in sync with the wristband by test_haptic_contract.py.
struct SoundHapticPattern: Equatable, Sendable {
    let event: String
    let description: String
    let segments: [Int]

    static let all: [Self] = [
        Self(event: "ALARM", description: "Three long pulses", segments: [400, 150, 400, 150, 400]),
        Self(event: "CAR_HORN", description: "Two long pulses", segments: [650, 200, 650]),
        Self(event: "GLASS", description: "Three short pulses", segments: [150, 120, 150, 120, 150]),
        Self(event: "SHOUT", description: "Long · short · long", segments: [450, 180, 150, 180, 450]),
        Self(event: "BABY", description: "Short · long · short", segments: [150, 180, 500, 180, 150]),
        Self(event: "KNOCK", description: "Two short pulses", segments: [150, 120, 150]),
        Self(event: "DOORBELL", description: "Long · short", segments: [500, 180, 150]),
        Self(event: "PHONE", description: "Two short · pause · two short", segments: [150, 120, 150, 400, 150, 120, 150]),
        Self(event: "DOG", description: "Two short · one long", segments: [150, 120, 150, 180, 500]),
        Self(event: "SPEECH", description: "One short pulse", segments: [150]),
        Self(event: "HUMAN", description: "One short pulse", segments: [150]),
        Self(event: "ANIMAL", description: "Two short · one long", segments: [150, 120, 150, 180, 500]),
        Self(event: "VEHICLE", description: "Two long pulses", segments: [650, 200, 650]),
        Self(event: "HOUSEHOLD", description: "Two short pulses", segments: [150, 120, 150]),
        Self(event: "MACHINE", description: "Two medium pulses", segments: [350, 150, 350]),
        Self(event: "MUSIC", description: "Four short pulses", segments: [150, 120, 150, 120, 150, 120, 150]),
        Self(event: "NATURE", description: "One long pulse", segments: [650]),
        Self(event: "OTHER", description: "One medium pulse", segments: [300]),
        Self(event: "QUIET", description: "No vibration", segments: [])
    ]

    static func supports(_ event: String) -> Bool {
        SoundCatalog.forEvent(event) != nil || all.contains { $0.event == event }
    }

    static func forEvent(_ event: String) -> Self {
        let key = SoundCatalog.forEvent(event)?.hapticEvent ?? event
        return all.first { $0.event == key }
            ?? Self(event: "UNKNOWN", description: "One short pulse", segments: [150])
    }
}
