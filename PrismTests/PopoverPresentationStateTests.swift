import XCTest
@testable import Prism

final class PopoverPresentationStateTests: XCTestCase {
    func testFirstClickOpensAndSecondClickClosesImmediately() {
        var state = PopoverPresentationState.closed

        XCTAssertEqual(state.requestToggle(), .open)
        XCTAssertEqual(state.requestToggle(), .close)
        XCTAssertFalse(state.isPresented)
    }

    func testExternalCloseIsIdempotent() {
        var state = PopoverPresentationState.closed

        XCTAssertNil(state.requestClose())
        _ = state.requestToggle()
        XCTAssertEqual(state.requestClose(), .close)
        XCTAssertNil(state.requestClose())
        state.didClose()
        state.didClose()
        XCTAssertFalse(state.isPresented)
    }

    func testOutsideClickClosesImmediately() {
        var state = PopoverPresentationState.closed

        XCTAssertEqual(state.requestPointerDown(on: .statusItem), .open)
        XCTAssertEqual(state.requestPointerDown(on: .outside), .close)
        XCTAssertFalse(state.isPresented)
    }

    func testStatusItemAndOutsidePointerHaveDistinctEffects() {
        var state = PopoverPresentationState.closed

        XCTAssertEqual(state.requestPointerDown(on: .statusItem), .open)
        XCTAssertNil(state.requestPointerDown(on: .popover))
        XCTAssertEqual(state.requestPointerDown(on: .statusItem), .close)
        XCTAssertNil(state.requestPointerDown(on: .outside))
    }

    func testFiveRapidClicksEndOpen() {
        var state = PopoverPresentationState.closed

        let actions = (0..<5).map { _ in state.requestPointerDown(on: .statusItem) }

        XCTAssertEqual(actions, [.open, .close, .open, .close, .open])
        XCTAssertTrue(state.isPresented)
    }

    func testFourRapidClicksEndClosed() {
        var state = PopoverPresentationState.closed

        let actions = (0..<4).map { _ in state.requestPointerDown(on: .statusItem) }

        XCTAssertEqual(actions, [.open, .close, .open, .close])
        XCTAssertFalse(state.isPresented)
    }
}
