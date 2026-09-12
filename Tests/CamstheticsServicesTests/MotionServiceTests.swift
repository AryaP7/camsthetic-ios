import XCTest
@testable import CamstheticsServices

// MARK: - AttitudeMath unit tests
//
// `AttitudeMath` operates only on plain `Double`s (never `CMDeviceMotion`),
// specifically so the roll/pitch derivation, the level threshold, and the
// smoothing formula are testable on macOS with no hardware — the same
// reasoning `LensSelectionTests`/`CaptureFormatSelectionTests` already
// document for this module. The `MotionService` actor itself (CoreMotion
// wiring, streaming, start/stop) is intentionally NOT exercised here: it
// has no pure-logic surface left once this math is factored out, and its
// remaining behaviour needs a physical device to mean anything.
final class MotionServiceTests: XCTestCase {

    // MARK: rollDegrees
    //
    // Expected values are `atan2(gravityX, gravityY)` in degrees — note
    // the (x, y) argument order, which is NOT the conventional
    // `atan2(y, x)`. Each case below is a value where atan2 lands on an
    // exact quadrant boundary, so the expectation is an exact literal
    // rather than a re-implementation of the formula under test.

    func testRollDegreesQuadrantBoundaries() {
        XCTAssertEqual(AttitudeMath.rollDegrees(gravityX: 0, gravityY: 1), 0, accuracy: 0.0001)
        XCTAssertEqual(AttitudeMath.rollDegrees(gravityX: 1, gravityY: 0), 90, accuracy: 0.0001)
        XCTAssertEqual(AttitudeMath.rollDegrees(gravityX: -1, gravityY: 0), -90, accuracy: 0.0001)
        XCTAssertEqual(abs(AttitudeMath.rollDegrees(gravityX: 0, gravityY: -1)), 180, accuracy: 0.0001)
    }

    func testRollDegreesDegenerateZeroVectorReturnsZero() {
        XCTAssertEqual(AttitudeMath.rollDegrees(gravityX: 0, gravityY: 0), 0)
    }

    func testRollDegreesRejectsNonFiniteInputs() {
        XCTAssertEqual(AttitudeMath.rollDegrees(gravityX: .nan, gravityY: 1), 0)
        XCTAssertEqual(AttitudeMath.rollDegrees(gravityX: 0, gravityY: .infinity), 0)
    }

    // MARK: pitchDegrees
    //
    // `atan2(gravityZ, planar)` where `planar = sqrt(x² + y²)` — well
    // defined through a full rotation, not just near upright.

    func testPitchDegreesZeroWhenGravityIsPurelyInThePlane() {
        XCTAssertEqual(AttitudeMath.pitchDegrees(gravityX: 0, gravityY: -1, gravityZ: 0), 0, accuracy: 0.0001)
    }

    func testPitchDegreesNinetyWhenGravityIsPurelyOnZAxis() {
        XCTAssertEqual(AttitudeMath.pitchDegrees(gravityX: 0, gravityY: 0, gravityZ: 1), 90, accuracy: 0.0001)
        XCTAssertEqual(AttitudeMath.pitchDegrees(gravityX: 0, gravityY: 0, gravityZ: -1), -90, accuracy: 0.0001)
    }

    func testPitchDegreesDegenerateZeroVectorReturnsZero() {
        XCTAssertEqual(AttitudeMath.pitchDegrees(gravityX: 0, gravityY: 0, gravityZ: 0), 0)
    }

    func testPitchDegreesRejectsNonFiniteInputs() {
        XCTAssertEqual(AttitudeMath.pitchDegrees(gravityX: .nan, gravityY: 0, gravityZ: 1), 0)
        XCTAssertEqual(AttitudeMath.pitchDegrees(gravityX: 0, gravityY: .infinity, gravityZ: 1), 0)
        XCTAssertEqual(AttitudeMath.pitchDegrees(gravityX: 0, gravityY: 0, gravityZ: .nan), 0)
    }

    // MARK: isLevel
    //
    // `docs/DESIGN_SYSTEM.md` §4.2's ±0.5° default, exercised at both
    // sides of the boundary and across the 0°/360° wrap.

    func testIsLevelAtExactBoundaryCountsAsLevel() {
        XCTAssertTrue(AttitudeMath.isLevel(rollDegrees: 0.5))
        XCTAssertTrue(AttitudeMath.isLevel(rollDegrees: -0.5))
    }

    func testIsLevelJustOutsideBoundaryIsNotLevel() {
        XCTAssertFalse(AttitudeMath.isLevel(rollDegrees: 0.51))
        XCTAssertFalse(AttitudeMath.isLevel(rollDegrees: -0.51))
    }

    func testIsLevelWrapsAcrossThreeSixtyDegrees() {
        // 359.8° is 0.2° from level (i.e. from 0°/360°), not 359.8° away.
        XCTAssertTrue(AttitudeMath.isLevel(rollDegrees: 359.8))
        XCTAssertTrue(AttitudeMath.isLevel(rollDegrees: -359.8))
    }

    func testIsLevelUpsideDownIsNotLevel() {
        XCTAssertFalse(AttitudeMath.isLevel(rollDegrees: 180))
    }

    func testIsLevelHonoursCustomTolerance() {
        XCTAssertTrue(AttitudeMath.isLevel(rollDegrees: 1.0, toleranceDegrees: 1.0))
        XCTAssertFalse(AttitudeMath.isLevel(rollDegrees: 1.0, toleranceDegrees: 0.9))
    }

    func testIsLevelRejectsNonFiniteInputs() {
        XCTAssertFalse(AttitudeMath.isLevel(rollDegrees: .nan))
        XCTAssertFalse(AttitudeMath.isLevel(rollDegrees: 0, toleranceDegrees: .nan))
    }

    // MARK: smoothed (exponential low-pass)

    func testSmoothedPassesNextThroughWhenNoPrevious() {
        XCTAssertEqual(AttitudeMath.smoothed(previous: nil, next: 20, alpha: 0.2), 20)
    }

    func testSmoothedAlphaOneIsPureNextPassThrough() {
        // 1.0 is MotionService.defaultSmoothingAlpha — CoreMotion's own
        // fused output flows straight through, unmodified.
        XCTAssertEqual(AttitudeMath.smoothed(previous: 10, next: 20, alpha: 1.0), 20)
    }

    func testSmoothedAlphaZeroHoldsPreviousValue() {
        XCTAssertEqual(AttitudeMath.smoothed(previous: 10, next: 20, alpha: 0.0), 10)
    }

    func testSmoothedAlphaHalfIsMidpoint() {
        XCTAssertEqual(AttitudeMath.smoothed(previous: 10, next: 20, alpha: 0.5), 15, accuracy: 0.0001)
    }

    func testSmoothedClampsOutOfRangeAlpha() {
        // alpha > 1 clamps to 1 (pure pass-through of `next`).
        XCTAssertEqual(AttitudeMath.smoothed(previous: 10, next: 20, alpha: 1.5), 20)
        // alpha < 0 clamps to 0 (pure hold of `previous`).
        XCTAssertEqual(AttitudeMath.smoothed(previous: 10, next: 20, alpha: -0.5), 10)
    }

    func testSmoothedFallsBackToNextWhenPreviousIsNonFinite() {
        XCTAssertEqual(AttitudeMath.smoothed(previous: .nan, next: 20, alpha: 0.2), 20)
    }

    func testSmoothedPassesNonFiniteNextThrough() {
        // Guard fails on a non-finite `next` too; the function returns it
        // unchanged rather than silently producing a different NaN.
        XCTAssertTrue(AttitudeMath.smoothed(previous: 10, next: .nan, alpha: 0.2).isNaN)
    }

    // MARK: DeviceAttitude

    func testDeviceAttitudeDefaultsConfidenceToOne() {
        let attitude = DeviceAttitude(rollDegrees: 1, pitchDegrees: 2, timestamp: 3)
        XCTAssertEqual(attitude.confidence, 1.0)
    }
}
