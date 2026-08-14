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
}
