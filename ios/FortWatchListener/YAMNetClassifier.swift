import AVFoundation
import CoreML
import Foundation

/// The bundled Google YAMNet model includes its complete waveform frontend.
/// No microphone data or inference request leaves this device.
final class YAMNetClassifier {
    static let sampleRate = 16_000
    static let inputFrames = 15_600
    static let hopFrames = 7_680
    static let classCount = 521
    private let model: MLModel

    init(modelURL: URL? = nil) throws {
        guard let url = modelURL ?? Bundle.main.url(forResource: "YAMNet", withExtension: "mlmodelc") else {
            throw ListenerError.message("The sound model is missing. Reinstall FortWatch.")
        }
        let configuration = MLModelConfiguration()
        // CPU has verified Float32 parity. Other compute units require their own
        // numerical and on-phone timing checks before changing this setting.
        configuration.computeUnits = .cpuOnly
        model = try MLModel(contentsOf: url, configuration: configuration)
        guard model.modelDescription.inputDescriptionsByName["waveform"]?.multiArrayConstraint?.shape == [15600],
              model.modelDescription.outputDescriptionsByName["scores"]?.multiArrayConstraint?.shape == [521] else {
            throw ListenerError.message("The installed sound model is incompatible with this app.")
        }
    }

    func predict(waveform: [Float]) throws -> [Double] {
        guard waveform.count == Self.inputFrames, waveform.allSatisfy(\.isFinite) else {
            throw ListenerError.message("Could not prepare the sound recognition window.")
        }
        let input = try MLMultiArray(shape: [NSNumber(value: Self.inputFrames)], dataType: .float32)
        for index in waveform.indices { input[index] = NSNumber(value: waveform[index]) }
        let result = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["waveform": input]))
        guard let output = result.featureValue(for: "scores")?.multiArrayValue,
              output.count == Self.classCount else {
            throw ListenerError.message("The sound model returned an incomplete result.")
        }
        let scores = (0..<output.count).map { output[$0].doubleValue }
        guard scores.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
            throw ListenerError.message("The sound model returned invalid scores.")
        }
        return scores
    }

    /// Resample only W (omnidirectional pressure). Direction retains the exact
    /// original four-channel window, never this mono representation.
    static func waveform(spatial: [Float], sampleRate: Int) throws -> [Float] {
        guard SpatialPCM.sampleRates.contains(sampleRate), spatial.count.isMultiple(of: 4),
              spatial.count / 4 == YAMNetWindowSchedule.windowFrames(at: sampleRate),
              spatial.allSatisfy(\.isFinite) else {
            throw ListenerError.message("The microphone window is incompatible with sound recognition.")
        }
        let mono = stride(from: 0, to: spatial.count, by: 4).map { spatial[$0] }
        if sampleRate == Self.sampleRate { return mono }
        guard let sourceFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(sampleRate), channels: 1, interleaved: false),
              let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(Self.sampleRate), channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: sourceFormat, to: targetFormat),
              let source = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(mono.count)),
              let destination = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: AVAudioFrameCount(Self.inputFrames)),
              let samples = source.floatChannelData?[0] else {
            throw ListenerError.message("Could not resample microphone audio.")
        }
        source.frameLength = AVAudioFrameCount(mono.count)
        mono.withUnsafeBufferPointer { samples.update(from: $0.baseAddress!, count: mono.count) }
        converter.primeMethod = .none
        converter.sampleRateConverterQuality = AVAudioQuality.max.rawValue
        var provided = false
        var error: NSError?
        let status = converter.convert(to: destination, error: &error) { _, inputStatus in
            if provided { inputStatus.pointee = .endOfStream; return nil }
            provided = true
            inputStatus.pointee = .haveData
            return source
        }
        guard status != .error, error == nil, destination.frameLength == Self.inputFrames,
              let converted = destination.floatChannelData?[0] else {
            throw error ?? NSError(domain: "FortWatchAudio", code: 1,
                                   userInfo: [NSLocalizedDescriptionKey: "The resampled audio window is incomplete."])
        }
        return Array(UnsafeBufferPointer(start: converted, count: Self.inputFrames))
    }
}

/// Latest complete 975ms window on a fixed 480ms grid. A busy model skips old
/// windows instead of queuing them and presenting increasingly stale alerts.
struct YAMNetWindowSchedule {
    private var previousStart: Int64 = -1

    static func windowFrames(at rate: Int) -> Int {
        Int((Double(rate) * Double(YAMNetClassifier.inputFrames) / Double(YAMNetClassifier.sampleRate)).rounded())
    }

    mutating func take(availableFrames: Int64, sampleRate: Int) -> (start: Int64, count: Int64)? {
        guard SpatialPCM.sampleRates.contains(sampleRate) else { return nil }
        let count = Int64(Self.windowFrames(at: sampleRate))
        let hop = Int64((Double(sampleRate) * Double(YAMNetClassifier.hopFrames) / Double(YAMNetClassifier.sampleRate)).rounded())
        guard availableFrames >= count else { return nil }
        let start = ((availableFrames - count) / hop) * hop
        guard start > previousStart else { return nil }
        previousStart = start
        return (start, count)
    }
}
