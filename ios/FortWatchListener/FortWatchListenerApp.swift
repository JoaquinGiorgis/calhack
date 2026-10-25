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

private typealias SoundAppearance = SoundIdentity

struct ListenerView: View {
    @State private var model = ListenerModel()
    @State private var showingGuide = false
    @State private var showingSoundGuide = false
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
                                   status: model.status, calibrate: model.calibrate, recentSound: model.recentSound)
                        if model.microphoneDenied || model.bluetooth.settingsDenied {
                            Button("Open Settings", systemImage: "gearshape", action: openSettings)
                                .buttonStyle(SecondaryCapsuleStyle())
                        }
                        soundLibraryEntry
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
            .sheet(isPresented: $showingSoundGuide) {
                SoundLibrary(canTest: model.bluetooth.isConnected && !model.active,
                                    disabledReason: model.bluetooth.isConnected
                                        ? "Stop listening to test vibration patterns."
                                        : "Connect your wristband to test vibration patterns.",
                                    testSound: { event in model.testSound(event: event) })
            }
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
                Button("Sound library", systemImage: "square.grid.2x2") { showingSoundGuide = true }
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
                Button("Start listening", systemImage: "mic.fill") { model.start() }
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

    private var soundLibraryEntry: some View {
        Button { showingSoundGuide = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "square.grid.2x2")
                    .font(.title2)
                    .foregroundStyle(ListenerStyle.lime)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Sound library")
                        .font(ListenerStyle.display(21, relativeTo: .headline))
                    Text("\(SoundIdentity.all.count) sounds · meanings & rhythms")
                        .font(ListenerStyle.body(14, relativeTo: .footnote))
                        .foregroundStyle(ListenerStyle.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.white)
            .frame(minHeight: 44)
            .padding(16)
            .modifier(FrostedSurface(radius: 22))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sound library. Learn and test \(SoundIdentity.all.count) sound patterns.")
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
    var tint: Color? = nil
    var border: Color? = nil
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        Group {
            if reduceTransparency {
                content.background(tint ?? ListenerStyle.color(0x292E38), in: .rect(cornerRadius: radius))
            } else if let tint {
                // Bound the brightness independently of the photograph beneath.
                content
                    .background(tint.opacity(0.58), in: .rect(cornerRadius: radius))
                    .background(ListenerStyle.ink.opacity(0.86), in: .rect(cornerRadius: radius))
                    .background(.ultraThinMaterial, in: .rect(cornerRadius: radius))
            } else {
                content
                    .background(ListenerStyle.ink.opacity(0.45), in: .rect(cornerRadius: radius))
                    .background(.ultraThinMaterial, in: .rect(cornerRadius: radius))
            }
        }
        .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(border?.opacity(0.75) ?? .white.opacity(0.38), lineWidth: 1))
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
    var recentSound: RecentSound? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var presented: PresentedSound {
        .current(live: SoundDirectionCue(angle: capturing && !calibrating ? angle : nil,
                                         event: capturing && !calibrating ? event : nil),
                 recent: recentSound)
    }
    private var displayedEvent: String? { presented.event }
    private var presentingRecent: Bool { presented.isRecent }

    private var appearance: SoundAppearance? {
        displayedEvent.map(SoundAppearance.init(event:))
    }

    private var usableAngle: Double? {
        guard !presentingRecent, capturing, calibrated, !calibrating, !calibrationFailed,
              let angle = presented.angle, angle.isFinite, (-180...180).contains(angle) else { return nil }
        return angle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            let headerLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
            headerLayout {
                Text(eyebrow)
                    .font(.caption.monospaced().weight(.semibold))
                    .tracking(1)
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
                if let displayedEvent {
                    VibrationPattern(event: displayedEvent)
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
                        .frame(width: 120, height: 120)
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
                        .font(ListenerStyle.display(appearance == nil ? 28 : 34, relativeTo: .title))
                        .tracking(-0.5)
                        .foregroundStyle(.white)
                        .accessibilityAddTraits(.isHeader)
                    if let appearance {
                        Text(appearance.summary)
                            .font(ListenerStyle.body(16))
                            .foregroundStyle(ListenerStyle.secondary)
                    } else if !capturing {
                        Text(detail)
                            .font(ListenerStyle.body(16))
                            .foregroundStyle(ListenerStyle.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
            }

            if presentingRecent, let recentSound = presented.recent {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(recentSound.observedAt, style: .relative)
                            .environment(\.locale, Locale(identifier: "en"))
                        Text("ago")
                    }
                    Text(recentSound.sent ? "Sent over Bluetooth" : "Detected · not sent to wristband")
                }
                .font(ListenerStyle.body(13, relativeTo: .caption))
                .foregroundStyle(ListenerStyle.secondary)
                .accessibilityElement(children: .combine)
            }
            if let displayedEvent {
                Label(SoundHapticPattern.forEvent(displayedEvent).description, systemImage: "waveform.path")
                    .font(ListenerStyle.body(15, relativeTo: .subheadline))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if presentingRecent, capturing, calibrating || calibrationFailed || !calibrated {
                Label(calibrating ? "Calibrating front — keep one sound steady." : calibrationFailed
                      ? "Calibration failed. Try again." : "Calibrate the front to locate the next sound.",
                      systemImage: "viewfinder")
                    .font(ListenerStyle.body(14, relativeTo: .footnote))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if capturing || presentingRecent {
                DirectionReadout(angle: usableAngle, reason: detail)
            }
            if presentingRecent, !capturing {
                Label(status, systemImage: "mic.slash")
                    .font(ListenerStyle.body(14, relativeTo: .footnote))
                    .foregroundStyle(ListenerStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
        .modifier(FrostedSurface(tint: appearance?.color, border: appearance?.signal))
    }

    private var eyebrow: String {
        if presentingRecent { return "RECENT SOUND" }
        if let appearance { return appearance.category }
        if starting { return "GETTING READY" }
        if !capturing { return "ON YOUR IPHONE" }
        if calibrating { return "CALIBRATION" }
        return "LISTENING"
    }

    private var title: String {
        if let appearance { return appearance.title }
        if starting { return "Starting…" }
        if !capturing { return "Ready to listen" }
        if calibrating { return "Calibrating front" }
        if usableAngle != nil { return "Sound nearby" }
        return "Listening for sounds"
    }

    private var detail: String {
        if presentingRecent { return "Past detection · no live location" }
        if calibrating { return "Keep one steady sound in front of your phone." }
        if capturing, calibrationFailed { return "Calibration failed. Try again to locate sounds." }
        if capturing, !calibrated { return "Calibrate front to locate sounds." }
        if appearance != nil { return "No clear source location in this sound." }
        return status
    }

    private var stateIcon: String {
        if let appearance { return appearance.icon }
        if calibrating { return "viewfinder" }
        return "waveform"
    }

}

private struct DirectionReadout: View {
    let angle: Double?
    let reason: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if let angle {
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                    : AnyLayout(HStackLayout(alignment: .center, spacing: 16))
                layout {
                    FilledDirectionArrow()
                        .fill(ListenerStyle.ink)
                        .frame(width: 42, height: 48)
                        .rotationEffect(.degrees(angle))
                        .frame(width: 64, height: 64)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(directionName(angle))
                            .font(ListenerStyle.display(30, relativeTo: .title))
                            .accessibilityAddTraits(.isHeader)
                        Text("Relative to your phone")
                            .font(ListenerStyle.body(13, relativeTo: .caption))
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .foregroundStyle(ListenerStyle.ink)
                .padding(16)
                .background(ListenerStyle.lime, in: .rect(cornerRadius: 18))
                .accessibilityElement(children: .combine)
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    Text("DIRECTION UNAVAILABLE")
                        .font(ListenerStyle.display(19, relativeTo: .headline))
                        .accessibilityAddTraits(.isHeader)
                    Text(reason)
                        .font(ListenerStyle.body(15, relativeTo: .subheadline))
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(.white)
                .padding(16)
                .background(ListenerStyle.ink.opacity(0.55), in: .rect(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.38), lineWidth: 1))
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func directionName(_ angle: Double) -> String {
        let sectors = ["AHEAD", "FRONT RIGHT", "RIGHT", "BEHIND RIGHT", "BEHIND", "BEHIND LEFT", "LEFT", "FRONT LEFT"]
        let normalized = (angle + 360).truncatingRemainder(dividingBy: 360)
        return sectors[Int((normalized + 22.5) / 45) % sectors.count]
    }
}

private struct FilledDirectionArrow: Shape {
    func path(in rect: CGRect) -> Path {
        let points: [CGPoint] = [CGPoint(x: 0.5, y: 0), CGPoint(x: 1, y: 0.44),
                                 CGPoint(x: 0.68, y: 0.44), CGPoint(x: 0.68, y: 1),
                                 CGPoint(x: 0.32, y: 1), CGPoint(x: 0.32, y: 0.44), CGPoint(x: 0, y: 0.44)]
        var path = Path()
        path.addLines(points.map { CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height) })
        path.closeSubpath()
        return path
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
    let event: String
    private var pattern: SoundHapticPattern { .forEvent(event) }

    var body: some View {
        HStack(spacing: 5) {
            Text("VIB").font(.caption2.monospaced().weight(.medium))
            PulseRhythm(segments: pattern.segments)
                .fill(.white.opacity(0.95))
                .frame(width: 66, height: 5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Vibration pattern: \(pattern.description)")
    }
}

/// One shared time scale keeps a short pulse visually short across every event.
private struct PulseRhythm: Shape {
    let segments: [Int]
    private static let longestPattern = SoundHapticPattern.all.map { $0.segments.reduce(0, +) }.max() ?? 1

    func path(in rect: CGRect) -> Path {
        let total = segments.reduce(0, +)
        guard total > 0 else { return Path() }
        let timeline = max(total, Self.longestPattern)
        var elapsed = 0
        var path = Path()
        for (index, duration) in segments.enumerated() {
            if index.isMultiple(of: 2), duration > 0 {
                let x = rect.minX + rect.width * CGFloat(elapsed) / CGFloat(timeline)
                let width = rect.width * CGFloat(duration) / CGFloat(timeline)
                path.addRoundedRect(in: CGRect(x: x, y: rect.minY, width: width, height: rect.height),
                                    cornerSize: CGSize(width: rect.height / 2, height: rect.height / 2))
            }
            elapsed += duration
        }
        return path
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

private struct SoundLibrary: View {
    let canTest: Bool
    let disabledReason: String
    let testSound: (String) -> Bool
    @State private var lastTestedEvent: String?
    @State private var testFeedback: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                ListeningBackdrop()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("\(SoundIdentity.all.count) sound types")
                            .font(ListenerStyle.display(28, relativeTo: .title))
                            .accessibilityAddTraits(.isHeader)
                        Text("Learn each sound by its color, symbol and rhythm. Direction appears on screen.")
                            .font(ListenerStyle.body())
                        Text(canTest ? "Choose Test to play a pattern on your wristband." : disabledReason)
                            .font(ListenerStyle.body(14, relativeTo: .footnote))
                            .foregroundStyle(ListenerStyle.secondary)
                        if let testFeedback {
                            Label(testFeedback, systemImage: "waveform.path")
                                .font(ListenerStyle.body(14, relativeTo: .footnote))
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(14)
                                .modifier(FrostedSurface(radius: 18))
                        }
                        ForEach(SoundIdentity.all, id: \.event) { identity in
                            SoundLibraryRow(identity: identity, canTest: canTest,
                                            selected: lastTestedEvent == identity.event) {
                                lastTestedEvent = identity.event
                                let accepted = testSound(identity.event)
                                let pattern = SoundHapticPattern.forEvent(identity.event)
                                testFeedback = accepted
                                    ? "\(identity.title) test sent. Feel \(pattern.description.lowercased())."
                                    : "\(identity.title) test not sent. Check the wristband connection."
                                if let testFeedback {
                                    UIAccessibility.post(notification: .announcement, argument: testFeedback)
                                }
                            }
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(20)
                    .frame(maxWidth: 620)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Sound library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }
}

private struct SoundLibraryRow: View {
    let identity: SoundIdentity
    let canTest: Bool
    let selected: Bool
    let test: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var pattern: SoundHapticPattern { .forEvent(identity.event) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            let headerLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
            headerLayout {
                Text(String(format: "%02d", identity.index) + "  /  " + identity.category)
                    .font(.caption2.monospaced().weight(.medium))
                    .tracking(0.8)
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
                if selected {
                    Text("LAST TEST")
                        .font(.caption2.monospaced().weight(.semibold))
                        .foregroundStyle(ListenerStyle.lime)
                }
            }
            .foregroundStyle(ListenerStyle.secondary)
            let identityLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 14))
            identityLayout {
                Image(systemName: identity.icon)
                    .font(.system(size: 27, weight: .medium))
                    .frame(width: 56, height: 56)
                    .background(identity.color, in: .circle)
                    .overlay(Circle().strokeBorder(identity.signal.opacity(0.8), lineWidth: 1))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(identity.title)
                        .font(ListenerStyle.display(25, relativeTo: .title2))
                        .accessibilityAddTraits(.isHeader)
                    Text(identity.summary)
                        .font(ListenerStyle.body(15, relativeTo: .subheadline))
                        .foregroundStyle(ListenerStyle.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
            Text(identity.examples)
                .font(ListenerStyle.body(14, relativeTo: .footnote))
                .foregroundStyle(ListenerStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Rectangle().fill(identity.signal.opacity(0.24)).frame(height: 1)
            let rhythmLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 16))
            rhythmLayout {
                VStack(alignment: .leading, spacing: 8) {
                    PulseRhythm(segments: pattern.segments)
                        .fill(identity.signal)
                        .frame(width: 102, height: 6)
                        .accessibilityHidden(true)
                    Text(pattern.description)
                        .font(ListenerStyle.body(14, relativeTo: .footnote))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: test) {
                    Text("Test")
                        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil)
                        .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: true)
                }
                .buttonStyle(SecondaryCapsuleStyle())
                .disabled(!canTest)
                .accessibilityLabel("Test \(identity.title) vibration")
                .accessibilityHint("Plays this sound's vibration pattern on the wristband.")
            }
        }
        .foregroundStyle(.white)
        .padding(18)
        .modifier(FrostedSurface(radius: 22, tint: identity.color, border: identity.signal))
        .overlay {
            if selected {
                RoundedRectangle(cornerRadius: 22).strokeBorder(ListenerStyle.lime, lineWidth: 2)
            }
        }
    }
}

private struct ListeningGuide: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Label("Tap Start listening to recognize sounds right away. Calibration is optional for sound recognition.", systemImage: "mic")
                    Label("For direction, keep the phone upright and still with its microphones uncovered.", systemImage: "iphone")
                    Label("Tap Calibrate front and make one steady sound in front for a second. Calibrate again if you move the phone.", systemImage: "viewfinder")
                    Label("The ring shows one dominant direction relative to the phone. It cannot separate voices or multiple sources.", systemImage: "scope")
                    Label("Each sound has its own vibration pattern. Direction appears on screen.", systemImage: "waveform.path")
                    Label("Audio stays on the iPhone and is not saved. Keep the app open during listening.", systemImage: "lock")
                    Text("Open Sound library to learn and test every pattern. Stop listening before testing.")
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
    @State private var previewMoment = Date()

    private var fixtureEvent: String? {
        if scenario == "long-label" { return "CAR_HORN" }
        if scenario == "unknown" { return "GLASS" }
        if scenario == "unknown-sound" { return "UNRECOGNIZED" }
        let candidate = scenario.uppercased().replacingOccurrences(of: "-", with: "_")
        return SoundIdentity.all.contains { $0.event == candidate } ? candidate : nil
    }
    private var fixtureAngle: Double? {
        if scenario == "long-label" { return -135 }
        if scenario == "recent-live-angle" { return 90 }
        if scenario == "unknown" || scenario == "unknown-sound" { return nil }
        return fixtureEvent == nil ? nil : 45
    }
    private var fixtureRecent: RecentSound? {
        switch scenario {
        case "calibration-failed":
            return RecentSound(event: "SPEECH", observedAt: previewMoment.addingTimeInterval(-18), sent: true)
        case "calibrating-recent":
            return RecentSound(event: "KNOCK", observedAt: previewMoment.addingTimeInterval(-10), sent: true)
        case "recent-live-angle":
            return RecentSound(event: "DOG", observedAt: previewMoment.addingTimeInterval(-25), sent: true)
        case "recent-stopped":
            return RecentSound(event: "PHONE", observedAt: previewMoment.addingTimeInterval(-45), sent: false)
        default: return nil
        }
    }

    var body: some View {
        Group {
            if scenario == "guide" || scenario == "library" {
                SoundLibrary(canTest: false, disabledReason: "DESIGN PREVIEW · Manual tests are disabled.",
                             testSound: { _ in false })
            } else {
                ZStack {
                    ListeningBackdrop()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            FortWatchWordmark()
                            Text("DESIGN PREVIEW · SIMULATED STATE")
                                .font(.caption.monospaced())
                                .foregroundStyle(.white)
                            SoundPanel(angle: fixtureAngle, event: fixtureEvent,
                                       capturing: scenario != "recent-stopped",
                                       calibrated: fixtureEvent != nil || scenario == "recent-live-angle",
                                       calibrating: scenario == "calibrating-recent",
                                       calibrationFailed: scenario == "calibration-failed" || scenario == "calibration-failed-empty", starting: false,
                                       level: fixtureAngle == nil ? 25 : 48,
                                       status: "Keep one steady sound in front of the phone, then try again.",
                                       calibrate: {}, recentSound: fixtureRecent)
                        }
                        .padding(20)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview("App — idle") { ListenerView() }
#Preview("ALARM — simulated") { ListenerDesignPreview(scenario: "alarm") }
#Preview("CAR HORN — simulated") { ListenerDesignPreview(scenario: "car-horn") }
#Preview("GLASS — simulated") { ListenerDesignPreview(scenario: "glass") }
#Preview("SHOUT — simulated") { ListenerDesignPreview(scenario: "shout") }
#Preview("BABY — simulated") { ListenerDesignPreview(scenario: "baby") }
#Preview("KNOCK — simulated") { ListenerDesignPreview(scenario: "knock") }
#Preview("DOORBELL — simulated") { ListenerDesignPreview(scenario: "doorbell") }
#Preview("PHONE — simulated") { ListenerDesignPreview(scenario: "phone") }
#Preview("DOG — simulated") { ListenerDesignPreview(scenario: "dog") }
#Preview("SPEECH — simulated") { ListenerDesignPreview(scenario: "speech") }
#Preview("Listening without calibration — simulated") { ListenerDesignPreview(scenario: "uncalibrated") }
#Preview("Calibration failed, still listening — simulated") { ListenerDesignPreview(scenario: "calibration-failed-empty") }
#Preview("Calibration failed — simulated recent sound") { ListenerDesignPreview(scenario: "calibration-failed") }
#Preview("Calibrating — simulated recent sound") { ListenerDesignPreview(scenario: "calibrating-recent") }
#Preview("Expired location — simulated recent sound") { ListenerDesignPreview(scenario: "recent-live-angle") }
#Preview("Stopped — simulated recent sound") { ListenerDesignPreview(scenario: "recent-stopped") }
#Preview("Long direction — simulated") { ListenerDesignPreview(scenario: "long-label") }
#Preview("Unknown direction — simulated") { ListenerDesignPreview(scenario: "unknown") }
#Preview("Unknown sound — simulated") { ListenerDesignPreview(scenario: "unknown-sound") }
#Preview("Sound library — simulated") { ListenerDesignPreview(scenario: "library") }
#endif
