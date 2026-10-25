import Foundation

/// Compile beside the real production catalog/selector; no copied policy logic.
private struct ReplayInput: Decodable {
    let scoreCount: Int
    let scoreFile: String
    let labels: [String]
    let clips: [Clip]
    struct Clip: Decodable {
        let filename: String
        let datasetCategory: String
        let targetIndices: [Int]
        let targetNames: [String]
        let windows: [Window]
    }
    struct Window: Decodable {
        let capturedEndSeconds: Double
        let modelEndSeconds: Double
        let rms: Double
        let scoreByteOffset: Int
    }
}
private struct LabelScore: Codable {
    let index: Int
    let name: String
    let score: Double
}
private struct Selected: Codable {
    let event: String
    let index: Int
    let name: String
    let hapticEvent: String
    let score: Double
    let shouldNotify: Bool
}
private struct WindowResult: Codable {
    let capturedEndSeconds: Double
    let modelEndSeconds: Double
    let rms: Double
    let silenceGated: Bool
    let rawTopFive: [LabelScore]
    let targetScores: [LabelScore]
    let selected: Selected?
}
private struct ClipResult: Codable {
    let filename: String
    let datasetCategory: String
    let targetNames: [String]
    let targetLabelExists: Bool
    let targetSpecificAlertProduced: Bool
    let targetSpecificVisualProduced: Bool
    let selectedNames: [String]
    let notifiedNames: [String]
    let targetPeakScores: [LabelScore]
    let windows: [WindowResult]
}
private struct ReplayResult: Codable {
    let method: String
    let limitations: [String]
    let clips: [ClipResult]
}

@main
private enum ReplaySelector {
    static func main() throws {
        guard (3...4).contains(CommandLine.arguments.count) else {
            throw NSError(domain: "Replay", code: 1, userInfo: [NSLocalizedDescriptionKey: "Usage: replay-selector replay-input.json results.json [selector-description]"])
        }
        let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let input = try JSONDecoder().decode(ReplayInput.self, from: Data(contentsOf: inputURL))
        let data = try Data(contentsOf: inputURL.deletingLastPathComponent().appendingPathComponent(input.scoreFile))
        guard input.scoreCount == SoundCatalog.all.count,
              input.labels == SoundCatalog.all.map(\.name) else {
            throw NSError(domain: "Replay", code: 2, userInfo: [NSLocalizedDescriptionKey: "Model scores and production catalog do not agree"])
        }
        var clips: [ClipResult] = []
        for clip in input.clips {
            var selector = YAMNetEventSelector()
            var windows: [WindowResult] = []
            var lastEnd = -Double.infinity
            for window in clip.windows {
                guard window.capturedEndSeconds > lastEnd,
                      window.scoreByteOffset >= 0,
                      window.scoreByteOffset + input.scoreCount * 4 <= data.count else {
                    throw NSError(domain: "Replay", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid score bounds or window order"])
                }
                lastEnd = window.capturedEndSeconds
                let raw: [Double] = data.withUnsafeBytes { bytes in
                    (0..<input.scoreCount).map { index in
                        let bits = bytes.loadUnaligned(fromByteOffset: window.scoreByteOffset + index * 4, as: UInt32.self)
                        return Double(Float(bitPattern: UInt32(littleEndian: bits)))
                    }
                }
                guard raw.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
                    throw NSError(domain: "Replay", code: 4, userInfo: [NSLocalizedDescriptionKey: "Nonfinite score trace"])
                }
                let gated = window.rms < SpatialDirection.minimumRMS
                let scores = gated ? [Double](repeating: 0, count: input.scoreCount) : raw
                let candidate = selector.select(scores: scores, at: window.capturedEndSeconds)
                let selected: Selected?
                if let candidate, let entry = SoundCatalog.forEvent(candidate.event) {
                    selected = Selected(event: entry.event, index: entry.index, name: entry.name,
                                        hapticEvent: entry.hapticEvent, score: candidate.score,
                                        shouldNotify: candidate.shouldNotify)
                } else { selected = nil }
                let top = raw.indices.sorted {
                    raw[$0] == raw[$1] ? $0 < $1 : raw[$0] > raw[$1]
                }.prefix(5).map { LabelScore(index: $0, name: input.labels[$0], score: raw[$0]) }
                let targets = clip.targetIndices.map { LabelScore(index: $0, name: input.labels[$0], score: raw[$0]) }
                windows.append(WindowResult(capturedEndSeconds: window.capturedEndSeconds,
                                            modelEndSeconds: window.modelEndSeconds, rms: window.rms,
                                            silenceGated: gated, rawTopFive: top, targetScores: targets, selected: selected))
            }
            let selectedNames = Array(Set(windows.compactMap { $0.selected?.name })).sorted()
            let notifiedNames = Array(Set(windows.compactMap { window -> String? in
                guard let selected = window.selected, selected.shouldNotify else { return nil }
                return selected.name
            })).sorted()
            let targetPeaks = clip.targetIndices.map { index in
                LabelScore(index: index, name: input.labels[index],
                           score: windows.flatMap(\.targetScores).filter { $0.index == index }.map(\.score).max() ?? 0)
            }
            let detected = windows.contains { result in
                result.selected.map { clip.targetIndices.contains($0.index) } ?? false
            }
            let notified = windows.contains { result in
                result.selected.map { $0.shouldNotify && clip.targetIndices.contains($0.index) } ?? false
            }
            clips.append(ClipResult(filename: clip.filename, datasetCategory: clip.datasetCategory,
                                    targetNames: clip.targetNames, targetLabelExists: !clip.targetIndices.isEmpty,
                                    targetSpecificAlertProduced: notified, targetSpecificVisualProduced: detected,
                                    selectedNames: selectedNames, notifiedNames: notifiedNames,
                                    targetPeakScores: targetPeaks, windows: windows))
            print("\(clip.filename) [\(clip.datasetCategory)]: visual=\(selectedNames.joined(separator: "; ")) | notify=\(notifiedNames.joined(separator: "; ")) | target visual=\(detected) notify=\(notified)")
        }
        let selectorDescription = CommandLine.arguments.count == 4 ? CommandLine.arguments[3]
            : "Actual production YAMNetEventSelector"
        let result = ReplayResult(
            method: selectorDescription + "; compiled with production SoundCatalog, SoundEvents and SpatialDirection. Scores unpacked losslessly from Float32. Native capture-window end times drive history/cooldown; same RMS gate as SpatialCapture.receive. Fresh selector per five-second public clip.",
            limitations: ["No model inference, live capture, resampler, BLE, direction or live TTL tested here.",
                          "Twenty-six positive public clips are not a representative accuracy or false-positive-rate study.",
                          "A selected label absent from declared targetNames is not automatically a false alert; related labels and incidental sounds require review."],
            clips: clips)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(result).write(to: URL(fileURLWithPath: CommandLine.arguments[2]), options: .atomic)
    }
}
