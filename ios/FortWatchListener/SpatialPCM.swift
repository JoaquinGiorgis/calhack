import AVFoundation
import Foundation

enum ListenerError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let message): message }
    }
}

/// Copies native ACN/SN3D W,Y,Z,X without downmixing the directional channels.
enum SpatialPCM {
    static let sampleRates: Set<Int> = [16000, 24000, 32000, 44100, 48000, 96000]
    static let layoutTag = kAudioChannelLayoutTag_HOA_ACN_SN3D | 4

    static func decode(_ sampleBuffer: CMSampleBuffer) throws -> (samples: [Float], rate: Int, pts: Double) {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer),
              let formatDescription = CMAudioFormatDescriptionGetStreamBasicDescription(description),
              formatDescription.pointee.mFormatID == kAudioFormatLinearPCM,
              formatDescription.pointee.mChannelsPerFrame == 4,
              let layout = CMAudioFormatDescriptionGetChannelLayout(description, sizeOut: nil),
              layout.pointee.mChannelLayoutTag == layoutTag else {
            throw ListenerError.message("The iPhone did not provide the four expected spatial channels. Direction cannot be estimated from this input.")
        }
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0, frameCount <= 48000 else {
            throw ListenerError.message("The capture size is invalid.")
        }
        let format = AVAudioFormat(cmAudioFormatDescription: description)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
            throw ListenerError.message("Could not prepare spatial audio.")
        }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sampleBuffer, at: 0, frameCount: Int32(frameCount),
                                                         into: buffer.mutableAudioBufferList) == noErr else {
            throw ListenerError.message("Could not read microphone audio.")
        }
        let pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        guard pts.isFinite, pts >= 0, format.sampleRate.isFinite,
              format.sampleRate.rounded() == format.sampleRate,
              Self.sampleRates.contains(Int(format.sampleRate)),
              Double(frameCount) <= format.sampleRate * 0.25 else {
            throw ListenerError.message("Audio timing or sample rate is invalid.")
        }
        return (try interleavedSamples(buffer), Int(format.sampleRate), pts)
    }

    static func interleavedSamples(_ buffer: AVAudioPCMBuffer) throws -> [Float] {
        let frames = Int(buffer.frameLength)
        guard buffer.format.channelCount == 4, frames > 0,
              buffer.format.streamDescription.pointee.mFormatFlags & kAudioFormatFlagIsBigEndian == 0 else {
            throw ListenerError.message("Spatial audio format is not supported.")
        }
        let size: Int
        switch buffer.format.commonFormat {
        case .pcmFormatFloat32, .pcmFormatInt32: size = 4
        case .pcmFormatFloat64: size = 8
        case .pcmFormatInt16: size = 2
        default: throw ListenerError.message("PCM audio format is not supported.")
        }
        var samples = [Float](repeating: 0, count: frames * 4)
        var baseChannel = 0
        for audioBuffer in UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList) {
            let channels = Int(audioBuffer.mNumberChannels)
            guard channels > 0, baseChannel + channels <= 4, let data = audioBuffer.mData,
                  Int(audioBuffer.mDataByteSize) >= frames * channels * size else {
                throw ListenerError.message("The audio block is incomplete.")
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
                    default: throw ListenerError.message("PCM audio format is not supported.")
                    }
                    guard value.isFinite else { throw ListenerError.message("Audio contains invalid samples.") }
                    samples[frame * 4 + baseChannel + channel] = value
                }
            }
            baseChannel += channels
        }
        guard baseChannel == 4 else { throw ListenerError.message("Spatial audio channels are missing.") }
        return samples
    }
}
