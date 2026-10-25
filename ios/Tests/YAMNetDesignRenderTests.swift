#if FORTWATCH_RENDER_CATALOG
import SwiftUI
import XCTest
@testable import FortWatchListener

/// Opt-in render artifacts from production SwiftUI views. These are explicitly
/// simulated UI states, not microphone detections or a physical screen capture.
final class YAMNetDesignRenderTests: XCTestCase {
    @MainActor
    func testExportNativeCatalogStates() throws {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("catalog-design-renders")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let scenarios = ["y012", "y076", "y132", "y282", "y321", "y382", "catalog-long", "catalog-recent", "catalog-silence", "catalog-unknown"]
        for scenario in scenarios {
            let content = ListenerDesignPreview(scenario: scenario).snapshot
                .environment(\.colorScheme, .dark)
                .frame(width: 393, height: 852)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.uiImage)
            let data = try XCTUnwrap(image.pngData())
            try data.write(to: directory.appendingPathComponent(scenario + ".png"))
        }
        print("CATALOG DESIGN RENDERS: " + directory.path)
    }

    @MainActor
    func testExportStaticLibrarySamplesAndLargestTextSize() throws {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("catalog-design-renders")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let cases: [(name: String, events: [String], typeSize: DynamicTypeSize, height: CGFloat)] = [
            ("library-three-simulated-samples", ["Y076", "Y283", "Y081"], .large, 1200),
            ("library-long-name-largest-text", ["Y081"], .accessibility5, 1800)
        ]
        for sample in cases {
            let content = SoundLibraryDesignPreview(events: sample.events, typeSize: sample.typeSize)
                .environment(\.colorScheme, .dark)
                .frame(width: 393, height: sample.height)
            let renderer = ImageRenderer(content: content)
            renderer.proposedSize = ProposedViewSize(width: 393, height: sample.height)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.uiImage)
            let data = try XCTUnwrap(image.pngData())
            try data.write(to: directory.appendingPathComponent(sample.name + ".png"))
        }
        print("STATIC LIBRARY SAMPLE RENDERS: " + directory.path)
    }
}
#endif
