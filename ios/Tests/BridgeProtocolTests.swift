import AVFoundation
import XCTest
@testable import FortWatchListener

/// Synthetic buffers verify the transport contract, not microphone accuracy.
final class BridgeProtocolTests: XCTestCase {
    private let sessionID = "71F92452-352D-4BA1-A79B-8514FE4EBB32"
    private func spatialFormat(_ commonFormat: AVAudioCommonFormat, interleaved: Bool) throws -> AVAudioFormat {
        let layout = try XCTUnwrap(AVAudioChannelLayout(layoutTag: SpatialPCM.layoutTag))
        return AVAudioFormat(commonFormat: commonFormat, sampleRate: 48000, interleaved: interleaved, channelLayout: layout)
    }

    func testPrivateEndpointsAndDefaultPort() throws {
        for address in ["192.168.1.20", "10.0.0.2", "172.16.2.3", "172.31.255.1", "My-Mac.local"] {
            let configuration = try BridgeConfiguration(address: address, token: "test-token")
            XCTAssertEqual(configuration.endpoint.path, "/audio")
            XCTAssertEqual(configuration.endpoint.port, 8766)
        }
        let configuration = try BridgeConfiguration(address: "http://192.168.1.20:9000/", token: "test-token")
        XCTAssertEqual(configuration.endpoint.port, 9000)
    }

    func testRejectsPublicURLsCredentialsAndAmbiguousAddresses() {
        for address in ["https://example.com", "8.8.8.8", "172.32.0.1", "172.15.0.1", "127.0.0.1",
                        "192.168.001.20", "256.1.1.1", "file:///tmp/audio", "http://user:pass@my-mac.local",
                        "http://my-mac.local/audio", "http://my-mac.local?dest=other", "http://my-mac.local#frag",
                        "http://my-mac.local:99999", "http://.local", "http://bad_.local"] {
            XCTAssertThrowsError(try BridgeConfiguration(address: address, token: "test-token"), address)
        }
        for token in ["", "bad\ntoken", String(repeating: "a", count: 257)] {
            XCTAssertThrowsError(try BridgeConfiguration(address: "10.0.0.2", token: token))
        }
    }

    func testPacketKeepsWYZXOrderAndLittleEndianSamples() throws {
        let samples: [Float] = [0.25, -0.5, 0.75, -1, 1, 0.5, 0, -0.25]
        let packet = try AudioPacket(session: sessionID, sequence: 4, sampleRate: 48000,
                                     pts: 3.25, samples: samples, calibrate: true)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(packet)) as? [String: Any])
        XCTAssertEqual(json["version"] as? Int, 1)
        XCTAssertEqual(json["layout"] as? String, "ACN_SN3D")
        XCTAssertEqual(json["frames"] as? Int, 2)
        XCTAssertEqual(json["sample_rate"] as? Int, 48000)
        XCTAssertEqual(json["sequence"] as? Int, 4)
        XCTAssertEqual(json["pts"] as? Double, 3.25)
        XCTAssertEqual(json["calibrate_front"] as? Bool, true)
        let data = try XCTUnwrap(Data(base64Encoded: packet.pcm_f32le))
        XCTAssertEqual(data.count, samples.count * 4)
        let decoded = data.withUnsafeBytes { bytes in
            stride(from: 0, to: bytes.count, by: 4).map {
                Float(bitPattern: UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: $0, as: UInt32.self)))
            }
        }
        XCTAssertEqual(decoded, samples)
    }

    func testPacketRejectsNonfiniteOversizedAndInvalidTime() {
        for samples: [Float] in [[], [0, 1, 2], [.nan, 0, 0, 0], [.infinity, 0, 0, 0],
                                 [Float](repeating: 0, count: 48004)] {
            XCTAssertThrowsError(try AudioPacket(session: sessionID, sequence: 0, sampleRate: 48000,
                                                pts: 0, samples: samples, calibrate: false))
        }
        for pts in [Double.nan, .infinity, -1] {
            XCTAssertThrowsError(try AudioPacket(session: sessionID, sequence: 0, sampleRate: 48000,
                                                pts: pts, samples: [0, 0, 0, 0], calibrate: false))
        }
        XCTAssertThrowsError(try AudioPacket(session: "invalid", sequence: 0, sampleRate: 48000,
                                            pts: 0, samples: [0, 0, 0, 0], calibrate: false))
        XCTAssertThrowsError(try AudioPacket(session: sessionID, sequence: 0, sampleRate: 8000,
                                            pts: 0, samples: [0, 0, 0, 0], calibrate: false))
        XCTAssertThrowsError(try AudioPacket(session: sessionID, sequence: 0, sampleRate: 48000,
                                            pts: 0, samples: [9, 0, 0, 0], calibrate: false))
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

    func testDirectionRequiresCalibrationQualityAndFiniteAngle() {
        func response(calibrated: Bool = true, calibrating: Bool = false,
                      angle: Double? = -35, quality: Double? = 0.8) -> BridgeResponse {
            BridgeResponse(accepted: true, calibrated: calibrated, calibrating: calibrating,
                           angle_deg: angle, direction_quality: quality, reason: "ok", wristband_connected: true)
        }
        XCTAssertEqual(response().usableAngle, -35)
        XCTAssertNil(response(calibrated: false).usableAngle)
        XCTAssertNil(response(calibrating: true).usableAngle)
        XCTAssertNil(response(angle: .nan).usableAngle)
        XCTAssertNil(response(angle: 181).usableAngle)
        XCTAssertNil(response(angle: nil).usableAngle)
        XCTAssertNil(response(quality: 0.59).usableAngle)
        XCTAssertNil(response(quality: .infinity).usableAngle)
        XCTAssertNil(response(quality: 1.1).usableAngle)
    }
}
