import SwiftUI
import UIKit

@main
struct FortWatchListenerApp: App {
    var body: some Scene {
        WindowGroup { ListenerView() }
    }
}

// Shared with the wristband: charcoal, saturated blue, white type.
private enum ListenerStyle {
    static let background = Color(red: 0.07, green: 0.08, blue: 0.10)
    static let surface = Color(red: 0.11, green: 0.12, blue: 0.15)
    static let secondary = Color(red: 0.73, green: 0.76, blue: 0.82)
    static let blue = Color(red: 0.16, green: 0.31, blue: 0.82)
    static let deepBlue = Color(red: 0.07, green: 0.14, blue: 0.38)
    static let green = Color(red: 0.43, green: 0.89, blue: 0.72)
    static let red = Color(red: 0.64, green: 0.12, blue: 0.18)
    static let radius: CGFloat = 20
}

struct ListenerView: View {
    @State private var model = ListenerModel()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    bluetoothPanel
                    DirectionPanel(angle: model.angle, capturing: model.capturing,
                                   calibrated: model.calibrated, calibrating: model.calibrating,
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
            .scrollDismissesKeyboard(.interactively)
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
                .font(.system(size: 22, weight: .medium))
                .frame(width: 48, height: 48)
                .background(ListenerStyle.surface, in: .rect(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.16)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("FortWatch")
                    .font(.largeTitle.weight(.bold))
                    .tracking(-1)
                    .accessibilityAddTraits(.isHeader)
                Text("SONIDO QUE SE SIENTE")
                    .font(.caption.monospaced().weight(.medium))
                    .tracking(1.2)
                    .foregroundStyle(ListenerStyle.secondary)
            }
        }
        .foregroundStyle(.white)
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(model.status, systemImage: model.capturing ? "mic.fill" : "mic.slash")
                .font(.subheadline)
                .foregroundStyle(ListenerStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if model.microphoneDenied || model.bluetooth.settingsDenied {
                Button("Abrir Configuración", systemImage: "gearshape") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .buttonStyle(ListenerButtonStyle(fill: ListenerStyle.blue))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bluetoothPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(model.bluetooth.isConnected ? "Pulsera conectada" : "Conectá tu pulsera",
                  systemImage: model.bluetooth.isConnected ? "checkmark.circle" : "applewatch")
                .font(.headline)
                .foregroundStyle(model.bluetooth.isConnected ? ListenerStyle.green : .white)
                .accessibilityAddTraits(.isHeader)
            Text(model.bluetooth.status)
                .font(.subheadline)
                .foregroundStyle(ListenerStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if model.bluetooth.isConnected {
                Button("Probar vibración", systemImage: "waveform.path") { model.testWristband() }
                    .buttonStyle(ListenerButtonStyle(fill: ListenerStyle.blue))
                    .disabled(model.active)
                Button("Desconectar pulsera", systemImage: "xmark.circle") { model.disconnect() }
                    .buttonStyle(ListenerButtonStyle(fill: ListenerStyle.background))
            } else if model.bluetooth.connecting {
                Button("Cancelar búsqueda", systemImage: "xmark") { model.disconnect() }
                    .buttonStyle(ListenerButtonStyle(fill: ListenerStyle.background))
            } else {
                Button("Conectar pulsera", systemImage: "antenna.radiowaves.left.and.right") {
                    model.bluetooth.connect()
                }
                .buttonStyle(ListenerButtonStyle(fill: ListenerStyle.blue))
            }
        }
        .padding(20)
        .background(ListenerStyle.surface, in: .rect(cornerRadius: ListenerStyle.radius))
        .overlay(RoundedRectangle(cornerRadius: ListenerStyle.radius).strokeBorder(.white.opacity(0.20)))
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("El iPhone reconoce el sonido. La pulsera te avisa.", systemImage: "waveform.path")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
            Text("Dejá el iPhone vertical en un soporte, sin cubrir los micrófonos. Para calibrar, mantené una única fuente de sonido frente al teléfono durante un segundo. Si movés el soporte, calibrá otra vez.")
            Text("La vibración indica el tipo de alerta; la flecha, la dirección respecto del teléfono. Varias fuentes o eco pueden volverla incierta.")
            Label("El audio se procesa en tu iPhone y no se guarda. Por Bluetooth solo viajan las alertas y el nivel de sonido. Al salir de la app se detiene la escucha.", systemImage: "iphone")
        }
        .font(.footnote)
        .foregroundStyle(ListenerStyle.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 4)
    }

    private var captureControl: some View {
        VStack(spacing: 8) {
            if model.active {
                Button("Detener escucha", systemImage: "stop.fill", role: .destructive) { model.stop() }
                    .buttonStyle(ListenerButtonStyle(fill: ListenerStyle.red))
            } else {
                Button("Iniciar escucha", systemImage: "mic.fill") { model.start() }
                    .buttonStyle(ListenerButtonStyle(fill: ListenerStyle.blue))
                    .disabled(!model.bluetooth.isConnected)
            }
            Text("Mantené esta app abierta durante la escucha.")
                .font(.caption)
                .foregroundStyle(ListenerStyle.secondary)
        }
        .padding(.horizontal, 20)
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
    let capturing: Bool
    let calibrated: Bool
    let calibrating: Bool
    let calibrate: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("SONIDO DOMINANTE", systemImage: "scope")
                .font(.caption.monospaced().weight(.semibold))
                .tracking(1.2)
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 18))
            layout {
                DirectionDial(angle: angle)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.title.weight(.bold))
                        .tracking(-0.5)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            Rectangle().fill(.white.opacity(0.28)).frame(height: 1)
            Button(action: calibrate) {
                Label(calibrating ? "Calibrando el frente…" : "Calibrar frente", systemImage: "viewfinder")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding(.horizontal, 12)
            }
            .buttonStyle(.plain)
            .background(.black.opacity(0.20), in: .rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.5)))
            .disabled(!capturing || calibrating)
            .opacity(!capturing || calibrating ? 0.5 : 1)
            .accessibilityHint("Mantené un sonido frente al teléfono durante un segundo.")
        }
        .padding(20)
        .foregroundStyle(.white)
        .background(LinearGradient(colors: [ListenerStyle.blue, ListenerStyle.deepBlue],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: .rect(cornerRadius: ListenerStyle.radius))
        .overlay(RoundedRectangle(cornerRadius: ListenerStyle.radius).strokeBorder(.white.opacity(0.28)))
    }

    private var title: String {
        if let angle { return "\(Int(abs(angle).rounded()))°" }
        if calibrating { return "Calibrando" }
        if !capturing { return "En espera" }
        if !calibrated { return "Fijá el frente" }
        return "Dirección incierta"
    }

    private var subtitle: String {
        if let angle {
            let degrees = Int(abs(angle).rounded())
            let side = degrees < 5 ? "Al frente" : degrees >= 175 ? "Detrás" : angle < 0 ? "A la izquierda" : "A la derecha"
            return "\(side)\nRespecto del frente calibrado."
        }
        if calibrating { return "Mantené un sonido frente al iPhone." }
        if !capturing { return "Conectá la pulsera y empezá a escuchar." }
        if !calibrated { return "Calibrá con un sonido frente al iPhone." }
        return "Esperando una dirección clara."
    }
}

private struct DirectionDial: View {
    let angle: Double?

    var body: some View {
        ZStack {
            Circle().strokeBorder(.white.opacity(0.12), lineWidth: 1)
            Circle().strokeBorder(.white.opacity(0.22), lineWidth: 1).padding(10)
            Circle().fill(.white.opacity(0.10)).padding(21)
            Circle().strokeBorder(.white.opacity(0.55), lineWidth: 1).padding(21)
            if let angle {
                Image(systemName: "arrow.up")
                    .font(.system(size: 32, weight: .semibold))
                    .rotationEffect(.degrees(angle))
            } else {
                Image(systemName: "location.slash")
                    .font(.system(size: 28, weight: .light))
            }
        }
        .frame(width: 110, height: 110)
        .accessibilityHidden(true)
    }
}

private struct SoundAlertCard: View {
    let event: String
    let sent: Bool

    private var appearance: (title: String, icon: String, color: Color) {
        switch event {
        case "ALARM": return ("ALARMA", "light.beacon.max", ListenerStyle.red)
        case "CAR_HORN": return ("BOCINA", "car.side", Color(red: 0.55, green: 0.22, blue: 0.04))
        case "GLASS": return ("VIDRIO", "wineglass", Color(red: 0.55, green: 0.10, blue: 0.28))
        case "SHOUT": return ("GRITO", "megaphone", Color(red: 0.55, green: 0.10, blue: 0.33))
        case "BABY": return ("BEBÉ", "figure.child", Color(red: 0.04, green: 0.35, blue: 0.33))
        case "KNOCK": return ("GOLPES", "door.left.hand.closed", ListenerStyle.blue)
        case "DOORBELL": return ("TIMBRE", "bell", Color(red: 0.34, green: 0.12, blue: 0.60))
        case "PHONE": return ("TELÉFONO", "phone", Color(red: 0.27, green: 0.32, blue: 0.40))
        case "DOG": return ("LADRIDO", "dog", Color(red: 0.40, green: 0.26, blue: 0.10))
        default: return ("VOZ", "text.bubble", Color(red: 0.08, green: 0.36, blue: 0.19))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ÚLTIMO SONIDO DETECTADO")
                .font(.caption.monospaced().weight(.semibold))
                .tracking(1)
            Label(appearance.title, systemImage: appearance.icon)
                .font(.title.weight(.bold))
            Label(sent ? "Alerta enviada por Bluetooth" : "Detectado; no se pudo enviar a la pulsera",
                  systemImage: sent ? "checkmark.circle" : "exclamationmark.circle")
                .font(.subheadline)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .foregroundStyle(.white)
        .background(LinearGradient(colors: [appearance.color, appearance.color.opacity(0.6)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: .rect(cornerRadius: ListenerStyle.radius))
        .overlay(RoundedRectangle(cornerRadius: ListenerStyle.radius).strokeBorder(.white.opacity(0.28)))
        .accessibilityElement(children: .combine)
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

#Preview { ListenerView() }
