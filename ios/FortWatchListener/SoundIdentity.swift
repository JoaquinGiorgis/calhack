import SwiftUI

/// One visual vocabulary for detected sounds, recent sounds and the library.
/// Categories describe the current recognizer, not every possible real-world sound.
struct SoundIdentity: Identifiable {
    let event: String
    let title: String
    let icon: String
    let colorHex: UInt32
    let signalHex: UInt32
    let category: String
    let summary: String
    let examples: String
    let index: Int

    var id: String { event }
    var color: Color { Self.color(colorHex) }
    var signal: Color { Self.color(signalHex) }

    static let all: [Self] = [
        Self("ALARM", "ALARM", "light.beacon.max", 0xB92131, 0xFF94A0, "SAFETY",
             "Alarm or siren", "Smoke alarms, alarm clocks and emergency sirens.", 1),
        Self("CAR_HORN", "CAR HORN", "car.side", 0xA84408, 0xFFBA83, "SAFETY",
             "Vehicle horn", "Car horns and air horns.", 2),
        Self("GLASS", "GLASS", "wineglass", 0xA32555, 0xFFAAC9, "SAFETY",
             "Breaking glass", "Glass breaking or shattering.", 3),
        Self("SHOUT", "SHOUT", "megaphone", 0xA3256D, 0xFCACE0, "SAFETY",
             "Raised voice", "Shouting, yelling and screaming.", 4),
        Self("BABY", "BABY", "figure.child", 0x126B67, 0x8EE9DD, "ATTENTION",
             "Baby crying", "An infant crying.", 5),
        Self("KNOCK", "KNOCK", "door.left.hand.closed", 0x1E4DD4, 0xA5BFFF, "ATTENTION",
             "Knocking sound", "Repeated knocks, such as knocking on a door.", 6),
        Self("DOORBELL", "DOORBELL", "bell", 0x652BC2, 0xCFAEFF, "ATTENTION",
             "Doorbell ringing", "A doorbell chime or ring.", 7),
        Self("PHONE", "PHONE", "phone", 0x485970, 0xC6D9F3, "ATTENTION",
             "Phone ringing", "Telephone bells and ringtones.", 8),
        Self("DOG", "DOG", "dog", 0x81501C, 0xF2CFA3, "NEARBY",
             "Dog barking", "A dog barking or giving a bow-wow.", 9),
        Self("SPEECH", "SPEECH", "text.bubble", 0x1F6539, 0xA5EAC5, "NEARBY",
             "Someone speaking", "Sustained speech. Words and speakers are not identified.", 10)
    ]

    init(event: String) {
        self = Self.all.first { $0.event == event }
            ?? Self("UNKNOWN", "SOUND", "waveform", 0x48515F, 0xE2E7EE, "LISTENING",
                    "Sound nearby", "No recognized sound category.", 0)
    }

    private init(_ event: String, _ title: String, _ icon: String,
                 _ colorHex: UInt32, _ signalHex: UInt32, _ category: String,
                 _ summary: String, _ examples: String, _ index: Int) {
        self.event = event
        self.title = title
        self.icon = icon
        self.colorHex = colorHex
        self.signalHex = signalHex
        self.category = category
        self.summary = summary
        self.examples = examples
        self.index = index
    }

    private static func color(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 255) / 255,
              green: Double((hex >> 8) & 255) / 255,
              blue: Double(hex & 255) / 255)
    }
}
