import AVFoundation
import XCTest
@testable import FortWatchListener

/// Synthetic buffers verify spatial PCM decoding, not microphone accuracy.
final class SpatialPCMTests: XCTestCase {
    private func spatialFormat(_ commonFormat: AVAudioCommonFormat, interleaved: Bool) throws -> AVAudioFormat {
        let layout = try XCTUnwrap(AVAudioChannelLayout(layoutTag: SpatialPCM.layoutTag))
        return AVAudioFormat(commonFormat: commonFormat, sampleRate: 48000, interleaved: interleaved, channelLayout: layout)
    }

    func testFloat32PlanarAndInterleavedPreserveChannels() throws {
        for interleaved in [false, true] {
            let format = try spatialFormat(.pcmFormatFloat32, interleaved: interleaved)
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2))
            buffer.frameLength = 2
            var baseChannel = 0
            for audioBuffer in UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList) {
                let pointer = try XCTUnwrap(audioBuffer.mData).assumingMemoryBound(to: Float.self)
                let channels = Int(audioBuffer.mNumberChannels)
                for frame in 0..<2 {
                    for channel in 0..<channels {
                        pointer[frame * channels + channel] = Float(frame * 4 + baseChannel + channel) / 8
                    }
                }
                baseChannel += channels
            }
            XCTAssertEqual(try SpatialPCM.interleavedSamples(buffer), (0..<8).map { Float($0) / 8 })
        }
    }

    func testIntegerPCMIsNormalizedWithoutChangingChannelOrder() throws {
        let format = try spatialFormat(.pcmFormatInt16, interleaved: true)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1))
        buffer.frameLength = 1
        let audio = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        let pointer = try XCTUnwrap(audio[0].mData).assumingMemoryBound(to: Int16.self)
        for (index, value) in [Int16.min, -16384, 0, 16384].enumerated() { pointer[index] = value }
        XCTAssertEqual(try SpatialPCM.interleavedSamples(buffer), [-1, -0.5, 0, 0.5])
    }

    func testCaptureBufferPreservesNativeLayoutTimestampAndSamples() throws {
        let format = try spatialFormat(.pcmFormatFloat32, interleaved: false)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2))
        buffer.frameLength = 2
        for channel in 0..<4 {
            for frame in 0..<2 { buffer.floatChannelData![channel][frame] = Float(channel + frame * 4) / 8 }
        }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 48000),
                                        presentationTimeStamp: CMTime(seconds: 3.25, preferredTimescale: 48000),
                                        decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        XCTAssertEqual(CMSampleBufferCreate(allocator: kCFAllocatorDefault, dataBuffer: nil, dataReady: false,
                                            makeDataReadyCallback: nil, refcon: nil,
                                            formatDescription: format.formatDescription, sampleCount: 2,
                                            sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                                            sampleSizeEntryCount: 0, sampleSizeArray: nil,
                                            sampleBufferOut: &sample), noErr)
        let sampleBuffer = try XCTUnwrap(sample)
        XCTAssertEqual(CMSampleBufferSetDataBufferFromAudioBufferList(sampleBuffer,
                                                                      blockBufferAllocator: kCFAllocatorDefault,
                                                                      blockBufferMemoryAllocator: kCFAllocatorDefault,
                                                                      flags: 0, bufferList: buffer.audioBufferList), noErr)
        XCTAssertEqual(CMSampleBufferSetDataReady(sampleBuffer), noErr)
        let decoded = try SpatialPCM.decode(sampleBuffer)
        XCTAssertEqual(decoded.pts, 3.25)
        XCTAssertEqual(decoded.rate, 48000)
        XCTAssertEqual(decoded.samples, (0..<8).map { Float($0) / 8 })
    }

    func testMonoAndInvalidFloatPCMDoNotMasqueradeAsSpatial() throws {
        let mono = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000,
                                              channels: 1, interleaved: false))
        let monoBuffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: 1))
        monoBuffer.frameLength = 1
        XCTAssertThrowsError(try SpatialPCM.interleavedSamples(monoBuffer))
        let spatial = try spatialFormat(.pcmFormatFloat32, interleaved: false)
        let spatialBuffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: spatial, frameCapacity: 1))
        spatialBuffer.frameLength = 1
        for channel in 0..<4 { spatialBuffer.floatChannelData![channel][0] = channel == 2 ? .nan : 0 }
        XCTAssertThrowsError(try SpatialPCM.interleavedSamples(spatialBuffer))
    }

}
