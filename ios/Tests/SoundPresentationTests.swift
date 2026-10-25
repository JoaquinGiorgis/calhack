import Foundation
import XCTest
@testable import FortWatchListener

final class SoundPresentationTests: XCTestCase {
    func testRecentSoundKeepsIdentityButCannotBorrowNewLiveDirection() {
        let recent = RecentSound(event: "KNOCK", observedAt: Date(timeIntervalSince1970: 100), sent: true)
        let shown = PresentedSound.current(live: SoundDirectionCue(angle: -90, event: nil), recent: recent)
        XCTAssertEqual(shown.event, "KNOCK")
        XCTAssertNil(shown.angle)
        XCTAssertTrue(shown.isRecent)
        XCTAssertEqual(shown.recent, recent)
    }

    func testNewClassifiedSoundReplacesRecentIdentityAndUsesOnlyItsOwnAngle() {
        let recent = RecentSound(event: "ALARM", observedAt: Date(), sent: true)
        let live = SoundDirectionCue(angle: 90, event: "DOG")
        let shown = PresentedSound.current(live: live, recent: recent)
        XCTAssertEqual(shown.event, "DOG")
        XCTAssertEqual(shown.angle, 90)
        XCTAssertFalse(shown.isRecent)
        XCTAssertNil(shown.recent)
        let uncertain = PresentedSound.current(live: SoundDirectionCue(angle: nil, event: "DOG"), recent: recent)
        XCTAssertEqual(uncertain.event, "DOG")
        XCTAssertNil(uncertain.angle)
        XCTAssertFalse(uncertain.isRecent)
    }

    func testGenericLiveDirectionRemainsUnlabelledWithoutRecentDetection() {
        let shown = PresentedSound.current(live: SoundDirectionCue(angle: 40, event: nil), recent: nil)
        XCTAssertNil(shown.event)
        XCTAssertEqual(shown.angle, 40)
        XCTAssertFalse(shown.isRecent)
    }

    func testStoppedCaptureCanRetainReadableHistoryWithoutDirection() {
        let recent = RecentSound(event: "CAR_HORN", observedAt: Date(), sent: false)
        let shown = PresentedSound.current(live: SoundDirectionCue(angle: nil, event: nil), recent: recent)
        XCTAssertEqual(shown.recent?.event, "CAR_HORN")
        XCTAssertFalse(shown.recent?.sent ?? true)
        XCTAssertNil(shown.angle)
        XCTAssertTrue(shown.isRecent)
    }
}
