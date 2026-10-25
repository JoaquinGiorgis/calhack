import AVFoundation
import Observation
import UIKit

@Observable @MainActor
final class ListenerModel {
    let bluetooth = WristbandBluetooth()
    private(set) var active = false
    private(set) var capturing = false
    private(set) var status = "Conectá la pulsera por Bluetooth para comenzar."
    private(set) var calibrated = false
    private(set) var calibrating = false
    private(set) var angle: Double?
    private(set) var level = 0
    private(set) var lastEvent: String?
    private(set) var lastEventSent = false
    private(set) var microphoneDenied = false
    @ObservationIgnored private var capture: SpatialCapture?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var audioDeadline: TimeInterval?
    @ObservationIgnored private var freshnessTask: Task<Void, Never>?
    @ObservationIgnored private var calibrationRequested = false
    @ObservationIgnored private var lastLevelSent = -Double.infinity
    @ObservationIgnored private var lastTimeSent = -Double.infinity

    init() {
        bluetooth.onConnect = { [weak self] in
            self?.status = "Pulsera lista. Probá la vibración o iniciá la escucha."
        }
        bluetooth.onDisconnect = { [weak self] message in
            guard let self else { return }
            if self.active {
                self.stop(message: message + " Volvé a conectar la pulsera e iniciar la escucha.")
            } else {
                self.status = message
            }
        }
    }

    func start() {
        guard !active else { return }
        guard bluetooth.isConnected else {
            status = "Conectá primero la pulsera FortWatch."
            return
        }
        active = true
        microphoneDenied = false
        capturing = false
        status = "Solicitando acceso al micrófono…"
        clearDirection()
        lastEvent = nil
        lastEventSent = false
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
            guard self.bluetooth.isConnected else {
                self.stop(message: "Se perdió la conexión. Volvé a conectar la pulsera.")
                return
            }
            self.status = "Preparando el reconocimiento en el iPhone…"
            self.capture = SpatialCapture { [weak self] event in
                DispatchQueue.main.async {
                    guard let self, self.generation == run, self.active else { return }
                    self.handle(event)
                }
            }
            self.capture?.start()
            UIApplication.shared.isIdleTimerDisabled = true
            self.startFreshnessCheck()
        }
    }

    func stop(message: String = "Escucha detenida.") {
        generation = UUID()
        capture?.stop(message: message)
        capture = nil
        freshnessTask?.cancel()
        freshnessTask = nil
        active = false
        capturing = false
        status = message
        clearDirection()
        audioDeadline = nil
        level = 0
        lastEvent = nil
        lastEventSent = false
        bluetooth.clearPendingAlerts()
        bluetooth.sendLevel(0)
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func disconnect() {
        if active { stop() }
        bluetooth.disconnect()
        status = "Pulsera desconectada."
    }

    func testWristband() {
        guard !active, bluetooth.isConnected else { return }
        let sent = bluetooth.sendAlert(event: "KNOCK", score: 1, angle: nil, quality: nil,
                                       validUntil: ProcessInfo.processInfo.systemUptime + 0.75)
        status = sent
            ? "Prueba enviada: buscá KNOCK en la pulsera y dos vibraciones cortas."
            : "No se pudo enviar la prueba. Revisá la conexión y probá otra vez."
    }

    func suspend() {
        if active { stop(message: "Escucha detenida al salir de la app. Volvé a iniciar y calibrar.") }
        bluetooth.disconnect()
    }

    func calibrate() {
        guard capturing, !calibrating else { return }
        calibrationRequested = true
        calibrated = false
        calibrating = true
        angle = nil
        lastEvent = nil
        bluetooth.clearPendingAlerts()
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
            status = "Escuchando en el iPhone. Calibrá el frente para ubicar los sonidos."
            bluetooth.sendTime()
            lastTimeSent = ProcessInfo.processInfo.systemUptime
        case .stopped(let message):
            stop(message: message)
        case .update(let update):
            // Main-queue updates from before the calibration tap must not revive old alerts.
            if calibrationRequested {
                guard update.calibrating else { return }
                calibrationRequested = false
            }
            let now = ProcessInfo.processInfo.systemUptime
            guard now < update.expiresAt else {
                angle = nil
                status = "Esperando audio reciente del micrófono…"
                return
            }
            audioDeadline = update.expiresAt
            calibrated = update.calibrated
            calibrating = update.calibrating
            if calibrated, !calibrating, let value = update.angle, value.isFinite,
               (-180...180).contains(value), let quality = update.quality,
               quality.isFinite, (0.60...1).contains(quality) {
                angle = value
            } else {
                angle = nil
            }
            level = min(100, max(0, update.level))
            status = update.status
            // Alert first: metering and time must not occupy a write slot ahead of it.
            if let alert = update.alert, !calibrating, now < alert.expiresAt {
                lastEvent = alert.event
                lastEventSent = bluetooth.sendAlert(event: alert.event, score: alert.score,
                                                     angle: alert.angle, quality: alert.quality,
                                                     validUntil: alert.expiresAt)
            }
            if now - lastLevelSent >= 0.25 {
                bluetooth.sendLevel(level)
                lastLevelSent = now
            }
            if now - lastTimeSent >= 10 {
                bluetooth.sendTime()
                lastTimeSent = now
            }
        }
    }

    private func startFreshnessCheck() {
        freshnessTask?.cancel()
        freshnessTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled, let self, self.active else { return }
                if let deadline = self.audioDeadline, ProcessInfo.processInfo.systemUptime >= deadline {
                    self.angle = nil
                    self.level = 0
                    self.status = "Esperando audio reciente del micrófono…"
                }
            }
        }
    }
}
