import XCTest
@testable import Prism

final class PopoverPresentationStateTests: XCTestCase {
    func testSecondToggleDuringOpeningClosesAsSoonAsShowCompletes() {
        var state = PopoverPresentationState.closed

        XCTAssertEqual(state.requestToggle(), .open)
        XCTAssertEqual(state.phase, .opening)
        XCTAssertNil(state.requestToggle())
        XCTAssertFalse(state.wantsVisible)
        XCTAssertEqual(state.didShow(), .close)
        XCTAssertEqual(state.phase, .closing)
        XCTAssertNil(state.didClose())
        XCTAssertEqual(state.phase, .closed)
    }

    func testToggleDuringClosingReopensAfterCloseCompletes() {
        var state = PopoverPresentationState.closed

        XCTAssertEqual(state.requestToggle(), .open)
        XCTAssertNil(state.didShow())
        XCTAssertEqual(state.requestToggle(), .close)
        XCTAssertNil(state.requestToggle())
        XCTAssertTrue(state.wantsVisible)
        XCTAssertEqual(state.didClose(), .open)
        XCTAssertEqual(state.phase, .opening)
        XCTAssertNil(state.didShow())
        XCTAssertEqual(state.phase, .open)
    }

    func testExternalCloseIsIdempotent() {
        var state = PopoverPresentationState.closed

        XCTAssertNil(state.requestClose())
        _ = state.requestToggle()
        XCTAssertNil(state.didShow())
        XCTAssertEqual(state.requestClose(), .close)
        XCTAssertNil(state.requestClose())
        state.willClose()
        XCTAssertNil(state.didClose())
        XCTAssertNil(state.didClose())
        XCTAssertEqual(state.phase, .closed)
    }

    func testOutsideClickDuringOpeningClosesAfterShowCompletes() {
        var state = PopoverPresentationState.closed

        XCTAssertEqual(state.requestPointerDown(on: .statusItem), .open)
        XCTAssertNil(state.requestPointerDown(on: .outside))
        XCTAssertFalse(state.wantsVisible)
        XCTAssertEqual(state.didShow(), .close)
        XCTAssertNil(state.didClose())
        XCTAssertEqual(state.phase, .closed)
    }

    func testLateDidShowCannotReopenClosingPopover() {
        var state = PopoverPresentationState.closed

        _ = state.requestToggle()
        state.willClose()
        XCTAssertNil(state.didShow())
        XCTAssertEqual(state.phase, .closing)
        _ = state.requestClose()
        XCTAssertNil(state.didClose())
        XCTAssertEqual(state.phase, .closed)
    }

    func testStatusItemAndOutsidePointerHaveDistinctEffects() {
        var state = PopoverPresentationState.closed

        XCTAssertEqual(state.requestPointerDown(on: .statusItem), .open)
        XCTAssertNil(state.didShow())
        XCTAssertNil(state.requestPointerDown(on: .popover))
        XCTAssertEqual(state.requestPointerDown(on: .statusItem), .close)
        XCTAssertNil(state.didClose())
        XCTAssertNil(state.requestPointerDown(on: .outside))
    }

    func testDismissHitTesterKeepsStatusItemClickOutOfOutsidePath() {
        let statusFrame = NSRect(x: 100, y: 900, width: 80, height: 24)
        let popoverFrame = NSRect(x: 80, y: 440, width: 360, height: 450)

        XCTAssertEqual(
            PopoverDismissHitTester.target(
                screenPoint: NSPoint(x: 140, y: 912),
                statusItemFrame: statusFrame,
                popoverFrame: popoverFrame
            ),
            .statusItem
        )
        XCTAssertEqual(
            PopoverDismissHitTester.target(
                screenPoint: NSPoint(x: 140, y: 700),
                statusItemFrame: statusFrame,
                popoverFrame: popoverFrame
            ),
            .popover
        )
        XCTAssertEqual(
            PopoverDismissHitTester.target(
                screenPoint: NSPoint(x: 40, y: 700),
                statusItemFrame: statusFrame,
                popoverFrame: popoverFrame
            ),
            .outside
        )
    }

    func testFiveRapidClicksDuringOpeningPreserveOddClickParity() {
        var state = PopoverPresentationState.closed

        XCTAssertEqual(state.requestPointerDown(on: .statusItem), .open)
        for _ in 0..<4 {
            XCTAssertNil(state.requestPointerDown(on: .statusItem))
        }

        XCTAssertTrue(state.wantsVisible)
        XCTAssertNil(state.didShow())
        XCTAssertEqual(state.phase, .open)
    }

    func testFourRapidClicksDuringOpeningPreserveEvenClickParity() {
        var state = PopoverPresentationState.closed

        XCTAssertEqual(state.requestPointerDown(on: .statusItem), .open)
        for _ in 0..<3 {
            XCTAssertNil(state.requestPointerDown(on: .statusItem))
        }

        XCTAssertFalse(state.wantsVisible)
        XCTAssertEqual(state.didShow(), .close)
        XCTAssertNil(state.didClose())
        XCTAssertEqual(state.phase, .closed)
    }
}
