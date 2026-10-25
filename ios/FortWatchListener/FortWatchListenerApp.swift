import SwiftUI
import UIKit

@main
struct FortWatchListenerApp: App {
    var body: some Scene {
        WindowGroup { ListenerView() }
    }
}

private enum ListenerStyle {
    static let ink = color(0x12141F)
    static let lime = color(0x8FD63D)
    static let secondary = Color.white.opacity(0.84)

    static func color(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 255) / 255,
              green: Double((hex >> 8) & 255) / 255,
              blue: Double(hex & 255) / 255)
    }

    static func display(_ size: CGFloat, relativeTo style: Font.TextStyle = .title2) -> Font {
        .custom("Gabarito-Regular", size: size, relativeTo: style).weight(.bold)
    }

    static func body(_ size: CGFloat = 16, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom("AtkinsonHyperlegibleNext-Regular", size: size, relativeTo: style)
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
        case "ALARM": self.init("ALARM", "light.beacon.max", 0xB92131, 0xFF94A0, "SAFETY")
        case "CAR_HORN": self.init("CAR HORN", "car.side", 0xA84408, 0xFFBA83, "SAFETY")
        case "GLASS": self.init("GLASS", "wineglass", 0xA32555, 0xFFAAC9, "SAFETY")
        case "SHOUT": self.init("SHOUT", "megaphone", 0xA3256D, 0xFCACE0, "SAFETY")
        case "BABY": self.init("BABY", "figure.child", 0x126B67, 0x8EE9DD, "ATTENTION")
        case "KNOCK": self.init("KNOCK", "door.left.hand.closed", 0x1E4DD4, 0xA5BFFF, "ATTENTION")
        case "DOORBELL": self.init("DOORBELL", "bell", 0x652BC2, 0xCFAEFF, "ATTENTION")
        case "PHONE": self.init("PHONE", "phone", 0x485970, 0xC6D9F3, "ATTENTION")
        case "DOG": self.init("DOG", "dog", 0x81501C, 0xF2CFA3, "NEARBY")
        case "SPEECH": self.init("SPEECH", "text.bubble", 0x1F6539, 0xA5EAC5, "NEARBY")
        default: self.init("SOUND", "waveform", 0x48515F, 0xE2E7EE, "LISTENING")
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
    @State private var showingGuide = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            ZStack {
                ListeningBackdrop()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        connection
                        SoundPanel(angle: model.directionAngle, event: model.directionEvent,
                                   capturing: model.capturing, calibrated: model.calibrated,
                                   calibrating: model.calibrating, calibrationFailed: model.calibrationFailed,
                                   starting: model.active && !model.capturing, level: model.level,
                                   status: model.status, calibrate: model.calibrate)
                        if model.microphoneDenied || model.bluetooth.settingsDenied {
                            Button("Open Settings", systemImage: "gearshape", action: openSettings)
                                .buttonStyle(SecondaryCapsuleStyle())
                        }
                        if let event = model.lastEvent, event != model.directionEvent {
                            LatestAlertRow(event: event, sent: model.lastEventSent)
                        }
                        if dynamicTypeSize.isAccessibilitySize { captureControl }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                    .frame(maxWidth: 620)
                    .frame(maxWidth: .infinity)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !dynamicTypeSize.isAccessibilitySize { captureControl }
            }
            .toolbar(.hidden, for: .navigationBar)
            .preferredColorScheme(.dark)
            .sheet(isPresented: $showingGuide) { ListeningGuide() }
            .onChange(of: scenePhase) {
                if scenePhase == .background { model.suspend() }
            }
        }
    }

    private var header: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        return layout {
            FortWatchWordmark()
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
            Menu {
                Button("Test vibration", systemImage: "waveform.path") { model.testWristband() }
                    .disabled(!model.bluetooth.isConnected || model.active)
                Button("How to use FortWatch", systemImage: "questionmark.circle") { showingGuide = true }
                Button("Open Settings", systemImage: "gearshape", action: openSettings)
                if model.bluetooth.isConnected || model.bluetooth.connecting {
                    Button("Disconnect wristband", systemImage: "xmark.circle", role: .destructive) { model.disconnect() }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(.circle)
            }
            .accessibilityLabel("Wristband options")
        }
        .padding(.leading, 18)
        .padding(.trailing, 4)
        .padding(.vertical, 5)
        .modifier(FrostedSurface(radius: 30))
    }

    private var connection: some View {
        VStack(alignment: .leading, spacing: 6) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 10))
            layout {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: model.bluetooth.isConnected ? "checkmark.circle.fill" : "applewatch")
                        .foregroundStyle(model.bluetooth.isConnected ? ListenerStyle.lime : .white)
                        .accessibilityHidden(true)
                    Text(model.bluetooth.isConnected ? "Wristband connected" : model.bluetooth.connecting ? "Finding your wristband…" : "Wristband not connected")
                        .font(ListenerStyle.body(15, relativeTo: .subheadline))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if model.bluetooth.connecting {
                    Button { model.disconnect() } label: {
                        Text("Cancel")
                            .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil)
                            .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: true)
                    }
                    .buttonStyle(SecondaryCapsuleStyle())
                    .accessibilityLabel("Cancel wristband search")
                } else if !model.bluetooth.isConnected {
                    Button { model.bluetooth.connect() } label: {
                        Text("Connect")
                            .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil)
                            .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: true)
                    }
                    .buttonStyle(SecondaryCapsuleStyle())
                    .accessibilityLabel("Connect wristband")
                }
            }
            .frame(minHeight: 44)
            if let reason = model.bluetooth.unavailableReason, !model.bluetooth.isConnected {
                Text(reason)
                    .font(ListenerStyle.body(14, relativeTo: .footnote))
                    .foregroundStyle(ListenerStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 4)
    }

    private var captureControl: some View {
        VStack(spacing: 10) {
            if model.active {
                Button(model.capturing ? "Stop listening" : "Cancel start", systemImage: "stop.fill", role: .destructive) { model.stop() }
                    .buttonStyle(PrimaryCapsuleStyle(prominent: false))
            } else {
                Button("Listen & calibrate", systemImage: "mic.fill") { model.calibrate() }
                    .buttonStyle(PrimaryCapsuleStyle())
                    .disabled(!model.bluetooth.isConnected)
            }
            Text(model.active ? "Keep this app open while listening." : "Audio stays on your iPhone. Nothing is recorded.")
                .font(ListenerStyle.body(13, relativeTo: .caption))
                .foregroundStyle(ListenerStyle.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? 0 : 20)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .frame(maxWidth: 620)
        .frame(maxWidth: .infinity)
        .background {
            if !dynamicTypeSize.isAccessibilitySize {
                LinearGradient(colors: [ListenerStyle.ink.opacity(0), ListenerStyle.ink.opacity(0.9)],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea(edges: .bottom)
            }
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }
}

private struct FortWatchWordmark: View {
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(ListenerStyle.lime)
                .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5))
                .frame(width: 11, height: 11)
                .accessibilityHidden(true)
            Text("fortwatch")
                .font(ListenerStyle.display(25, relativeTo: .title2))
                .tracking(-0.7)
                .foregroundStyle(.white)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("FortWatch")
        .accessibilityAddTraits(.isHeader)
    }
}

private struct ListeningBackdrop: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ListenerStyle.ink
                Image("ListeningBackdrop")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                ListenerStyle.ink.opacity(0.52)
                LinearGradient(colors: [ListenerStyle.ink.opacity(0.18), .clear, ListenerStyle.ink.opacity(0.7)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

private struct FrostedSurface: ViewModifier {
    var radius: CGFloat = 24
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        Group {
            if reduceTransparency {
                content.background(ListenerStyle.color(0x292E38), in: .rect(cornerRadius: radius))
            } else {
                content
                    .background(.white.opacity(0.14), in: .rect(cornerRadius: radius))
                    .background(.ultraThinMaterial, in: .rect(cornerRadius: radius))
            }
        }
        .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(.white.opacity(0.38), lineWidth: 1))
    }
}

private struct SoundPanel: View {
    let angle: Double?
    let event: String?
    let capturing: Bool
    let calibrated: Bool
    let calibrating: Bool
    let calibrationFailed: Bool
    let starting: Bool
    let level: Int
    let status: String
    let calibrate: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var appearance: SoundAppearance? {
        guard capturing, !calibrating, !calibrationFailed else { return nil }
        return event.map(SoundAppearance.init(event:))
    }

    private var usableAngle: Double? {
        guard capturing, calibrated, !calibrating, !calibrationFailed,
              let angle, angle.isFinite, (-180...180).contains(angle) else { return nil }
        return angle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline) {
                Text(eyebrow)
                    .font(.caption.monospaced().weight(.semibold))
                    .tracking(1)
                Spacer(minLength: 8)
                if let appearance {
                    VibrationPattern(category: appearance.category)
                } else {
                    Image(systemName: capturing ? "mic.fill" : "mic.slash")
                        .accessibilityLabel(capturing ? "Microphone active" : "Microphone stopped")
                }
            }
            .foregroundStyle(ListenerStyle.secondary)

            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
                : AnyLayout(HStackLayout(alignment: .center, spacing: usableAngle == nil ? 16 : 12))
            layout {
                if let usableAngle {
                    DirectionCue(angle: usableAngle, appearance: appearance ?? SoundAppearance(event: ""))
                        .frame(width: 138, height: 138)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: stateIcon)
                        .font(.system(size: 30, weight: .regular))
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .background(appearance?.color ?? .white.opacity(0.12), in: .circle)
                        .overlay(Circle().strokeBorder(.white.opacity(0.28), lineWidth: 1))
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 7) {
                    Text(title)
                        .font(ListenerStyle.display(appearance == nil ? 28 : 32, relativeTo: .title))
                        .tracking(-0.5)
                        .foregroundStyle(.white)
                        .accessibilityAddTraits(.isHeader)
                    Text(detail)
                        .font(ListenerStyle.body(16))
                        .foregroundStyle(ListenerStyle.secondary)
                    if usableAngle != nil {
                        Text("Relative to your phone")
                            .font(ListenerStyle.body(12, relativeTo: .caption))
                            .foregroundStyle(ListenerStyle.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
            }

            if capturing {
                SoundLevelMeter(level: level)
                Button(calibrating ? "Calibrating…" : calibrated ? "Recalibrate front" : calibrationFailed ? "Try calibration again" : "Calibrate front",
                       systemImage: "viewfinder", action: calibrate)
                    .buttonStyle(SecondaryCapsuleStyle())
                    .disabled(calibrating)
                    .accessibilityHint("Keep one steady sound in front of the phone for a second.")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(FrostedSurface())
    }

    private var eyebrow: String {
        if starting { return "GETTING READY" }
        if !capturing { return "ON YOUR IPHONE" }
        if calibrating { return "CALIBRATION" }
        if calibrationFailed || !calibrated { return "DIRECTION SETUP" }
        return appearance?.category ?? "LISTENING"
    }

    private var title: String {
        if starting { return "Starting…" }
        if !capturing { return "Ready to listen" }
        if calibrating { return "Set the front" }
        if calibrationFailed { return "Calibration failed" }
        if let appearance { return appearance.title }
        if !calibrated { return "Calibration needed" }
        if usableAngle != nil { return "Sound nearby" }
        return "Listening"
    }

    private var detail: String {
        if let usableAngle { return directionName(usableAngle) }
        if calibrating { return "Keep one steady sound in front of your phone." }
        if appearance != nil { return "Direction unclear" }
        return status
    }

    private var stateIcon: String {
        if let appearance { return appearance.icon }
        if calibrationFailed { return "exclamationmark" }
        if calibrating || (capturing && !calibrated) { return "viewfinder" }
        return "waveform"
    }

    private func directionName(_ angle: Double) -> String {
        let sectors = ["Ahead", "Front right", "To the right", "Behind right", "Behind", "Behind left", "To the left", "Front left"]
        let normalized = (angle + 360).truncatingRemainder(dividingBy: 360)
        return sectors[Int((normalized + 22.5) / 45) % sectors.count]
    }
}

/// Only a valid angle places an icon around the phone. The arc is not an
/// uncertainty measurement, and its category comes from the same audio window.
private struct DirectionCue: View {
    let angle: Double
    let appearance: SoundAppearance

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let radians = angle * .pi / 180
            ZStack {
                Circle().strokeBorder(.white.opacity(0.15), lineWidth: 1)
                    .frame(width: side * 0.56, height: side * 0.56)
                    .position(center)
                Image(systemName: "iphone")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(.white.opacity(0.8))
                    .position(center)
                TaperedSoundArc()
                    .fill(appearance.signal)
                    .rotationEffect(.degrees(angle))
                Image(systemName: appearance.icon)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(appearance.color, in: .circle)
                    .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1))
                    .position(x: center.x + CGFloat(sin(radians)) * side * 0.365,
                              y: center.y - CGFloat(cos(radians)) * side * 0.365)
            }
        }
    }
}

private struct TaperedSoundArc: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let radius = side * 0.28
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let steps = 48
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

private struct VibrationPattern: View {
    let category: String
    private var count: Int { category == "SAFETY" ? 3 : category == "ATTENTION" ? 2 : 1 }
    private var description: String { category == "SAFETY" ? "Three long pulses" : category == "ATTENTION" ? "Two short pulses" : "One short pulse" }

    var body: some View {
        HStack(spacing: 5) {
            Text("VIB").font(.caption2.monospaced().weight(.medium))
            HStack(spacing: 3) {
                ForEach(0..<count, id: \.self) { _ in
                    Capsule().fill(.white.opacity(0.9)).frame(width: category == "SAFETY" ? 10 : 6, height: 4)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Alert pattern: \(description)")
    }
}

private struct SoundLevelMeter: View {
    let level: Int

    var body: some View {
        HStack(spacing: 12) {
            Text("MIC LEVEL")
                .font(.caption2.monospaced().weight(.medium))
                .foregroundStyle(ListenerStyle.secondary)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.15))
                    Capsule().fill(ListenerStyle.lime)
                        .frame(width: geometry.size.width * CGFloat(min(100, max(0, level))) / 100)
                }
            }
            .frame(height: 4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Microphone level")
        .accessibilityValue("\(min(100, max(0, level))) out of 100")
    }
}

private struct LatestAlertRow: View {
    let event: String
    let sent: Bool
    private var appearance: SoundAppearance { SoundAppearance(event: event) }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: appearance.icon)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(appearance.color, in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("LATEST ALERT")
                    .font(.caption2.monospaced().weight(.medium))
                    .tracking(0.8)
                    .foregroundStyle(ListenerStyle.secondary)
                Text(appearance.title)
                    .font(ListenerStyle.display(22))
                Text(sent ? "Sent over Bluetooth" : "Detected · not sent")
                    .font(ListenerStyle.body(13, relativeTo: .caption))
                    .foregroundStyle(ListenerStyle.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(16)
        .modifier(FrostedSurface(radius: 22))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Latest alert, \(appearance.title). \(sent ? "Submitted over Bluetooth. Physical vibration is not confirmed by the app." : "Detected, but not sent to the wristband.")")
    }
}

private struct PrimaryCapsuleStyle: ButtonStyle {
    var prominent = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(ListenerStyle.body(18, relativeTo: .headline).weight(.bold))
            .foregroundStyle(prominent ? ListenerStyle.ink : .white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 20)
            .padding(.vertical, 3)
            .background(prominent ? ListenerStyle.lime : .white.opacity(0.14), in: .capsule)
            .overlay(Capsule().strokeBorder(.white.opacity(prominent ? 0 : 0.38), lineWidth: 1))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
    }
}

private struct SecondaryCapsuleStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(ListenerStyle.body(15, relativeTo: .subheadline).weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
            .frame(minHeight: 44)
            .background(.white.opacity(0.1), in: .capsule)
            .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.45)
    }
}

private struct ListeningGuide: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Label("Keep the phone upright and still, with its microphones uncovered.", systemImage: "iphone")
                    Label("Make one steady sound in front for a second. Calibrate again if you move the phone.", systemImage: "viewfinder")
                    Label("The ring shows one dominant direction relative to the phone. It cannot separate voices or multiple sources.", systemImage: "scope")
                    Label("Vibration follows alert priority. Direction appears on screen.", systemImage: "waveform.path")
                    Label("Audio stays on the iPhone and is not saved. Keep the app open during listening.", systemImage: "lock")
                    Text("Use Test vibration in the options menu to check the wristband gives two short pulses.")
                        .foregroundStyle(ListenerStyle.secondary)
                }
                .font(ListenerStyle.body())
                .fixedSize(horizontal: false, vertical: true)
                .padding(24)
            }
            .navigationTitle("Using FortWatch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }
}

#if DEBUG
/// Isolated design fixtures. No model, microphone, Bluetooth or production route.
struct ListenerDesignPreview: View {
    let scenario: String

    var body: some View {
        ZStack {
            ListeningBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    FortWatchWordmark()
                    Text("DESIGN PREVIEW · SIMULATED STATE")
                        .font(.caption.monospaced())
                        .foregroundStyle(.white)
                    SoundPanel(angle: scenario == "knock" ? 45 : nil,
                               event: scenario == "knock" ? "KNOCK" : nil,
                               capturing: true, calibrated: scenario == "knock", calibrating: false,
                               calibrationFailed: scenario == "calibration-failed", starting: false,
                               level: scenario == "knock" ? 48 : 25,
                               status: "Keep one steady sound in front of the phone, then try again.",
                               calibrate: {})
                }
                .padding(20)
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview("App — idle") { ListenerView() }
#Preview("KNOCK — design fixture") { ListenerDesignPreview(scenario: "knock") }
#Preview("Calibration — design fixture") { ListenerDesignPreview(scenario: "calibration-failed") }
#endif
