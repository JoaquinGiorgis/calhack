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
                    DirectionPanel(angle: model.angle, capturing: model.capturing,
                                   calibrated: model.calibrated, calibrating: model.calibrating,
                                   calibrate: model.calibrate)
                    status
                    ConnectionPanel(address: $model.address, token: $model.token, active: model.active)
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
                if scenePhase == .background, model.active {
                    model.stop(message: "Captura detenida al salir de la app. Volvé a iniciar y calibrar.")
                }
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
            if model.microphoneDenied {
                Button("Abrir Configuración", systemImage: "gearshape") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .buttonStyle(ListenerButtonStyle(fill: ListenerStyle.blue))
            }
            Label(model.wristbandConnected ? "Pulsera conectada a la Mac" : "Pulsera sin confirmar",
                  systemImage: model.wristbandConnected ? "checkmark.circle" : "questionmark.circle")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(model.wristbandConnected ? ListenerStyle.green : ListenerStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("El iPhone escucha. La Mac reconoce. La pulsera vibra.", systemImage: "waveform.path")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
            Text("Dejá el iPhone vertical en un soporte, sin cubrir los micrófonos. Para calibrar, mantené una única fuente de sonido frente al teléfono durante un segundo. Si movés el soporte, calibrá otra vez.")
            Text("La vibración indica el tipo de alerta; la flecha, la dirección respecto del teléfono. Varias fuentes o eco pueden volverla incierta.")
            Label("El audio va a la Mac por la red local y no se guarda en esta app. Al salir, se detiene la captura.", systemImage: "network")
        }
        .font(.footnote)
        .foregroundStyle(ListenerStyle.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 4)
    }

    private var captureControl: some View {
        VStack(spacing: 8) {
            if model.active {
                Button("Detener captura", systemImage: "stop.fill", role: .destructive) { model.stop() }
                    .buttonStyle(ListenerButtonStyle(fill: ListenerStyle.red))
            } else {
                Button("Iniciar captura", systemImage: "mic.fill") { model.start() }
                    .buttonStyle(ListenerButtonStyle(fill: ListenerStyle.blue))
                    .disabled(model.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.token.isEmpty)
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
        if !capturing { return "Conectá la Mac para ubicar el sonido." }
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

private struct ConnectionPanel: View {
    @Binding var address: String
    @Binding var token: String
    let active: Bool
    @FocusState private var focusedField: Field?
    private enum Field { case address, token }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Conectar a la Mac", systemImage: "laptopcomputer")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 7) {
                fieldLabel("DIRECCIÓN DE LA MAC")
                TextField("IP o nombre .local", text: $address,
                          prompt: Text("IP o nombre .local").foregroundStyle(ListenerStyle.secondary))
                    .keyboardType(.URL)
                    .submitLabel(.next)
                    .focused($focusedField, equals: .address)
                    .onSubmit { focusedField = .token }
                    .accessibilityLabel("IP o nombre local de la Mac")
                    .modifier(ConnectionFieldStyle(focused: focusedField == .address))
            }
            VStack(alignment: .leading, spacing: 7) {
                fieldLabel("CÓDIGO DE CONEXIÓN")
                SecureField("Pegá el código de la Mac", text: $token,
                            prompt: Text("Pegá el código de la Mac").foregroundStyle(ListenerStyle.secondary))
                    .submitLabel(.done)
                    .focused($focusedField, equals: .token)
                    .onSubmit { focusedField = nil }
                    .accessibilityLabel("Código de conexión")
                    .modifier(ConnectionFieldStyle(focused: focusedField == .token))
            }
            Text("Usá la dirección y el código del receptor. Ambos equipos deben estar en la misma red de confianza.")
                .font(.footnote)
                .foregroundStyle(ListenerStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .disabled(active)
        .padding(20)
        .foregroundStyle(.white)
        .background(ListenerStyle.surface, in: .rect(cornerRadius: ListenerStyle.radius))
        .overlay(RoundedRectangle(cornerRadius: ListenerStyle.radius).strokeBorder(.white.opacity(0.14)))
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Listo") { focusedField = nil }
            }
        }
        .onChange(of: active) { if active { focusedField = nil } }
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption.monospaced().weight(.medium))
            .tracking(0.8)
            .foregroundStyle(ListenerStyle.secondary)
            .accessibilityHidden(true)
    }
}

private struct ConnectionFieldStyle: ViewModifier {
    let focused: Bool

    func body(content: Content) -> some View {
        content
            .font(.body)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .frame(minHeight: 48)
            .background(ListenerStyle.background, in: .rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(focused ? .white : .white.opacity(0.38), lineWidth: focused ? 2 : 1))
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
