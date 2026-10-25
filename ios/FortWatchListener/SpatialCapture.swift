import AVFoundation
import Foundation
import SoundAnalysis

enum CaptureEvent {
    case started
    case update(LocalAudioUpdate)
    case stopped(String)
}

private final class ClassificationObserver: NSObject, SNResultsObserving {
    let result: (SNClassificationResult) -> Void
    let failure: (Error) -> Void

    init(result: @escaping (SNClassificationResult) -> Void, failure: @escaping (Error) -> Void) {
        self.result = result
        self.failure = failure
    }

    func request(_ request: SNRequest, didProduce result: SNResult) {
        if let classification = result as? SNClassificationResult { self.result(classification) }
    }

    func request(_ request: SNRequest, didFailWithError error: Error) { failure(error) }
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
    private var audioActivated = false
    private var pendingSamples: [Float] = []
    private var pendingPTS: Double?
    private var sampleRate: Int?
    private var nextExpectedPTS: Double?
    private var observers: [NSObjectProtocol] = []
    private var watchdog: DispatchSourceTimer?
    private var lastSampleTime = ProcessInfo.processInfo.systemUptime
    private var calibration = FrontCalibration()
    private var calibrationStartedAt: TimeInterval?
    private var selector = SoundEventSelector()
    private var ring = SpatialSampleRing()
    private var analysisGeneration = UUID()
    private var analysisFrame: Int64 = 0
    private var analysisBusy = false
    private var analysisStartedAt: TimeInterval = 0
    private var pendingAnalysis: [Float] = []
    private var pendingAnalysisStart: Int64?
    private var pendingAnalysisEnd: TimeInterval = 0
    private var lastResultEndFrame: Int64 = -1
    private var currentLevel = 0
    private var currentDirection = SpatialDirectionResult(angle: nil, quality: nil, reason: "not_calibrated")
    private var currentExpiry: TimeInterval = 0
    // The following three fields belong exclusively to inferenceQueue.
    private var analyzer: SNAudioStreamAnalyzer?
    private var analyzerGeneration: UUID?
    private var analyzerRate: Int?
    private var analysisObserver: ClassificationObserver?

    init(onEvent: @escaping (CaptureEvent) -> Void) {
        self.onEvent = onEvent
        super.init()
    }

    func start() {
        queue.async { [self] in
            do {
                let audioSession = AVAudioSession.sharedInstance()
                captureSession.automaticallyConfiguresApplicationAudioSession = false
                try audioSession.setCategory(.record, mode: .default)
                try audioSession.setActive(true)
                audioActivated = true
                guard let microphone = audioSession.availableInputs?.first(where: { $0.portType == .builtInMic }) else {
                    throw ListenerError.message("No está disponible el micrófono integrado del iPhone.")
                }
                try audioSession.setPreferredInput(microphone)
                try configureCapture()
                // Load Apple's built-in model before capture starts, so cold model
                // startup cannot repeatedly overflow the single inference slot.
                let rate = Int(audioSession.sampleRate)
                guard SpatialPCM.sampleRates.contains(rate) else {
                    throw ListenerError.message("La frecuencia del micrófono no es compatible.")
                }
                let generation = analysisGeneration
                try Self.inferenceQueue.sync { try prepareAnalyzer(rate: rate, generation: generation) }
                running = true
                lastSampleTime = ProcessInfo.processInfo.systemUptime
                captureSession.startRunning()
                guard captureSession.isRunning else { throw ListenerError.message("No se pudo iniciar el micrófono.") }
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
            throw ListenerError.message("No hay una entrada de audio disponible.")
        }
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }
        let input = try AVCaptureDeviceInput(device: device)
        guard captureSession.canAddInput(input) else {
            throw ListenerError.message("No se puede conectar el micrófono a la captura.")
        }
        captureSession.addInput(input)
        // Apple checks support only after attaching the input to the session.
        guard input.isMultichannelAudioModeSupported(.firstOrderAmbisonics) else {
            throw ListenerError.message("Este dispositivo no ofrece captura espacial compatible. Usá un iPhone 16 Pro o posterior con iOS 26.")
        }
        input.multichannelAudioMode = .firstOrderAmbisonics
        if #available(iOS 26.4, *), input.isAudioZoomSupported { input.isAudioZoomEnabled = false }
        let output = AVCaptureAudioDataOutput()
        output.spatialAudioChannelLayoutTag = SpatialPCM.layoutTag
        guard captureSession.canAddOutput(output) else {
            throw ListenerError.message("No se puede acceder al audio espacial.")
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
            let now = ProcessInfo.processInfo.systemUptime
            calibration.start(now: now)
            calibrationStartedAt = now
            currentDirection = SpatialDirectionResult(angle: nil, quality: nil, reason: "calibrating")
            currentExpiry = now + 0.75
            publish(status: "Mantené un sonido frente al teléfono durante un segundo.")
        }
    }

    func stop(message: String = "Escucha detenida.") {
        queue.async { [self] in stopOnQueue(message) }
    }

    private func stopOnQueue(_ message: String) {
        running = false
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        watchdog?.cancel()
        watchdog = nil
        pendingSamples.removeAll(keepingCapacity: false)
        pendingPTS = nil
        calibration.reset()
        invalidateAnalysis()
        Self.inferenceQueue.async { [self] in
            analyzer?.removeAllRequests()
            analyzer = nil
            analysisObserver = nil
            analyzerGeneration = nil
            analyzerRate = nil
        }
        if captureSession.isRunning { captureSession.stopRunning() }
        if audioActivated {
            try? AVAudioSession.sharedInstance().setActive(false)
            audioActivated = false
        }
        onEvent(.stopped(message))
    }

    private func observeInterruptions() {
        for name in [AVAudioSession.interruptionNotification, AVAudioSession.routeChangeNotification,
                     AVCaptureSession.wasInterruptedNotification, AVCaptureSession.runtimeErrorNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                self?.queue.async { [weak self] in
                    guard let self, self.running else { return }
                    self.stopOnQueue("La captura se interrumpió o cambió el micrófono. Volvé a iniciar y calibrar.")
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
                self.stopOnQueue("El micrófono dejó de enviar audio. Volvé a iniciar la escucha.")
            } else if self.analysisBusy && now - self.analysisStartedAt > 3 {
                self.stopOnQueue("El reconocimiento se demoró demasiado. Volvé a iniciar la escucha.")
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
                throw ListenerError.message("La entrada cambió a un micrófono externo. Volvé al micrófono integrado y reiniciá.")
            }
            let decoded = try SpatialPCM.decode(sampleBuffer)
            if let sampleRate, sampleRate != decoded.rate {
                throw ListenerError.message("Cambió la frecuencia del audio. Volvé a iniciar y calibrar.")
            }
            sampleRate = decoded.rate
            let now = ProcessInfo.processInfo.systemUptime
            lastSampleTime = now
            let decodedEndPTS = decoded.pts + Double(decoded.samples.count / 4) / Double(decoded.rate)
            guard let sourceClock = captureSession.synchronizationClock else {
                throw ListenerError.message("No se pudo sincronizar el tiempo del micrófono.")
            }
            let hostClock = CMClockGetHostTimeClock()
            let hostEnd = CMSyncConvertTime(CMTime(seconds: decodedEndPTS, preferredTimescale: CMTimeScale(decoded.rate)),
                                           from: sourceClock, to: hostClock)
            let age = CMTimeGetSeconds(CMTimeSubtract(CMClockGetTime(hostClock), hostEnd))
            guard age.isFinite, age >= -0.05 else {
                throw ListenerError.message("El tiempo del audio no es válido. Volvé a iniciar la escucha.")
            }
            guard age < 0.75 else {
                resetForCaptureGap()
                currentExpiry = now + 0.75
                publish(status: "El audio llegó tarde. Volvé a calibrar el frente.")
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
            let status = calibration.calibrating ? "Mantené un sonido estable frente al teléfono…" :
                (calibration.zero != nil ? "Frente calibrado. Escuchando sonidos…" : "No se pudo calibrar. Probá un sonido claro y estable frente al teléfono.")
            publish(status: status)
            return
        }
        currentDirection = calibration.zero.map { SpatialDirection.estimate(samples: samples, sampleRate: rate, zero: $0) }
            ?? SpatialDirectionResult(angle: nil, quality: nil, reason: "not_calibrated")
        publish(status: calibration.zero == nil ? "Escuchando. Calibrá el frente para ubicar los sonidos." : "Escuchando en el iPhone…")
        if analysisBusy && pendingAnalysis.count + samples.count > rate * 4 / 2 {
            // At most 500ms can wait behind the one inference call. Overflow
            // discards that window instead of letting latency grow without bound.
            invalidateAnalysis()
        }
        let startFrame = analysisFrame
        guard ring.append(samples: samples, sampleRate: rate, startFrame: startFrame, endUptime: capturedEnd) else {
            throw ListenerError.message("No se pudo preparar el audio para reconocer sonidos.")
        }
        analysisFrame += Int64(frames)
        if analysisBusy {
            if pendingAnalysisStart == nil { pendingAnalysisStart = startFrame }
            pendingAnalysis.append(contentsOf: samples)
            pendingAnalysisEnd = capturedEnd
        } else {
            try submitAnalysis(samples, startFrame: startFrame, rate: rate, now: now)
        }
    }

    private func submitAnalysis(_ samples: [Float], startFrame: Int64, rate: Int, now: TimeInterval) throws {
        let frames = samples.count / 4
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(rate), channels: 1, interleaved: false),
              let mono = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let channel = mono.floatChannelData?[0] else {
            throw ListenerError.message("No se pudo preparar el audio para reconocer sonidos.")
        }
        mono.frameLength = AVAudioFrameCount(frames)
        for frame in 0..<frames { channel[frame] = samples[frame * 4] }
        let generation = analysisGeneration
        analysisBusy = true
        analysisStartedAt = now
        Self.inferenceQueue.async { [self] in
            do {
                if analyzerGeneration != generation || analyzerRate != rate { try prepareAnalyzer(rate: rate, generation: generation) }
                analyzer?.analyze(mono, atAudioFramePosition: startFrame)
            } catch {
                queue.async { [self] in
                    if running && analysisGeneration == generation { stopOnQueue(error.localizedDescription) }
                }
            }
            queue.async { [self] in
                analysisBusy = false
                guard running, !calibration.calibrating,
                      let start = pendingAnalysisStart, !pendingAnalysis.isEmpty else { return }
                let now = ProcessInfo.processInfo.systemUptime
                guard now < pendingAnalysisEnd + 0.75 else { invalidateAnalysis(); return }
                let samples = pendingAnalysis
                pendingAnalysis.removeAll(keepingCapacity: true)
                pendingAnalysisStart = nil
                do { try submitAnalysis(samples, startFrame: start, rate: rate, now: now) }
                catch { stopOnQueue(error.localizedDescription) }
            }
        }
    }

    private static func makeRequest() throws -> SNClassifySoundRequest {
        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        let missing = SoundEventSelector().missingClassifications(from: Set(request.knownClassifications))
        guard missing.isEmpty else {
            throw ListenerError.message("El reconocimiento de este iPhone no incluye todos los sonidos necesarios: " + missing.joined(separator: ", "))
        }
        let desired = CMTime(seconds: 1, preferredTimescale: 48000)
        let constraint = request.windowDurationConstraint
        let supported: Bool
        switch constraint {
        case .durationRange(let range): supported = CMTimeRangeContainsTime(range, time: desired)
        case .enumeratedDurations(let durations): supported = durations.contains { CMTimeCompare($0, desired) == 0 }
        @unknown default: supported = false
        }
        guard supported else {
            throw ListenerError.message("El reconocedor no admite ventanas de un segundo en este dispositivo.")
        }
        request.windowDuration = desired
        let actual = CMTimeGetSeconds(request.windowDuration)
        guard actual.isFinite, (0.5...2).contains(actual) else {
            throw ListenerError.message("El reconocedor no ofrece una ventana de audio compatible.")
        }
        request.overlapFactor = 0.5
        return request
    }

    /// Called exclusively on inferenceQueue, including initial model warmup.
    private func prepareAnalyzer(rate: Int, generation: UUID) throws {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(rate), channels: 1, interleaved: false) else {
            throw ListenerError.message("El audio no es compatible con el reconocedor.")
        }
        analyzer?.removeAllRequests()
        let stream = SNAudioStreamAnalyzer(format: format)
        let observer = ClassificationObserver(result: { [weak self] result in
            self?.queue.async { [weak self] in self?.receive(result, generation: generation, rate: rate) }
        }, failure: { [weak self] error in
            self?.queue.async { [weak self] in
                guard let self, self.running, self.analysisGeneration == generation else { return }
                self.stopOnQueue("No se pudo reconocer el audio: " + error.localizedDescription)
            }
        })
        try stream.add(Self.makeRequest(), withObserver: observer)
        analyzer = stream
        analyzerGeneration = generation
        analyzerRate = rate
        analysisObserver = observer
    }

    private func receive(_ result: SNClassificationResult, generation: UUID, rate: Int) {
        guard running, generation == analysisGeneration, !calibration.calibrating,
              result.timeRange.start.isNumeric, result.timeRange.duration.isNumeric else { return }
        let start = CMTimeConvertScale(result.timeRange.start, timescale: CMTimeScale(rate), method: .roundHalfAwayFromZero).value
        let count = CMTimeConvertScale(result.timeRange.duration, timescale: CMTimeScale(rate), method: .roundHalfAwayFromZero).value
        guard start >= 0, count > 0, count <= rate * 2, start <= Int64.max - count,
              start + count > lastResultEndFrame,
              let window = ring.window(startFrame: start, frameCount: count) else { return }
        lastResultEndFrame = start + count
        let expiry = window.endUptime + 0.75
        guard ProcessInfo.processInfo.systemUptime < expiry else { selector.reset(); return }
        var power = 0.0
        for index in stride(from: 0, to: window.samples.count, by: 4) {
            let value = Double(window.samples[index])
            power += value * value
        }
        let rms = sqrt(power / Double(window.samples.count / 4))
        let scores = rms >= SpatialDirection.minimumRMS
            ? Dictionary(result.classifications.map { ($0.identifier, $0.confidence) }, uniquingKeysWith: max)
            : [:]
        guard let candidate = selector.select(scores: scores, at: window.endUptime) else { return }
        let direction = calibration.zero.map { SpatialDirection.estimate(samples: window.samples, sampleRate: rate, zero: $0) }
            ?? SpatialDirectionResult(angle: nil, quality: nil, reason: "not_calibrated")
        let alert = SoundEventDetection(event: candidate.event, score: candidate.score,
                                        angle: direction.angle, quality: direction.quality, expiresAt: expiry)
        publish(status: "Sonido detectado: " + candidate.event, alert: alert)
    }

    private func invalidateAnalysis() {
        analysisGeneration = UUID()
        analysisFrame = 0
        lastResultEndFrame = -1
        ring.reset()
        selector.reset()
        pendingAnalysis.removeAll(keepingCapacity: true)
        pendingAnalysisStart = nil
    }

    private func resetForCaptureGap() {
        pendingSamples.removeAll(keepingCapacity: true)
        pendingPTS = nil
        nextExpectedPTS = nil
        calibration.reset()
        calibrationStartedAt = nil
        currentDirection = SpatialDirectionResult(angle: nil, quality: nil, reason: "audio_gap")
        invalidateAnalysis()
    }

    private func publish(status: String, alert: SoundEventDetection? = nil) {
        onEvent(.update(LocalAudioUpdate(angle: currentDirection.angle, quality: currentDirection.quality,
                                        calibrated: calibration.zero != nil, calibrating: calibration.calibrating,
                                        level: currentLevel, status: status, alert: alert, expiresAt: currentExpiry)))
    }
}
