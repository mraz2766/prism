import XCTest
@testable import Prism

final class PopoverPresentationStateTests: XCTestCase {
    func testRepeatedToggleIsIgnoredWhileOpeningAndClosing() {
        var state = PopoverPresentationState.closed

        XCTAssertEqual(state.requestToggle(), .open)
        XCTAssertEqual(state, .opening)
        XCTAssertNil(state.requestToggle())
        state.didShow()
        XCTAssertEqual(state, .open)

        XCTAssertEqual(state.requestToggle(), .close)
        XCTAssertEqual(state, .closing)
        XCTAssertNil(state.requestToggle())
        state.didClose()
        XCTAssertEqual(state, .closed)
    }

    func testExternalCloseIsIdempotent() {
        var state = PopoverPresentationState.closed

        XCTAssertNil(state.requestClose())
        _ = state.requestToggle()
        state.didShow()
        XCTAssertEqual(state.requestClose(), .close)
        XCTAssertNil(state.requestClose())
        state.willClose()
        state.didClose()
        state.didClose()
        XCTAssertEqual(state, .closed)
    }

    func testLateDidShowCannotReopenClosingPopover() {
        var state = PopoverPresentationState.closed

        _ = state.requestToggle()
        state.willClose()
        state.didShow()
        XCTAssertEqual(state, .closing)
        state.didClose()
        XCTAssertEqual(state, .closed)
    }

    func testStatusItemAndOutsidePointerHaveDistinctEffects() {
        var state = PopoverPresentationState.closed

        XCTAssertEqual(state.requestPointerDown(on: .statusItem), .open)
        state.didShow()
        XCTAssertEqual(state.requestPointerDown(on: .statusItem), .close)
        state.didClose()
        XCTAssertNil(state.requestPointerDown(on: .outside))
    }

    func testDismissHitTesterKeepsStatusItemClickOutOfOutsidePath() {
        let frame = NSRect(x: 100, y: 900, width: 80, height: 24)

        XCTAssertEqual(
            PopoverDismissHitTester.target(screenPoint: NSPoint(x: 140, y: 912), statusItemFrame: frame),
            .statusItem
        )
        XCTAssertEqual(
            PopoverDismissHitTester.target(screenPoint: NSPoint(x: 40, y: 700), statusItemFrame: frame),
            .outside
        )
    }

    func testRapidOddNumberOfSettledStatusItemClicksEndsOpen() {
        var state = PopoverPresentationState.closed

        for _ in 0..<5 {
            let action = state.requestPointerDown(on: .statusItem)
            switch action {
            case .open:
                state.didShow()
            case .close:
                state.didClose()
            case nil:
                XCTFail("A settled status-item click must produce exactly one action")
            }
        }

        XCTAssertEqual(state, .open)
    }
}
