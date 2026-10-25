import AVFoundation
import Foundation

enum CaptureEvent {
    case started
    case response(BridgeResponse, expiresAt: TimeInterval)
    case waiting(String)
    case stopped(String)
}

/// All capture, buffering and request state belongs to `queue`. Nothing is stored on disk.
final class SpatialCapture: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, URLSessionTaskDelegate {
    // AVAudioSession is a singleton. Old stop and new start must share ordering even
    // when the user rapidly restarts and each run owns a different capture object.
    private static let lifecycleQueue = DispatchQueue(label: "dev.fortwatch.spatial.capture", qos: .userInitiated)
    private let queue = SpatialCapture.lifecycleQueue
    private let captureSession = AVCaptureSession()
    private let configuration: BridgeConfiguration
    private let onEvent: (CaptureEvent) -> Void
    private let streamID = UUID().uuidString
    private var sequence = 0
    private var running = false
    private var audioActivated = false
    private var requestInFlight = false
    private var hasReceivedResponse = false
    private var calibrationPending = false
    private var pendingSamples: [Float] = []
    private var pendingPTS: Double?
    private var sampleRate: Int?
    private var nextExpectedPTS: Double?
    private var request: URLSessionDataTask?
    private var network: URLSession?
    private var observers: [NSObjectProtocol] = []
    private var lastSampleTime = ProcessInfo.processInfo.systemUptime
    private var watchdog: DispatchSourceTimer?

    init(configuration: BridgeConfiguration, onEvent: @escaping (CaptureEvent) -> Void) {
        self.configuration = configuration
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

                let settings = URLSessionConfiguration.ephemeral
                settings.timeoutIntervalForRequest = 1.5
                settings.timeoutIntervalForResource = 1.5
                settings.urlCache = nil
                settings.httpCookieStorage = nil
                settings.httpShouldSetCookies = false
                settings.waitsForConnectivity = false
                network = URLSession(configuration: settings, delegate: self, delegateQueue: nil)

                running = true
                lastSampleTime = ProcessInfo.processInfo.systemUptime
                captureSession.startRunning()
                guard captureSession.isRunning else { throw ListenerError.message("No se pudo iniciar el micrófono.") }
                observeInterruptions()
                beginWatchdog()
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
        // Support is evaluated with the input already attached, as in Apple's FOA sample.
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
            calibrationPending = true
        }
    }

    func stop(message: String = "Captura detenida.") {
        queue.async { [self] in stopOnQueue(message) }
    }

    private func stopOnQueue(_ message: String) {
        running = false
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        watchdog?.cancel()
        watchdog = nil
        request?.cancel()
        request = nil
        network?.invalidateAndCancel()
        network = nil
        requestInFlight = false
        pendingSamples.removeAll(keepingCapacity: false)
        pendingPTS = nil
        if captureSession.isRunning { captureSession.stopRunning() }
        if audioActivated {
            try? AVAudioSession.sharedInstance().setActive(false)
            audioActivated = false
        }
        onEvent(.stopped(message))
    }

    private func observeInterruptions() {
        let center = NotificationCenter.default
        for name in [AVAudioSession.interruptionNotification, AVAudioSession.routeChangeNotification,
                     AVCaptureSession.wasInterruptedNotification, AVCaptureSession.runtimeErrorNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
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
            if ProcessInfo.processInfo.systemUptime - self.lastSampleTime > 3 {
                self.stopOnQueue("El micrófono dejó de enviar audio. Volvé a iniciar la captura.")
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
            lastSampleTime = ProcessInfo.processInfo.systemUptime
            // A dropped capture buffer must not be joined to older samples as if contiguous.
            if let expected = nextExpectedPTS, abs(decoded.pts - expected) > 2.0 / Double(decoded.rate) {
                pendingSamples.removeAll(keepingCapacity: true)
                pendingPTS = nil
                if sequence > 0 { sequence += 1 }
            }
            nextExpectedPTS = decoded.pts + Double(decoded.samples.count / 4) / Double(decoded.rate)
            if pendingPTS == nil { pendingPTS = decoded.pts }
            pendingSamples.append(contentsOf: decoded.samples)
            let chunkFrames = decoded.rate / 10
            let chunkSamples = chunkFrames * 4
            while pendingSamples.count >= chunkSamples {
                guard let pts = pendingPTS else { break }
                let samples = Array(pendingSamples.prefix(chunkSamples))
                pendingSamples.removeFirst(chunkSamples)
                pendingPTS = pts + Double(chunkFrames) / Double(decoded.rate)
                let currentSequence = sequence
                sequence += 1
                // Drop instead of queueing old audio while a request is outstanding.
                guard !requestInFlight else { continue }
                let packet = try AudioPacket(session: streamID, sequence: currentSequence,
                                             sampleRate: decoded.rate, pts: pts, samples: samples,
                                             calibrate: calibrationPending)
                calibrationPending = false
                try send(packet)
            }
        } catch {
            stopOnQueue(error.localizedDescription)
        }
    }

    private func send(_ packet: AudioPacket) throws {
        guard let network else { return }
        var urlRequest = URLRequest(url: configuration.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer " + configuration.token, forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONEncoder().encode(packet)
        urlRequest.timeoutInterval = 1.5
        requestInFlight = true
        let requestStarted = ProcessInfo.processInfo.systemUptime
        let expiresAt = requestStarted + 0.75
        request = network.dataTask(with: urlRequest) { [weak self] data, response, error in
            guard let self else { return }
            self.queue.async { [self] in
                guard self.running else { return }
                self.requestInFlight = false
                self.request = nil
                if let error {
                    if !self.hasReceivedResponse {
                        self.stopOnQueue("No se pudo conectar a la Mac. Permití la red local, revisá la dirección y volvé a iniciar: " + error.localizedDescription)
                        return
                    }
                    self.onEvent(.waiting("No llega audio a la Mac. Revisá la red y el receptor: " + error.localizedDescription))
                    return
                }
                guard let http = response as? HTTPURLResponse, let data, data.count <= 16_384 else {
                    self.stopOnQueue("La Mac envió una respuesta inválida.")
                    return
                }
                guard http.statusCode == 200 else {
                    let message: String
                    switch http.statusCode {
                    case 401: message = "El código de conexión no coincide. Copialo otra vez desde la Mac."
                    case 409: message = "La sesión de audio perdió continuidad o hay otro teléfono conectado. Detené la otra captura y volvé a iniciar."
                    default: message = "La Mac rechazó el audio (\(http.statusCode)). Revisá que ambos usen la misma versión."
                    }
                    self.stopOnQueue(message)
                    return
                }
                guard let result = try? JSONDecoder().decode(BridgeResponse.self, from: data), result.accepted else {
                    self.stopOnQueue("La Mac no pudo aceptar este audio.")
                    return
                }
                self.hasReceivedResponse = true
                // An old successful HTTP response must not revive an obsolete direction.
                guard ProcessInfo.processInfo.systemUptime < expiresAt else {
                    self.onEvent(.waiting("La red está retrasada. La dirección no está disponible."))
                    return
                }
                self.onEvent(.response(result, expiresAt: expiresAt))
            }
        }
        request?.resume()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Never forward microphone audio or the pairing token to a redirected address.
        completionHandler(nil)
    }
}
