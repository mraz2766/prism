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

    func testPointerEventGateConsumesOnePhysicalEventOnlyOnce() {
        var gate = PopoverPointerEventGate()
        let event = PopoverPointerEventIdentity(
            eventNumber: 42,
            timestamp: 10,
            typeRawValue: NSEvent.EventType.leftMouseDown.rawValue,
            buttonNumber: 0
        )

        XCTAssertTrue(gate.consume(event))
        XCTAssertFalse(gate.consume(event))
    }

    func testPointerEventGateDoesNotDebounceDistinctFastClicks() {
        var gate = PopoverPointerEventGate()
        let first = PopoverPointerEventIdentity(
            eventNumber: 42,
            timestamp: 10,
            typeRawValue: NSEvent.EventType.leftMouseDown.rawValue,
            buttonNumber: 0
        )
        let second = PopoverPointerEventIdentity(
            eventNumber: 43,
            timestamp: 10.001,
            typeRawValue: NSEvent.EventType.leftMouseDown.rawValue,
            buttonNumber: 0
        )

        XCTAssertTrue(gate.consume(first))
        XCTAssertTrue(gate.consume(second))
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
