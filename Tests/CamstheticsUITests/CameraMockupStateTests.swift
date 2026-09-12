import XCTest
@testable import CamstheticsUI

// MARK: - CameraMockupState unit tests
//
// `CameraMockupState` is mostly UI presentation state, not deeply testable
// logic — most of its properties are plain stored values a view mutates
// directly, which would be restating the implementation rather than
// testing behavior. These tests cover the handful of methods with actual
// logic (clamping, selection bookkeeping) where a wrong implementation
// would produce an observably wrong result.
@MainActor
final class CameraMockupStateTests: XCTestCase {

    func testDragExposureClampsToDocumentedRange() {
        // PRODUCT_SPEC.md §1.5: "adjusts exposure compensation (±2.0 EV)."
        let state = CameraMockupState()

        state.dragExposure(to: 5.0)
        XCTAssertEqual(state.exposureBiasEV, 2.0)

        state.dragExposure(to: -5.0)
        XCTAssertEqual(state.exposureBiasEV, -2.0)

        state.dragExposure(to: 0.75)
        XCTAssertEqual(state.exposureBiasEV, 0.75)
    }

    func testSelectLensUpdatesSelectionAndZoomFactorTogether() {
        let state = CameraMockupState()
        let option = MockLensOption(id: "0.5", label: ".5", zoomFactor: 0.5)

        state.selectLens(option)

        XCTAssertEqual(state.selectedLensID, "0.5")
        XCTAssertEqual(state.currentZoomFactor, 0.5)
    }

    func testFocusAndExposeSetsReticleAndClearsLock() {
        let state = CameraMockupState()
        state.lockAEAF()
        XCTAssertTrue(state.isAEAFLocked)

        state.focusAndExpose(at: CGPoint(x: 100, y: 200))

        XCTAssertEqual(state.reticlePosition, CGPoint(x: 100, y: 200))
        XCTAssertTrue(state.isExposureExpanded)
        // A fresh tap-to-focus should not inherit a previous AE/AF lock.
        XCTAssertFalse(state.isAEAFLocked)
    }

    func testClearReticleResetsAllExposureState() {
        let state = CameraMockupState()
        state.focusAndExpose(at: CGPoint(x: 10, y: 10))
        state.dragExposure(to: 1.5)
        state.lockAEAF()

        state.clearReticle()

        XCTAssertNil(state.reticlePosition)
        XCTAssertFalse(state.isExposureExpanded)
        XCTAssertFalse(state.isAEAFLocked)
        XCTAssertEqual(state.exposureBiasEV, 0)
    }

    func testToggleGridFlipsVisibility() {
        let state = CameraMockupState()
        let initial = state.showRuleOfThirdsGrid

        state.toggleGrid()

        XCTAssertEqual(state.showRuleOfThirdsGrid, !initial)
    }

    func testSelectModeUpdatesSelection() {
        let state = CameraMockupState()
        state.selectMode(.scan)
        XCTAssertEqual(state.selectedMode, .scan)
    }
}
