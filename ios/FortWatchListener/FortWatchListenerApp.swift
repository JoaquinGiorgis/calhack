import SwiftUI
import UIKit

@main
struct FortWatchListenerApp: App {
    var body: some Scene {
        WindowGroup { ListenerView() }
    }
}

// FortWatch's wristband palette: charcoal, bold white type and event colors.
private enum ListenerStyle {
    static let background = color(0x15171D)
    static let surface = color(0x20232B)
    static let secondary = color(0xB8C0CF)
    static let blue = color(0x244BCE)
    static let signalBlue = color(0x7097FF)
    static let green = color(0x82DEB4)
    static let red = color(0xA92535)
    static let radius: CGFloat = 20

    static func color(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 255) / 255,
              green: Double((hex >> 8) & 255) / 255,
              blue: Double(hex & 255) / 255)
    }
}

private struct SoundAppearance {
    let title: String
    let icon: String
    let color: Color
    let signal: Color
    let category: String

    init(event: String) {
        switch event {
        case "ALARM":
            self.init("ALARM", "light.beacon.max", 0xB92131, 0xFF6A79, "SAFETY")
        case "CAR_HORN":
            self.init("CAR HORN", "car.side", 0xA84408, 0xFFAB64, "SAFETY")
        case "GLASS":
            self.init("GLASS", "wineglass", 0xA32555, 0xFF86B0, "SAFETY")
        case "SHOUT":
            self.init("SHOUT", "megaphone", 0xA3256D, 0xFC88CD, "SAFETY")
        case "BABY":
            self.init("BABY", "figure.child", 0x126B67, 0x63D9C9, "ATTENTION")
        case "KNOCK":
            self.init("KNOCK", "door.left.hand.closed", 0x244BCE, 0x7097FF, "ATTENTION")
        case "DOORBELL":
            self.init("DOORBELL", "bell", 0x652BC2, 0xB78AFF, "ATTENTION")
        case "PHONE":
            self.init("PHONE", "phone", 0x485970, 0xAFC7E9, "ATTENTION")
        case "DOG":
            self.init("DOG", "dog", 0x81501C, 0xE8B678, "NEARBY")
        case "SPEECH":
            self.init("SPEECH", "text.bubble", 0x1F6539, 0x82DEB4, "NEARBY")
        default:
            self.init("SOUND", "waveform", 0x48515F, 0xC5CEDB, "DETECTED")
        }
    }

    private init(_ title: String, _ icon: String, _ color: UInt32, _ signal: UInt32, _ category: String) {
        self.title = title
        self.icon = icon
        self.color = ListenerStyle.color(color)
        self.signal = ListenerStyle.color(signal)
        self.category = category
    }
}

struct ListenerView: View {
    @State private var model = ListenerModel()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: model.capturing ? 12 : 24) {
                    header
                    bluetoothPanel
                    DirectionPanel(angle: model.directionAngle, event: model.directionEvent,
                                   capturing: model.capturing, calibrated: model.calibrated,
                                   calibrating: model.calibrating, calibrationFailed: model.calibrationFailed,
                                   starting: model.active && !model.capturing,
                                   canCalibrate: model.bluetooth.isConnected && (!model.active || model.capturing),
                                   calibrate: model.calibrate)
                    status
                    if let event = model.lastEvent {
                        SoundAlertCard(event: event, sent: model.lastEventSent)
                    }
                    if dynamicTypeSize.isAccessibilitySize { captureControl }
                    instructions
                }
                .padding(20)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .background(ListenerStyle.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !dynamicTypeSize.isAccessibilitySize { captureControl }
            }
            .toolbar(.hidden, for: .navigationBar)
            .preferredColorScheme(.dark)
            .onChange(of: scenePhase) {
                if scenePhase == .background { model.suspend() }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "waveform")
                .font(.title2.weight(.bold))
                .frame(width: 48, height: 48)
                .background(ListenerStyle.surface, in: .rect(cornerRadius: 14))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("FortWatch")
                    .font((model.capturing ? Font.title : Font.largeTitle).weight(.black))
                    .tracking(-1)
                    .accessibilityAddTraits(.isHeader)
                Text("FEEL WHAT YOU CAN’T HEAR")
                    .font(.caption.monospaced().weight(.medium))
                    .tracking(0.8)
                    .foregroundStyle(ListenerStyle.secondary)
            }
        }
        .foregroundStyle(.white)
    }

    private var bluetoothPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
            layout {
                HStack(spacing: 10) {
                    Image(systemName: "applewatch")
                        .font(.title2)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("WRISTBAND")
                            .font(.caption.monospaced().weight(.semibold))
                            .tracking(0.8)
                            .foregroundStyle(ListenerStyle.secondary)
                        Text(connectionTitle)
                            .font(.headline)
                            .foregroundStyle(model.bluetooth.isConnected ? ListenerStyle.green : .white)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                if model.bluetooth.isConnected {
                    Button("Disconnect") { model.disconnect() }
                        .buttonStyle(CompactButtonStyle())
                } else if model.bluetooth.connecting {
                    Button("Cancel") { model.disconnect() }
                        .buttonStyle(CompactButtonStyle())
                        .accessibilityLabel("Cancel wristband search")
                } else {
                    Button("Connect") { model.bluetooth.connect() }
                        .buttonStyle(CompactButtonStyle(fill: ListenerStyle.blue))
                        .accessibilityLabel("Connect wristband")
                }
            }
            if !model.bluetooth.isConnected {
                Text(model.bluetooth.status)
                    .font(.subheadline)
                    .foregroundStyle(ListenerStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !model.active {
                Button("Test vibration", systemImage: "waveform.path") { model.testWristband() }
                    .buttonStyle(ListenerButtonStyle(fill: ListenerStyle.background))
                    .accessibilityHint("Sends a test alert. Check the wristband for two short pulses.")
            }
        }
        .padding(16)
        .background(ListenerStyle.surface, in: .rect(cornerRadius: ListenerStyle.radius))
    }

    private var connectionTitle: String {
        if model.bluetooth.isConnected { return "Connected" }
        if model.bluetooth.connecting { return "Connecting…" }
        return "Not connected"
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.capturing {
                SoundLevelMeter(level: model.level, active: true)
            }
            Label(model.status, systemImage: model.capturing ? "mic.fill" : "mic.slash")
                .font(.subheadline)
                .foregroundStyle(ListenerStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if model.microphoneDenied || model.bluetooth.settingsDenied {
                Button("Open Settings", systemImage: "gearshape") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .buttonStyle(ListenerButtonStyle(fill: ListenerStyle.blue))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var instructions: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 16) {
                Label("Keep your iPhone upright on a fixed stand, with its microphones uncovered.", systemImage: "iphone")
                Label("To set the front, make one steady sound in front of the phone for a second. Calibrate again if you move it.", systemImage: "viewfinder")
                Label("The cue shows one dominant direction relative to the phone. Other sounds and echoes can make it uncertain.", systemImage: "scope")
                Label("Vibration tells you the alert priority. One motor cannot indicate left or right.", systemImage: "waveform.path")
                Label("Audio is processed on your iPhone and is not saved. Bluetooth carries alerts, sound level and the time.", systemImage: "lock")
            }
            .font(.footnote)
            .foregroundStyle(ListenerStyle.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 12)
        } label: {
            Text("How to use FortWatch")
                .font(.subheadline.weight(.semibold))
                .padding(.vertical, 12)
                .frame(minHeight: 44, alignment: .leading)
        }
        .tint(.white)
    }

    private var captureControl: some View {
        VStack(spacing: 10) {
            if model.active {
                Button(model.capturing ? "Stop listening" : "Cancel start", systemImage: "stop.fill", role: .destructive) {
                    model.stop()
                }
                .buttonStyle(ListenerButtonStyle(fill: ListenerStyle.red))
            } else {
                Button("Listen & calibrate", systemImage: "mic.fill") { model.calibrate() }
                    .buttonStyle(ListenerButtonStyle(fill: ListenerStyle.blue))
                    .disabled(!model.bluetooth.isConnected)
            }
            Text("Keep this app open while listening.")
                .font(.caption)
                .foregroundStyle(ListenerStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? 0 : 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: 620)
        .frame(maxWidth: .infinity)
        .background(ListenerStyle.background)
        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.12)).frame(height: 1) }
    }
}

private struct DirectionPanel: View {
    let angle: Double?
    let event: String?
    let capturing: Bool
    let calibrated: Bool
    let calibrating: Bool
    let calibrationFailed: Bool
    let starting: Bool
    let canCalibrate: Bool
    let calibrate: () -> Void

    private var appearance: SoundAppearance? { event.map(SoundAppearance.init(event:)) }
    private var usableAngle: Double? {
        guard capturing, calibrated, !calibrating, !calibrationFailed,
              let angle, angle.isFinite, (-180...180).contains(angle) else { return nil }
        return angle
    }

    var body: some View {
        VStack(spacing: capturing ? 12 : 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("SOUND DIRECTION")
                    .font(.caption.monospaced().weight(.semibold))
                    .tracking(1)
                Spacer(minLength: 12)
                Text(capturing ? "LISTENING" : "STANDBY")
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(capturing ? ListenerStyle.green : ListenerStyle.secondary)
            }
            .foregroundStyle(ListenerStyle.secondary)

            DirectionCue(angle: usableAngle, appearance: appearance ?? SoundAppearance(event: ""))
                .frame(maxWidth: capturing ? 200 : 220)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text(title)
                    .font((capturing ? Font.title2 : Font.largeTitle).weight(.black))
                    .tracking(-0.8)
                    .foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(ListenerStyle.secondary)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)

            if capturing {
                Button(calibrating ? "Calibrating front…" : "Calibrate front",
                       systemImage: "viewfinder", action: calibrate)
                    .buttonStyle(ListenerButtonStyle(fill: ListenerStyle.surface))
                    .disabled(!canCalibrate || calibrating)
                    .accessibilityHint("Keep one steady sound in front of the phone for one second.")
            } else {
                Text(starting ? "Waiting for the microphone to start…" : canCalibrate ? "Starts the microphone and sets the front direction." : "Connect your wristband to start calibration.")
                    .font(.footnote)
                    .foregroundStyle(ListenerStyle.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }

    private var title: String {
        if calibrating { return "Calibrating" }
        if starting { return "Starting microphone" }
        if !capturing { return "Ready to listen" }
        if calibrationFailed { return "Calibration failed" }
        if !calibrated { return "Calibration needed" }
        if usableAngle == nil { return "Direction unclear" }
        if let appearance { return appearance.title }
        if usableAngle != nil { return "Dominant sound" }
        return "Listening"
    }

    private var subtitle: String {
        if calibrating { return "Keep a steady sound in front of the phone." }
        if starting { return "Preparing sound recognition. Calibration will unlock when audio starts." }
        if !capturing { return "Connect your wristband, then start listening." }
        if calibrationFailed { return "Try again with one steady sound in front of the phone." }
        if !calibrated { return "Tap Calibrate front, then make a steady sound in front." }
        if let usableAngle { return "\(directionName(usableAngle)) · relative to the phone" }
        if let appearance { return "\(appearance.title) detected, but its direction is unclear." }
        return "No clear direction yet. Try one nearby sound."
    }

    private func directionName(_ angle: Double) -> String {
        let sectors = ["Ahead", "Front right", "Right", "Behind right", "Behind", "Behind left", "Left", "Front left"]
        let normalized = (angle + 360).truncatingRemainder(dividingBy: 360)
        return sectors[Int((normalized + 22.5) / 45) % sectors.count]
    }
}

/// A single event cue, not a compass or a map of separated sound sources.
private struct DirectionCue: View {
    let angle: Double?
    let appearance: SoundAppearance?

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            ZStack {
                // A neutral guide stays visible without implying a measured source.
                Circle()
                    .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                    .frame(width: side * 0.61, height: side * 0.61)
                    .position(center)
                ReticleShape()
                    .stroke(.white.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, lineCap: .square))
                    .frame(width: 58, height: 58)
                    .position(center)
                Image(systemName: "iphone")
                    .font(.system(size: 23, weight: .light))
                    .foregroundStyle(ListenerStyle.secondary)
                    .position(center)
                Text("PHONE")
                    .font(.caption2.monospaced().weight(.medium))
                    .tracking(1)
                    .foregroundStyle(ListenerStyle.secondary)
                    .position(x: center.x, y: center.y + 43)

                if let angle, let appearance {
                    TaperedSoundArc()
                        .fill(appearance.signal)
                        .rotationEffect(.degrees(angle))
                    let radians = angle * .pi / 180
                    Image(systemName: appearance.icon)
                        .font(.system(size: 23, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(appearance.color, in: .circle)
                        .overlay(Circle().strokeBorder(appearance.signal, lineWidth: 1.5))
                        .position(x: center.x + CGFloat(sin(radians)) * side * 0.405,
                                  y: center.y - CGFloat(cos(radians)) * side * 0.405)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// The broad middle and pointed ends communicate a direction without claiming
/// that the width represents measured angular uncertainty.
private struct TaperedSoundArc: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let radius = side * 0.305
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let steps = 64
        var outer: [CGPoint] = []
        var inner: [CGPoint] = []
        for index in 0...steps {
            let progress = Double(index) / Double(steps)
            let radians = (-90 - 48 + 96 * progress) * .pi / 180
            let halfWidth = CGFloat(sin(.pi * progress)) * side * 0.027
            let x = CGFloat(cos(radians)), y = CGFloat(sin(radians))
            outer.append(CGPoint(x: center.x + x * (radius + halfWidth), y: center.y + y * (radius + halfWidth)))
            inner.append(CGPoint(x: center.x + x * (radius - halfWidth), y: center.y + y * (radius - halfWidth)))
        }
        var path = Path()
        path.addLines(outer + inner.reversed())
        path.closeSubpath()
        return path
    }
}

private struct ReticleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let arm = rect.width * 0.22
        var path = Path()
        for (x, y, dx, dy) in [(rect.minX, rect.minY, 1.0, 1.0),
                              (rect.maxX, rect.minY, -1.0, 1.0),
                              (rect.minX, rect.maxY, 1.0, -1.0),
                              (rect.maxX, rect.maxY, -1.0, -1.0)] {
            path.move(to: CGPoint(x: x + arm * dx, y: y))
            path.addLine(to: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x, y: y + arm * dy))
        }
        return path
    }
}

private struct SoundLevelMeter: View {
    let level: Int
    let active: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text("INPUT")
                .font(.caption2.monospaced().weight(.medium))
                .foregroundStyle(ListenerStyle.secondary)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12))
                    Capsule().fill(ListenerStyle.green)
                        .frame(width: geometry.size.width * CGFloat(active ? min(100, max(0, level)) : 0) / 100)
                }
            }
            .frame(height: 4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Microphone level")
        .accessibilityValue(active ? "\(min(100, max(0, level))) out of 100" : "Not listening")
    }
}

private struct SoundAlertCard: View {
    let event: String
    let sent: Bool

    private var appearance: SoundAppearance { SoundAppearance(event: event) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("LATEST ALERT")
                    .font(.caption.monospaced().weight(.semibold))
                    .tracking(1)
                Spacer(minLength: 12)
                Text(appearance.category)
                    .font(.caption2.monospaced().weight(.medium))
            }
            Label(appearance.title, systemImage: appearance.icon)
                .font(.title.weight(.black))
            Label(sent ? "Sent over Bluetooth" : "Detected · not sent to wristband",
                  systemImage: sent ? "arrow.up.right" : "exclamationmark.circle")
                .font(.subheadline)
            if sent {
                Text("Check the wristband for the alert and vibration.")
                    .font(.footnote)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .foregroundStyle(.white)
        .background(appearance.color, in: .rect(cornerRadius: ListenerStyle.radius))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Latest alert. \(appearance.title). \(sent ? "Submitted over Bluetooth. Check the wristband for the alert and vibration." : "Detected, but not sent to the wristband.")")
    }
}

private struct ListenerButtonStyle: ButtonStyle {
    let fill: Color
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .background(fill, in: .rect(cornerRadius: 14))
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
    }
}

private struct CompactButtonStyle: ButtonStyle {
    var fill: Color = ListenerStyle.background

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(fill, in: .rect(cornerRadius: 12))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

#Preview { ListenerView() }
