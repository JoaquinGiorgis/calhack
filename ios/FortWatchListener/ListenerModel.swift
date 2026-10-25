import AVFoundation
import Observation
import UIKit

@Observable @MainActor
final class ListenerModel {
    let bluetooth = WristbandBluetooth()
    private(set) var active = false
    private(set) var capturing = false
    private(set) var status = "Connect your wristband to get started."
    private(set) var calibrated = false
    private(set) var calibrating = false
    private(set) var calibrationFailed = false
    private(set) var angle: Double?
    private(set) var directionCue = SoundDirectionCue(angle: nil, event: nil)
    var directionAngle: Double? { directionCue.angle }
    var directionEvent: String? { directionCue.event }
    private(set) var level = 0
    private(set) var lastEvent: String?
    private(set) var lastEventSent = false
    private(set) var recentSound: RecentSound?
    private(set) var microphoneDenied = false
    @ObservationIgnored private var capture: SpatialCapture?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var audioDeadline: TimeInterval?
    @ObservationIgnored private var freshnessTask: Task<Void, Never>?
    @ObservationIgnored private var calibrationRequested = false
    @ObservationIgnored private var lastLevelSent = -Double.infinity
    @ObservationIgnored private var lastTimeSent = -Double.infinity
    @ObservationIgnored private var directionalAlert: SoundEventDetection?
    @ObservationIgnored private var calibrateAfterStart = false
    @ObservationIgnored private var resumeListeningAfterReconnect = false

    init() {
        bluetooth.onConnect = { [weak self] in
            guard let self else { return }
            if self.resumeListeningAfterReconnect {
                self.resumeListeningAfterReconnect = false
                self.status = "Wristband reconnected. Restarting listening…"
                self.start()
            } else {
                self.status = "Wristband ready. Test vibration or start listening."
            }
        }
        bluetooth.onDisconnect = { [weak self] message in
            guard let self else { return }
            if self.active {
                self.stop(message: message + " Listening will restart after reconnection.")
                self.resumeListeningAfterReconnect = true
            } else {
                self.status = message
            }
        }
    }

    func start(calibrateWhenReady: Bool = false) {
        guard !active else { return }
        guard bluetooth.isConnected else {
            status = "Connect your FortWatch wristband first."
            return
        }
        active = true
        calibrateAfterStart = calibrateWhenReady
        microphoneDenied = false
        capturing = false
        status = "Requesting microphone access…"
        recordCaptureStatus("starting")
        clearDirection()
        lastEvent = nil
        lastEventSent = false
        recentSound = nil
        generation = UUID()
        let run = generation
        Task { [weak self] in
            let allowed = await AVCaptureDevice.requestAccess(for: .audio)
            guard let self, self.generation == run, self.active else { return }
            guard allowed else {
                self.stop(message: "Allow microphone access in Settings to use FortWatch.")
                self.microphoneDenied = true
                return
            }
            guard self.bluetooth.isConnected else {
                self.stop(message: "Connection lost. Reconnect your wristband.")
                return
            }
            self.status = "Preparing sound recognition on your iPhone…"
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

    func stop(message: String = "Listening stopped.") {
        generation = UUID()
        capture?.stop(message: message)
        capture = nil
        freshnessTask?.cancel()
        freshnessTask = nil
        active = false
        calibrateAfterStart = false
        capturing = false
        status = message
        recordCaptureStatus("stopped")
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
        resumeListeningAfterReconnect = false
        if active { stop() }
        bluetooth.disconnect()
        status = "Wristband disconnected."
    }

    func testWristband() {
        testSound(event: "KNOCK")
    }

    @discardableResult
    func testSound(event: String) -> Bool {
        guard !active, bluetooth.isConnected,
              SoundHapticPattern.supports(event) else { return false }
        let sent = bluetooth.sendPatternTest(event: event)
        status = sent
            ? "Test sent: " + (SoundCatalog.forEvent(event)?.title ?? event.replacingOccurrences(of: "_", with: " ")) + ". "
                + SoundHapticPattern.forEvent(event).description + "."
            : "Test could not be sent. Check the connection and try again."
        return sent
    }

    func suspend() {
        resumeListeningAfterReconnect = false
        if active { stop(message: "Listening stopped when you left the app. Start again and recalibrate.") }
        bluetooth.disconnect()
    }

    func calibrate() {
        if !capturing {
            guard !active, bluetooth.isConnected else { return }
            start(calibrateWhenReady: true)
            return
        }
        guard capturing, !calibrating else { return }
        calibrationRequested = true
        calibrated = false
        calibrating = true
        calibrationFailed = false
        angle = nil
        lastEvent = nil
        directionalAlert = nil
        refreshDirectionCue()
        bluetooth.clearPendingAlerts()
        status = "Keep one sound in front of the phone for one second."
        capture?.calibrateFront()
    }

    private func clearDirection() {
        angle = nil
        directionalAlert = nil
        refreshDirectionCue()
        calibrated = false
        calibrating = false
        calibrationFailed = false
        calibrationRequested = false
    }

    private func handle(_ event: CaptureEvent) {
        switch event {
        case .started:
            capturing = true
            status = "Listening on your iPhone. Set the front direction to locate sounds."
            recordCaptureStatus("capturing")
            bluetooth.sendTime()
            lastTimeSent = ProcessInfo.processInfo.systemUptime
            if calibrateAfterStart {
                calibrateAfterStart = false
                calibrate()
            }
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
                refreshDirectionCue()
                status = "Waiting for fresh microphone audio…"
                return
            }
            audioDeadline = update.expiresAt
            calibrated = update.calibrated
            calibrating = update.calibrating
            calibrationFailed = update.calibrationFailed
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
                directionalAlert = alert
                if alert.shouldNotify {
                    lastEventSent = bluetooth.sendAlert(event: alert.event, score: alert.score,
                                                       angle: alert.angle, quality: alert.quality,
                                                       validUntil: alert.expiresAt)
                } else {
                    lastEventSent = bluetooth.sendDisplay(event: alert.event, score: alert.score,
                                                         angle: alert.angle, quality: alert.quality,
                                                         validUntil: alert.expiresAt)
                }
                recentSound = RecentSound(event: alert.event, observedAt: Date(), sent: lastEventSent)
            }
            refreshDirectionCue()
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
                    self.status = "Waiting for fresh microphone audio…"
                }
                self.refreshDirectionCue()
            }
        }
    }

    private func refreshDirectionCue() {
        let now = ProcessInfo.processInfo.systemUptime
        if let alert = directionalAlert, now >= alert.expiresAt { directionalAlert = nil }
        directionCue = .current(liveAngle: angle, alert: directionalAlert, at: now)
    }

    // A single local diagnostic record for device bring-up. No audio, recognized
    // events, Bluetooth identifiers, or network credentials are written here.
    private func recordCaptureStatus(_ state: String) {
        guard let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
              let data = try? JSONSerialization.data(withJSONObject: ["state": state, "message": status],
                                                     options: [.sortedKeys]) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: directory.appendingPathComponent("fortwatch-capture-status.json"), options: .atomic)
    }
}
