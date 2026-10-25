import AVFoundation
import Foundation

enum CaptureEvent {
    case started
    case update(LocalAudioUpdate)
    case stopped(String)
}

/// Capture and mutable state have one serial owner. Inference has one bounded slot
/// on a separate queue; audio stays in memory and never leaves the phone.
final class SpatialCapture: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    private static let lifecycleQueue = DispatchQueue(label: "dev.fortwatch.spatial.capture", qos: .userInitiated)
    private static let inferenceQueue = DispatchQueue(label: "dev.fortwatch.spatial.classify", qos: .userInitiated)
    private let queue = SpatialCapture.lifecycleQueue
    private let captureSession = AVCaptureSession()
    private let onEvent: (CaptureEvent) -> Void
    private var running = false
    private var pendingSamples: [Float] = []
    private var pendingPTS: Double?
    private var sampleRate: Int?
    private var nextExpectedPTS: Double?
    private var observers: [NSObjectProtocol] = []
    private var watchdog: DispatchSourceTimer?
    private var lastSampleTime = ProcessInfo.processInfo.systemUptime
    private var calibration = FrontCalibration()
    private var calibrationStartedAt: TimeInterval?
    private var selector = YAMNetEventSelector()
    private var ring = SpatialSampleRing()
    private var analysisGeneration = UUID()
    private var analysisFrame: Int64 = 0
    private var analysisBusy = false
    private var analysisStartedAt: TimeInterval = 0
    private var windowSchedule = YAMNetWindowSchedule()
    private var inferenceCount = 0
    private var lastInferenceMilliseconds = 0.0
    private var currentLevel = 0
    private var currentDirection = SpatialDirectionResult(angle: nil, quality: nil, reason: "not_calibrated")
    private var directionSamples: [Float] = []
    private var currentExpiry: TimeInterval = 0
    private var lastDiagnosticWrite = -Double.infinity
    private var diagnosticWindows = 0
    private var diagnosticValidWindows = 0
    private var diagnosticPeakQuality = 0.0
    private var lastDiagnosticSnapshot: [String: Any] = [:]
    // Accessed exclusively on inferenceQueue.
    private var classifier: YAMNetClassifier?

    init(onEvent: @escaping (CaptureEvent) -> Void) {
        self.onEvent = onEvent
        super.init()
    }

    func start() {
        queue.async { [self] in
            do {
                // Let AVCaptureSession negotiate the built-in microphone's FOA
                // configuration, as in Apple's spatial-audio capture sample.
                // Forcing .record/.default yielded audio but no directional
                // intensity on the connected iPhone during physical diagnosis.
                captureSession.automaticallyConfiguresApplicationAudioSession = true
                try configureCapture()
                // Load and warm the bundled model before microphone capture.
                try Self.inferenceQueue.sync {
                    let model = try YAMNetClassifier()
                    _ = try model.predict(waveform: [Float](repeating: 0, count: YAMNetClassifier.inputFrames))
                    classifier = model
                }
                running = true
                lastSampleTime = ProcessInfo.processInfo.systemUptime
                captureSession.startRunning()
                guard captureSession.isRunning else { throw ListenerError.message("Could not start the microphone.") }
                observeInterruptions()
                beginWatchdog()
                // Delegate buffers use this same queue, so started is always first.
                onEvent(.started)
            } catch {
                stopOnQueue(error.localizedDescription)
            }
        }
    }

    private func configureCapture() throws {
        guard let device = AVCaptureDevice.default(for: .audio) else {
            throw ListenerError.message("No audio input is available.")
        }
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }
        let input = try AVCaptureDeviceInput(device: device)
        guard captureSession.canAddInput(input) else {
            throw ListenerError.message("Could not connect the microphone for capture.")
        }
        captureSession.addInput(input)
        // Apple checks support only after attaching the input to the session.
        guard input.isMultichannelAudioModeSupported(.firstOrderAmbisonics) else {
            throw ListenerError.message("This device does not support spatial capture. Use an iPhone 16 Pro or later with iOS 26.")
        }
        input.multichannelAudioMode = .firstOrderAmbisonics
        if #available(iOS 26.4, *), input.isAudioZoomSupported { input.isAudioZoomEnabled = false }
        let output = AVCaptureAudioDataOutput()
        output.spatialAudioChannelLayoutTag = SpatialPCM.layoutTag
        guard captureSession.canAddOutput(output) else {
            throw ListenerError.message("Could not access spatial audio.")
        }
        captureSession.addOutput(output)
        output.setSampleBufferDelegate(self, queue: queue)
    }

    func calibrateFront() {
        queue.async { [self] in
            guard running else { return }
            invalidateAnalysis()
            pendingSamples.removeAll(keepingCapacity: true)
            pendingPTS = nil
            directionSamples.removeAll(keepingCapacity: true)
            let now = ProcessInfo.processInfo.systemUptime
            calibration.start(now: now)
            calibrationStartedAt = now
            diagnosticWindows = 0
            diagnosticValidWindows = 0
            diagnosticPeakQuality = 0
            lastDiagnosticWrite = -Double.infinity
            currentDirection = SpatialDirectionResult(angle: nil, quality: nil, reason: "calibrating")
            currentExpiry = now + 0.75
            publish(status: "Keep a sound in front of the phone for one second.")
        }
    }

    func stop(message: String = "Listening stopped.") {
        queue.async { [self] in stopOnQueue(message) }
    }

    private func stopOnQueue(_ message: String) {
        running = false
        if !lastDiagnosticSnapshot.isEmpty {
            lastDiagnosticSnapshot["capturing"] = false
            lastDiagnosticSnapshot["stoppedAt"] = Date().timeIntervalSince1970
            writeSpatialDiagnostics(lastDiagnosticSnapshot)
        }
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        watchdog?.cancel()
        watchdog = nil
        pendingSamples.removeAll(keepingCapacity: false)
        pendingPTS = nil
        directionSamples.removeAll(keepingCapacity: false)
        calibration.reset()
        invalidateAnalysis()
        Self.inferenceQueue.async { [self] in classifier = nil }
        if captureSession.isRunning { captureSession.stopRunning() }
        onEvent(.stopped(message))
    }

    private func observeInterruptions() {
        for name in [AVAudioSession.interruptionNotification, AVAudioSession.routeChangeNotification,
                     AVCaptureSession.wasInterruptedNotification, AVCaptureSession.runtimeErrorNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                self?.queue.async { [weak self] in
                    guard let self, self.running else { return }
                    self.stopOnQueue("Capture was interrupted or the microphone changed. Restart listening and recalibrate.")
                }
            })
        }
    }

    private func beginWatchdog() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            guard let self, self.running else { return }
            let now = ProcessInfo.processInfo.systemUptime
            if now - self.lastSampleTime > 3 {
                self.stopOnQueue("The microphone stopped sending audio. Restart listening.")
            } else if self.analysisBusy && now - self.analysisStartedAt > 3 {
                self.stopOnQueue("Sound recognition took too long. Restart listening.")
            }
        }
        timer.resume()
        watchdog = timer
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard running else { return }
        do {
            guard AVAudioSession.sharedInstance().currentRoute.inputs.contains(where: { $0.portType == .builtInMic }) else {
                throw ListenerError.message("Input switched to an external microphone. Switch back to the built-in microphone and restart.")
            }
            let decoded = try SpatialPCM.decode(sampleBuffer)
            if let sampleRate, sampleRate != decoded.rate {
                throw ListenerError.message("The audio sample rate changed. Restart listening and recalibrate.")
            }
            sampleRate = decoded.rate
            let now = ProcessInfo.processInfo.systemUptime
            lastSampleTime = now
            let decodedEndPTS = decoded.pts + Double(decoded.samples.count / 4) / Double(decoded.rate)
            guard let sourceClock = captureSession.synchronizationClock else {
                throw ListenerError.message("Could not synchronize microphone timing.")
            }
            let hostClock = CMClockGetHostTimeClock()
            let hostEnd = CMSyncConvertTime(CMTime(seconds: decodedEndPTS, preferredTimescale: CMTimeScale(decoded.rate)),
                                           from: sourceClock, to: hostClock)
            let age = CMTimeGetSeconds(CMTimeSubtract(CMClockGetTime(hostClock), hostEnd))
            guard age.isFinite, age >= -0.05 else {
                throw ListenerError.message("Audio timing is invalid. Restart listening.")
            }
            guard age < 0.75 else {
                resetForCaptureGap()
                currentExpiry = now + 0.75
                publish(status: "Audio arrived late. Calibrate the front again.")
                return
            }
            let decodedEndUptime = now - max(0, age)
            if let expected = nextExpectedPTS, abs(decoded.pts - expected) > 2.0 / Double(decoded.rate) {
                resetForCaptureGap()
            }
            nextExpectedPTS = decodedEndPTS
            if pendingPTS == nil { pendingPTS = decoded.pts }
            pendingSamples.append(contentsOf: decoded.samples)
            let chunkFrames = decoded.rate / 10
            let chunkSamples = chunkFrames * 4
            while pendingSamples.count >= chunkSamples {
                guard let pts = pendingPTS else { break }
                let samples = Array(pendingSamples.prefix(chunkSamples))
                pendingSamples.removeFirst(chunkSamples)
                let endPTS = pts + Double(chunkFrames) / Double(decoded.rate)
                pendingPTS = endPTS
                let capturedEnd = decodedEndUptime - (decodedEndPTS - endPTS)
                try processChunk(samples, rate: decoded.rate, capturedEnd: capturedEnd, now: now)
            }
        } catch {
            stopOnQueue(error.localizedDescription)
        }
    }

    private func processChunk(_ samples: [Float], rate: Int, capturedEnd: TimeInterval, now: TimeInterval) throws {
        let frames = samples.count / 4
        let power = stride(from: 0, to: samples.count, by: 4).reduce(0.0) { $0 + Double(samples[$1]) * Double(samples[$1]) }
        let rms = sqrt(power / Double(frames))
        currentLevel = Int(min(100, max(0, (20 * log10(max(rms, 1e-9)) + 60) / 60 * 100)))
        currentExpiry = capturedEnd + 0.75
        if calibration.calibrating {
            // Exclude buffers that were already in the capture pipeline at the tap.
            if let started = calibrationStartedAt, capturedEnd - Double(frames) / Double(rate) >= started {
                calibration.consume(samples: samples, sampleRate: rate, now: now)
            }
            currentDirection = SpatialDirectionResult(angle: nil, quality: nil, reason: "calibrating")
            if !calibration.calibrating {
                calibrationStartedAt = nil
                invalidateAnalysis()
            }
            let status = calibration.calibrating ? "Keep a steady sound in front of the phone…" :
                (calibration.zero != nil ? "Front calibrated. Listening for sounds…" : "Calibration failed. Try a clear, steady sound in front of the phone.")
            recordSpatialDiagnostics(calibration.lastResult, capturedEnd: capturedEnd, now: now)
            publish(status: status)
            return
        }
        // A short rolling window reduces single-buffer flicker. Classified
        // alerts still use their own exact audio window in receive(_:...).
        let directionSampleCount = rate * 4 * 3 / 10
        directionSamples.append(contentsOf: samples)
        if directionSamples.count > directionSampleCount {
            directionSamples.removeFirst(directionSamples.count - directionSampleCount)
        }
        let measured = directionSamples.count == directionSampleCount
            ? SpatialDirection.estimate(samples: directionSamples, sampleRate: rate, zero: calibration.zero ?? 0)
            : SpatialDirectionResult(angle: nil, quality: nil, reason: "warming_up")
        currentDirection = calibration.zero != nil ? measured
            : SpatialDirectionResult(angle: nil, quality: nil, reason: "not_calibrated")
        recordSpatialDiagnostics(measured, capturedEnd: capturedEnd, now: now)
        let status = calibration.failed
            ? "Calibration failed. Keep one clear, continuous sound in front and try again."
            : calibration.zero == nil ? "Listening. Calibrate the front to locate sounds." : "Listening on iPhone…"
        publish(status: status)
        let startFrame = analysisFrame
        guard ring.append(samples: samples, sampleRate: rate, startFrame: startFrame, endUptime: capturedEnd) else {
            throw ListenerError.message("Could not prepare audio for sound recognition.")
        }
        analysisFrame += Int64(frames)
        submitLatestAnalysis(rate: rate)
    }

    private func submitLatestAnalysis(rate: Int) {
        guard running, !analysisBusy, !calibration.calibrating,
              let bounds = windowSchedule.take(availableFrames: analysisFrame, sampleRate: rate),
              let window = ring.window(startFrame: bounds.start, frameCount: bounds.count),
              ProcessInfo.processInfo.systemUptime < window.endUptime + 0.75 else { return }
        let generation = analysisGeneration
        analysisBusy = true
        analysisStartedAt = ProcessInfo.processInfo.systemUptime
        Self.inferenceQueue.async { [self] in
            let started = ProcessInfo.processInfo.systemUptime
            let result: Result<[Double], Error>
            do {
                guard let classifier else { throw ListenerError.message("The sound model is unavailable. Restart listening.") }
                let waveform = try YAMNetClassifier.waveform(spatial: window.samples, sampleRate: rate)
                result = .success(try classifier.predict(waveform: waveform))
            } catch { result = .failure(error) }
            let elapsed = (ProcessInfo.processInfo.systemUptime - started) * 1000
            queue.async { [self] in
                analysisBusy = false
                guard running else { return }
                if analysisGeneration == generation {
                    switch result {
                    case .success(let scores):
                        inferenceCount += 1
                        lastInferenceMilliseconds = elapsed
                        receive(scores, window: window, rate: rate)
                    case .failure(let error):
                        stopOnQueue("Could not recognize the audio: " + error.localizedDescription)
                        return
                    }
                }
                // The same queue owns rate changes and generation invalidation.
                if let sampleRate { submitLatestAnalysis(rate: sampleRate) }
            }
        }
    }

    private func receive(_ result: [Double], window: AlignedSpatialSamples, rate: Int) {
        let expiry = window.endUptime + 0.75
        guard ProcessInfo.processInfo.systemUptime < expiry else { selector.reset(); return }
        var power = 0.0
        for index in stride(from: 0, to: window.samples.count, by: 4) {
            let value = Double(window.samples[index])
            power += value * value
        }
        let rms = sqrt(power / Double(window.samples.count / 4))
        let scores = rms >= SpatialDirection.minimumRMS ? result : [Double](repeating: 0, count: YAMNetClassifier.classCount)
        guard let candidate = selector.select(scores: scores, at: window.endUptime) else { return }
        let direction = calibration.zero.map { SpatialDirection.estimate(samples: window.samples, sampleRate: rate, zero: $0) }
            ?? SpatialDirectionResult(angle: nil, quality: nil, reason: "not_calibrated")
        let alert = SoundEventDetection(event: candidate.event, score: candidate.score,
                                        angle: direction.angle, quality: direction.quality, expiresAt: expiry,
                                        shouldNotify: candidate.shouldNotify)
        let name = SoundCatalog.forEvent(candidate.event)?.title ?? "Sound"
        publish(status: "Sound detected: " + name, alert: alert)
    }

    private func invalidateAnalysis() {
        analysisGeneration = UUID()
        analysisFrame = 0
        windowSchedule = YAMNetWindowSchedule()
        ring.reset()
        selector.reset()
    }

    private func resetForCaptureGap() {
        pendingSamples.removeAll(keepingCapacity: true)
        pendingPTS = nil
        nextExpectedPTS = nil
        calibration.reset()
        calibrationStartedAt = nil
        directionSamples.removeAll(keepingCapacity: true)
        currentDirection = SpatialDirectionResult(angle: nil, quality: nil, reason: "audio_gap")
        invalidateAnalysis()
    }

    private func publish(status: String, alert: SoundEventDetection? = nil) {
        onEvent(.update(LocalAudioUpdate(angle: currentDirection.angle, quality: currentDirection.quality,
                                        calibrated: calibration.zero != nil, calibrating: calibration.calibrating,
                                        calibrationFailed: calibration.failed,
                                        level: currentLevel, status: status, alert: alert, expiresAt: currentExpiry)))
    }

    /// Latest numeric health snapshot only. No audio, speech, event categories,
    /// network data or Bluetooth identifiers; at most one periodic write per second,
    /// plus a terminal snapshot that marks capture stopped.
    private func recordSpatialDiagnostics(_ result: SpatialDirectionResult?, capturedEnd: TimeInterval, now: TimeInterval) {
        diagnosticWindows += 1
        if result?.angle != nil { diagnosticValidWindows += 1 }
        diagnosticPeakQuality = max(diagnosticPeakQuality, result?.metrics?.quality ?? 0)
        let calibrationFinished = !calibration.calibrating && lastDiagnosticSnapshot["calibrating"] as? Bool == true
        guard now - lastDiagnosticWrite >= 1 || calibrationFinished else { return }
        lastDiagnosticWrite = now
        var snapshot: [String: Any] = [
            "capturing": running, "sampledAt": Date().timeIntervalSince1970,
            "classifier": "YAMNet", "classifierClasses": YAMNetClassifier.classCount,
            "inferenceCount": inferenceCount, "lastInferenceMs": lastInferenceMilliseconds,
            "calibrated": calibration.zero != nil, "calibrating": calibration.calibrating,
            "calibrationFailed": calibration.failed, "windows": diagnosticWindows,
            "validDirectionWindows": diagnosticValidWindows, "peakQuality": diagnosticPeakQuality,
            "calibrationAttemptSeconds": calibration.attemptedDuration,
            "calibrationCandidateWindows": calibration.candidateWindows,
            "calibrationAcceptedWindows": calibration.acceptedWindows,
            "calibrationBestQuality": calibration.bestQuality,
            "calibrationBufferedSeconds": calibration.bufferedDuration,
            "reason": result?.reason ?? "waiting_for_audio", "inputLevel": currentLevel,
            "audioAgeMs": max(0, now - capturedEnd) * 1000
        ]
        if let last = calibration.lastResult { snapshot["calibrationReason"] = last.reason }
        if let rejection = calibration.lastRejectionReason { snapshot["calibrationRejectionReason"] = rejection }
        if let angle = result?.angle { snapshot["rawAngle"] = angle }
        if let metrics = result?.metrics {
            snapshot["rms"] = metrics.rms
            snapshot["coherence"] = metrics.coherence
            snapshot["horizontalFraction"] = metrics.horizontalFraction
            snapshot["stability"] = metrics.stability
            snapshot["quality"] = metrics.quality
            snapshot["directionalRMS"] = metrics.directionalRMS
        }
        lastDiagnosticSnapshot = snapshot
        writeSpatialDiagnostics(snapshot)
    }

    private func writeSpatialDiagnostics(_ snapshot: [String: Any]) {
        guard let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
              let data = try? JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys]) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: directory.appendingPathComponent("fortwatch-spatial-status.json"), options: .atomic)
    }
}
