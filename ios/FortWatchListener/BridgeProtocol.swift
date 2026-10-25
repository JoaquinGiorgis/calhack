import AVFoundation
import Foundation

enum ListenerError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let message): message }
    }
}

struct BridgeConfiguration {
    let endpoint: URL
    let token: String

    init(address: String, token: String) throws {
        let address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var parts = URLComponents(string: address.contains("://") ? address : "http://" + address),
              parts.scheme == "http" || parts.scheme == "https",
              let host = parts.host?.lowercased(), Self.isLocalHost(host),
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/",
              parts.port == nil || (1...65535).contains(parts.port!) else {
            throw ListenerError.message("Ingresá la IP privada o el nombre .local de tu Mac, por ejemplo 192.168.1.20:8766.")
        }
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, token.utf8.count <= 256,
              token.utf8.allSatisfy({ $0 > 32 && $0 < 127 }) else {
            throw ListenerError.message("Pegá el código de conexión que muestra la Mac.")
        }
        parts.port = parts.port ?? 8766
        parts.path = "/audio"
        guard let endpoint = parts.url else { throw ListenerError.message("La dirección de la Mac no es válida.") }
        self.endpoint = endpoint
        self.token = token
    }

    private static func isLocalHost(_ host: String) -> Bool {
        if host.hasSuffix(".local"), host.count > 6 {
            let labels = host.split(separator: ".", omittingEmptySubsequences: false)
            return labels.allSatisfy { label in
                !label.isEmpty && label.count <= 63 && label.first != "-" && label.last != "-" &&
                label.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
            }
        }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        let numbers = parts.compactMap { part -> Int? in
            guard !part.isEmpty, part.allSatisfy(\.isNumber), let value = Int(part),
                  (0...255).contains(value), String(value) == part else { return nil }
            return value
        }
        guard numbers.count == 4 else { return false }
        return numbers[0] == 10 || (numbers[0] == 192 && numbers[1] == 168) ||
            (numbers[0] == 172 && (16...31).contains(numbers[1]))
    }
}

struct AudioPacket: Encodable {
    static let sampleRates: Set<Int> = [16000, 24000, 32000, 44100, 48000, 96000]
    let version = 1
    let session: String
    let sequence: Int
    let sample_rate: Int
    let frames: Int
    let pts: Double
    let layout = "ACN_SN3D"
    let pcm_f32le: String
    let calibrate_front: Bool

    init(session: String, sequence: Int, sampleRate: Int, pts: Double,
         samples: [Float], calibrate: Bool) throws {
        guard UUID(uuidString: session) != nil, (0...9_007_199_254_740_991).contains(sequence),
              pts.isFinite, (0...1e12).contains(pts), Self.sampleRates.contains(sampleRate),
              !samples.isEmpty, samples.count.isMultiple(of: 4),
              samples.count / 4 <= sampleRate / 4,
              samples.allSatisfy({ $0.isFinite && abs($0) <= 8 }) else {
            throw ListenerError.message("La captura produjo un bloque de audio inválido.")
        }
        self.session = session
        self.sequence = sequence
        self.sample_rate = sampleRate
        self.frames = samples.count / 4
        self.pts = pts
        self.calibrate_front = calibrate
        var bytes = Data(capacity: samples.count * MemoryLayout<UInt32>.size)
        for sample in samples {
            var bits = sample.bitPattern.littleEndian
            withUnsafeBytes(of: &bits) { bytes.append(contentsOf: $0) }
        }
        self.pcm_f32le = bytes.base64EncodedString()
    }
}

struct BridgeResponse: Decodable {
    let accepted: Bool
    let calibrated: Bool
    let calibrating: Bool
    let angle_deg: Double?
    let direction_quality: Double?
    let reason: String
    let wristband_connected: Bool

    var usableAngle: Double? {
        guard accepted, calibrated, !calibrating,
              let angle = angle_deg, angle.isFinite, (-180...180).contains(angle),
              let quality = direction_quality, quality.isFinite, (0.60...1).contains(quality)
        else { return nil }
        return angle
    }
}

/// Copies the native PCM layout without downmixing. The bridge requires ACN/SN3D W,Y,Z,X.
enum SpatialPCM {
    static let layoutTag = kAudioChannelLayoutTag_HOA_ACN_SN3D | 4

    static func decode(_ sampleBuffer: CMSampleBuffer) throws -> (samples: [Float], rate: Int, pts: Double) {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer),
              let formatDescription = CMAudioFormatDescriptionGetStreamBasicDescription(description),
              formatDescription.pointee.mFormatID == kAudioFormatLinearPCM,
              formatDescription.pointee.mChannelsPerFrame == 4,
              let layout = CMAudioFormatDescriptionGetChannelLayout(description, sizeOut: nil),
              layout.pointee.mChannelLayoutTag == layoutTag else {
            throw ListenerError.message("El iPhone no entregó los cuatro canales espaciales esperados. No se puede estimar dirección con esta entrada.")
        }
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0, frameCount <= 48000 else {
            throw ListenerError.message("El tamaño de la captura no es válido.")
        }
        let format = AVAudioFormat(cmAudioFormatDescription: description)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
            throw ListenerError.message("No se pudo preparar el audio espacial.")
        }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sampleBuffer, at: 0, frameCount: Int32(frameCount),
                                                         into: buffer.mutableAudioBufferList) == noErr else {
            throw ListenerError.message("No se pudo leer el audio del micrófono.")
        }
        let pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        guard pts.isFinite, pts >= 0, format.sampleRate.isFinite,
              format.sampleRate.rounded() == format.sampleRate,
              AudioPacket.sampleRates.contains(Int(format.sampleRate)),
              Double(frameCount) <= format.sampleRate * 0.25 else {
            throw ListenerError.message("El tiempo o la frecuencia del audio no son válidos.")
        }
        return (try interleavedSamples(buffer), Int(format.sampleRate), pts)
    }

    static func interleavedSamples(_ buffer: AVAudioPCMBuffer) throws -> [Float] {
        let frames = Int(buffer.frameLength)
        guard buffer.format.channelCount == 4, frames > 0,
              buffer.format.streamDescription.pointee.mFormatFlags & kAudioFormatFlagIsBigEndian == 0 else {
            throw ListenerError.message("Formato espacial no compatible.")
        }
        let size: Int
        switch buffer.format.commonFormat {
        case .pcmFormatFloat32, .pcmFormatInt32: size = 4
        case .pcmFormatFloat64: size = 8
        case .pcmFormatInt16: size = 2
        default: throw ListenerError.message("Formato PCM no compatible.")
        }
        var samples = [Float](repeating: 0, count: frames * 4)
        var baseChannel = 0
        for audioBuffer in UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList) {
            let channels = Int(audioBuffer.mNumberChannels)
            guard channels > 0, baseChannel + channels <= 4, let data = audioBuffer.mData,
                  Int(audioBuffer.mDataByteSize) >= frames * channels * size else {
                throw ListenerError.message("El bloque de audio está incompleto.")
            }
            for frame in 0..<frames {
                for channel in 0..<channels {
                    let offset = (frame * channels + channel) * size
                    let value: Float
                    switch buffer.format.commonFormat {
                    case .pcmFormatFloat32: value = data.loadUnaligned(fromByteOffset: offset, as: Float.self)
                    case .pcmFormatFloat64: value = Float(data.loadUnaligned(fromByteOffset: offset, as: Double.self))
                    case .pcmFormatInt16: value = Float(data.loadUnaligned(fromByteOffset: offset, as: Int16.self)) / 32768
                    case .pcmFormatInt32: value = Float(data.loadUnaligned(fromByteOffset: offset, as: Int32.self)) / 2147483648
                    default: throw ListenerError.message("Formato PCM no compatible.")
                    }
                    guard value.isFinite else { throw ListenerError.message("Audio con muestras inválidas.") }
                    samples[frame * 4 + baseChannel + channel] = value
                }
            }
            baseChannel += channels
        }
        guard baseChannel == 4 else { throw ListenerError.message("Faltan canales espaciales.") }
        return samples
    }
}
