import SwiftUI
import UIKit

@main
struct FortWatchListenerApp: App {
    var body: some Scene {
        WindowGroup { ListenerView() }
    }
}

private enum ListenerStyle {
    static let spacing: CGFloat = 16
    static let directionSize: CGFloat = 56
}

struct ListenerView: View {
    @State private var model = ListenerModel()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("El iPhone escucha. La Mac reconoce el sonido. La pulsera muestra la alerta y vibra.")
                    Text("Dejá el iPhone vertical en un soporte, sin cubrir los micrófonos. Mantené esta app abierta.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("Conectar a la Mac") {
                    TextField("IP o nombre .local de la Mac", text: $model.address)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .disabled(model.active)
                    SecureField("Código de conexión", text: $model.token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disabled(model.active)
                    Text("Usá la dirección y el código que muestra el receptor en la Mac. Ambos equipos deben estar en la misma red de confianza.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if model.active {
                        Button("Detener captura", role: .destructive) { model.stop() }
                    } else {
                        Button("Iniciar captura") { model.start() }
                            .disabled(model.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.token.isEmpty)
                    }
                }
                Section("Estado") {
                    Label(model.status, systemImage: model.capturing ? "waveform" : "mic.slash")
                    if model.microphoneDenied {
                        Button("Abrir Configuración") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                    }
                    Label(model.wristbandConnected ? "Pulsera conectada a la Mac" : "Pulsera sin confirmar",
                          systemImage: model.wristbandConnected ? "checkmark.circle" : "questionmark.circle")
                }
                Section("Dirección del sonido dominante") {
                    DirectionView(angle: model.angle)
                    Button(model.calibrating ? "Calibrando el frente…" : "Calibrar frente") { model.calibrate() }
                        .disabled(!model.capturing || model.calibrating)
                    Text("Para calibrar, mantené una única fuente de sonido frente al teléfono durante un segundo. Si movés el soporte, calibrá otra vez.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section {
                    Text("La vibración indica el tipo de alerta; la flecha indica la dirección relativa al teléfono. Varias fuentes o eco pueden volverla incierta.")
                    Text("El audio se transmite a la Mac por la red local y no se guarda en esta app. Al salir de la app se detiene la captura.")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .navigationTitle("FortWatch")
            .onChange(of: scenePhase) {
                if scenePhase == .background, model.active {
                    model.stop(message: "Captura detenida al salir de la app. Volvé a iniciar y calibrar.")
                }
            }
        }
    }
}

private struct DirectionView: View {
    let angle: Double?
    @ScaledMetric(relativeTo: .largeTitle) private var arrowSize = ListenerStyle.directionSize

    var body: some View {
        VStack(spacing: ListenerStyle.spacing) {
            if let angle {
                Image(systemName: "arrow.up")
                    .font(.system(size: arrowSize, weight: .semibold))
                    .rotationEffect(.degrees(angle))
                    .accessibilityHidden(true)
                Text(description(angle))
                    .font(.title2.bold())
                Text("Respecto del frente que calibraste")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "location.slash")
                    .font(.largeTitle)
                    .accessibilityHidden(true)
                Text("Dirección incierta")
                    .font(.title2.bold())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, ListenerStyle.spacing)
        .accessibilityElement(children: .combine)
    }

    private func description(_ angle: Double) -> String {
        let degrees = Int(abs(angle).rounded())
        if degrees < 5 { return "Al frente" }
        if degrees >= 175 { return "Detrás" }
        return "\(degrees)° a la \(angle < 0 ? "izquierda" : "derecha")"
    }
}
