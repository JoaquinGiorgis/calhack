import AVFoundation
import Observation
import UIKit

@Observable @MainActor
final class ListenerModel {
    var address = ""
    var token = ""
    private(set) var active = false
    private(set) var capturing = false
    private(set) var status = "Conectá la Mac para comenzar."
    private(set) var calibrated = false
    private(set) var calibrating = false
    private(set) var angle: Double?
    private(set) var wristbandConnected = false
    private(set) var microphoneDenied = false
    @ObservationIgnored private var capture: SpatialCapture?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var responseDeadline: TimeInterval?
    @ObservationIgnored private var freshnessTask: Task<Void, Never>?
    @ObservationIgnored private var calibrationRequested = false

    func start() {
        guard !active else { return }
        do {
            let configuration = try BridgeConfiguration(address: address, token: token)
            active = true
            microphoneDenied = false
            capturing = false
            status = "Solicitando acceso al micrófono…"
            clearDirection()
            wristbandConnected = false
            generation = UUID()
            let run = generation
            Task { [weak self] in
                let allowed = await AVCaptureDevice.requestAccess(for: .audio)
                guard let self, self.generation == run, self.active else { return }
                guard allowed else {
                    self.stop(message: "Permití el micrófono en Configuración para usar FortWatch.")
                    self.microphoneDenied = true
                    return
                }
                self.status = "Preparando el micrófono…"
                self.capture = SpatialCapture(configuration: configuration) { [weak self] event in
                    DispatchQueue.main.async {
                        guard let self, self.generation == run else { return }
                        self.handle(event)
                    }
                }
                self.capture?.start()
                UIApplication.shared.isIdleTimerDisabled = true
                self.startFreshnessCheck()
            }
        } catch {
            status = error.localizedDescription
        }
    }

    func stop(message: String = "Captura detenida.") {
        generation = UUID()
        capture?.stop(message: message)
        capture = nil
        freshnessTask?.cancel()
        freshnessTask = nil
        active = false
        capturing = false
        status = message
        clearDirection()
        wristbandConnected = false
        responseDeadline = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func calibrate() {
        guard capturing else { return }
        calibrationRequested = true
        calibrated = false
        calibrating = true
        angle = nil
        status = "Mantené un sonido frente al teléfono durante un segundo."
        capture?.calibrateFront()
    }

    private func clearDirection() {
        angle = nil
        calibrated = false
        calibrating = false
        calibrationRequested = false
    }

    private func handle(_ event: CaptureEvent) {
        switch event {
        case .started:
            capturing = true
            status = "Esperando a la Mac…"
        case .waiting(let message):
            clearDirection()
            wristbandConnected = false
            responseDeadline = nil
            status = message
        case .stopped(let message):
            stop(message: message)
        case .response(let response, let expiresAt):
            guard ProcessInfo.processInfo.systemUptime < expiresAt else {
                angle = nil
                wristbandConnected = false
                status = "La respuesta llegó tarde. Esperando audio reciente…"
                return
            }
            responseDeadline = expiresAt
            wristbandConnected = response.wristband_connected
            // Ignore the response to an in-flight pre-calibration packet.
            if calibrationRequested {
                guard response.calibrating || !response.calibrated else { return }
                calibrationRequested = false
            }
            calibrated = response.calibrated
            calibrating = response.calibrating
            angle = response.usableAngle
            if calibrating {
                status = "Calibrando: mantené el sonido frente al teléfono."
            } else if !calibrated {
                status = response.reason == "calibration_failed_retry"
                    ? "No se pudo calibrar. Usá una única fuente clara y probá otra vez."
                    : "Conectado. Calibrá el frente del teléfono."
            } else if angle == nil {
                status = "Escuchando. Dirección incierta."
            } else {
                status = "Escuchando. Dirección relativa al teléfono."
            }
        }
    }

    private func startFreshnessCheck() {
        freshnessTask?.cancel()
        freshnessTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled, let self, self.active else { return }
                if let deadline = self.responseDeadline, ProcessInfo.processInfo.systemUptime >= deadline {
                    self.angle = nil
                    self.wristbandConnected = false
                    self.status = "Esperando audio reciente de la Mac…"
                }
            }
        }
    }
}
