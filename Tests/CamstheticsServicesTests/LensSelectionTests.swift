import AVFoundation
import XCTest
@testable import CamstheticsServices

// MARK: - LensSelection unit tests
//
// `LensSelection.options(...)` deliberately operates on already-queried
// value types (device-type array, zoom-factor values) rather than
// `AVCaptureDevice` directly, specifically so it is testable with
// constructed fixtures — `AVCaptureDevice` has no public initializer and
// cannot be synthesized without real hardware. Runs via plain
// `swift test`, no simulator/device needed, matching
// CaptureFormatSelectionTests' established pattern.
//
// Fixture device types are built via `AVCaptureDevice.DeviceType(rawValue:)`
// with the literal raw strings, rather than the `.builtInUltraWideCamera`/
// `.builtInTelephotoCamera` static constants: those specific constants are
// iOS/iPadOS/Mac-Catalyst/tvOS-only (unavailable on plain macOS, per the
// SDK's own availability annotations — verified by attempting to build),
// while `LensSelection` itself is genuinely platform-agnostic pure logic
// that should stay testable on macOS too (ARCHITECTURE.md §6.1's
// macOS-speed test tier). Constructing via the raw String initializer
// (which is not restricted) keeps this test file cross-platform without
// `#if os(iOS)` guards, and doubles as evidence `LensSelection` has no
// hidden iOS-only dependency.
private enum Fixture {
    static let ultraWide = AVCaptureDevice.DeviceType(rawValue: "AVCaptureDeviceTypeBuiltInUltraWideCamera")
    static let wideAngle = AVCaptureDevice.DeviceType(rawValue: "AVCaptureDeviceTypeBuiltInWideAngleCamera")
    static let telephoto = AVCaptureDevice.DeviceType(rawValue: "AVCaptureDeviceTypeBuiltInTelephotoCamera")
}

final class LensSelectionTests: XCTestCase {

    // MARK: Non-virtual (single-camera) devices — e.g. iPhone SE

    func testSingleCameraDeviceProducesExactlyOneOneTimesOption() {
        let options = LensSelection.options(
            constituentDeviceTypes: [],
            minAvailableVideoZoomFactor: 1.0,
            switchOverVideoZoomFactors: []
        )

        XCTAssertEqual(options.count, 1)
        XCTAssertEqual(options.first?.zoomFactor, 1.0)
        XCTAssertEqual(options.first?.label, "1×")
    }

    // MARK: Dual-wide devices (ultra-wide + wide, no telephoto) — e.g. iPhone 13
    //
    // Realistic values: the Wide constituent conventionally enters at raw
    // factor 1.0 (Apple's own "1.0 = full field of view" reference point),
    // so a normally-behaving dual-wide device's ultra-wide entry (0.5) and
    // switch-over (1.0) already align with the label convention with no
    // adjustment needed — this is the "nothing anomalous, fix is a no-op"
    // case, contrasted with the real-hardware-observed anomaly covered by
    // `testAnomalousDualWideDeviceLabelsRelativeToWideNotRawFactor` below.

    func testDualWideDeviceProducesHalfAndOneTimesOptions() {
        let options = LensSelection.options(
            constituentDeviceTypes: [Fixture.ultraWide, Fixture.wideAngle],
            minAvailableVideoZoomFactor: 0.5,
            switchOverVideoZoomFactors: [1.0]
        )

        XCTAssertEqual(options.count, 2)
        XCTAssertEqual(options[0].zoomFactor, 0.5)
        XCTAssertEqual(options[0].label, "0.5×")
        XCTAssertEqual(options[0].deviceType, Fixture.ultraWide)
        XCTAssertEqual(options[1].zoomFactor, 1.0)
        XCTAssertEqual(options[1].label, "1×")
        XCTAssertEqual(options[1].deviceType, Fixture.wideAngle)
    }

    // MARK: Physical-device-observed anomaly (Phase 2 hardware checkpoint)
    //
    // On the actual iPhone 16 (iPhone17,3) this shipped on, this dual-wide
    // device reports minAvailableVideoZoomFactor=1.0 and
    // virtualDeviceSwitchOverVideoZoomFactors=[2.0] — i.e. every entry
    // factor scaled ×2 relative to the conventional 0.5/1.0 above. Before
    // this fix, that produced buttons labeled "1×"/"2×" (confirmed on
    // physical hardware: the "1×" button was actually driving the Ultra
    // Wide constituent — visibly noisier/softer footage — while "2×" drove
    // the Wide constituent). The fix labels relative to the Wide
    // constituent's own entry factor, which is immune to any such uniform
    // scaling of the device's reported factors: the RAW zoomFactor values
    // (what actually drives the hardware) are unchanged either way.

    func testAnomalousDualWideDeviceLabelsRelativeToWideNotRawFactor() {
        let options = LensSelection.options(
            constituentDeviceTypes: [Fixture.ultraWide, Fixture.wideAngle],
            minAvailableVideoZoomFactor: 1.0,
            switchOverVideoZoomFactors: [2.0]
        )

        XCTAssertEqual(options.count, 2)
        // Raw factors — what's actually passed to videoZoomFactor/ramp —
        // are exactly what the device reported, untouched.
        XCTAssertEqual(options[0].zoomFactor, 1.0)
        XCTAssertEqual(options[1].zoomFactor, 2.0)
        // Labels are corrected to be relative to the Wide constituent
        // (index 1, raw factor 2.0), not the raw factor itself.
        XCTAssertEqual(options[0].label, "0.5×")
        XCTAssertEqual(options[0].deviceType, Fixture.ultraWide)
        XCTAssertEqual(options[1].label, "1×")
        XCTAssertEqual(options[1].deviceType, Fixture.wideAngle)
    }

    // MARK: Triple-camera devices (ultra-wide + wide + telephoto) — e.g. iPhone 16 Pro

    func testTripleCameraDeviceProducesThreeOptionsInOrder() {
        let options = LensSelection.options(
            constituentDeviceTypes: [Fixture.ultraWide, Fixture.wideAngle, Fixture.telephoto],
            minAvailableVideoZoomFactor: 0.5,
            switchOverVideoZoomFactors: [1.0, 5.0]
        )

        XCTAssertEqual(options.map(\.zoomFactor), [0.5, 1.0, 5.0])
        XCTAssertEqual(options.map(\.label), ["0.5×", "1×", "5×"])
        XCTAssertEqual(options.map(\.deviceType), [Fixture.ultraWide, Fixture.wideAngle, Fixture.telephoto])
    }

    // MARK: Defensive bounds handling

    func testMismatchedFactorAndDeviceTypeCountsNeverIndexOutOfBounds() {
        // Fewer switch-over factors than constituents minus one — should
        // never crash, just produce fewer options than constituents.
        let options = LensSelection.options(
            constituentDeviceTypes: [Fixture.ultraWide, Fixture.wideAngle, Fixture.telephoto],
            minAvailableVideoZoomFactor: 0.5,
            switchOverVideoZoomFactors: []
        )

        XCTAssertEqual(options.count, 1)
        XCTAssertEqual(options.first?.zoomFactor, 0.5)
    }

    // MARK: Dual camera (wide + telephoto, no ultra-wide) — e.g. iPhone 12 Pro

    func testDualCameraDeviceProducesOneAndTelephotoOptionsWithNoSubOneEntry() {
        // Distinct from dual-WIDE: this constituent order has no
        // ultra-wide, so minAvailableVideoZoomFactor is 1.0, not 0.5 —
        // there must be no fabricated "0.5×" entry here.
        let options = LensSelection.options(
            constituentDeviceTypes: [Fixture.wideAngle, Fixture.telephoto],
            minAvailableVideoZoomFactor: 1.0,
            switchOverVideoZoomFactors: [2.0]
        )

        XCTAssertEqual(options.map(\.zoomFactor), [1.0, 2.0])
        XCTAssertEqual(options.map(\.label), ["1×", "2×"])
        XCTAssertNil(options.first(where: { $0.zoomFactor < 1.0 }))
    }

    // MARK: Label formatting

    func testLabelFormattingWholeNumbersOmitDecimal() {
        XCTAssertEqual(LensSelection.label(for: 1.0), "1×")
        XCTAssertEqual(LensSelection.label(for: 2.0), "2×")
        XCTAssertEqual(LensSelection.label(for: 5.0), "5×")
    }

    func testLabelFormattingFractionalKeepsOneDecimal() {
        XCTAssertEqual(LensSelection.label(for: 0.5), "0.5×")
    }

    // MARK: Zoom-ramp rate derivation (Track A2)

    func testRampRateScalesWithStopCountForFixedDuration() {
        // 1× → 2× is exactly 1 stop; 1× → 4× is exactly 2 stops. For the
        // same target duration, the 2-stop jump needs double the rate.
        let oneStopRate = LensSelection.rampRate(from: 1.0, to: 2.0, duration: 0.35)
        let twoStopRate = LensSelection.rampRate(from: 1.0, to: 4.0, duration: 0.35)

        XCTAssertEqual(twoStopRate, oneStopRate * 2, accuracy: 0.001)
    }

    func testRampRateIsDirectionIndependent() {
        // Zooming out (2×→1×) should take the same rate as zooming in
        // (1×→2×) for the same duration — `rate` "controls the speed...
        // independent of direction" per Apple's documentation.
        let zoomIn = LensSelection.rampRate(from: 1.0, to: 2.0, duration: 0.35)
        let zoomOut = LensSelection.rampRate(from: 2.0, to: 1.0, duration: 0.35)

        XCTAssertEqual(zoomIn, zoomOut, accuracy: 0.001)
    }

    func testRampRateShorterDurationProducesHigherRate() {
        let slow = LensSelection.rampRate(from: 1.0, to: 2.0, duration: 0.7)
        let fast = LensSelection.rampRate(from: 1.0, to: 2.0, duration: 0.35)

        XCTAssertGreaterThan(fast, slow)
    }

    func testRampRateEqualFactorsReturnNoOpDefault() {
        XCTAssertEqual(LensSelection.rampRate(from: 2.0, to: 2.0, duration: 0.35), 1.0)
    }

    func testRampRateNeverReturnsZeroOrNegativeForDegenerateInputs() {
        XCTAssertGreaterThan(LensSelection.rampRate(from: 0, to: 2.0, duration: 0.35), 0)
        XCTAssertGreaterThan(LensSelection.rampRate(from: 1.0, to: 0, duration: 0.35), 0)
        XCTAssertGreaterThan(LensSelection.rampRate(from: 1.0, to: 2.0, duration: 0), 0)
    }

    func testRampRateHasAFloorForVeryLongDurations() {
        // An extremely long requested duration would compute a
        // near-zero rate — the floor keeps it from becoming a
        // never-finishing ramp.
        let rate = LensSelection.rampRate(from: 1.0, to: 1.01, duration: 1000)
        XCTAssertGreaterThanOrEqual(rate, 0.1)
    }

    func testRampRateHasACeilingForVeryLargeJumps() {
        // A pathological multi-stop jump (e.g. 0.5× to 100×, ~7.6 stops)
        // over the normal 0.35s duration would compute an enormous rate
        // without a ceiling — defeating the entire point of deriving the
        // rate (a visible ramp, not a snap).
        let rate = LensSelection.rampRate(from: 0.5, to: 100, duration: 0.35)
        XCTAssertLessThanOrEqual(rate, 6.0)
    }

    func testRampRateRejectsNonFiniteInputs() {
        XCTAssertEqual(LensSelection.rampRate(from: .nan, to: 2.0, duration: 0.35), 1.0)
        XCTAssertEqual(LensSelection.rampRate(from: 1.0, to: .infinity, duration: 0.35), 1.0)
        XCTAssertEqual(LensSelection.rampRate(from: 1.0, to: 2.0, duration: .nan), 1.0)
        XCTAssertEqual(LensSelection.rampRate(from: 1.0, to: 2.0, duration: .infinity), 1.0)
    }

    func testRampRateRejectsNegativeInputs() {
        XCTAssertEqual(LensSelection.rampRate(from: -1.0, to: 2.0, duration: 0.35), 1.0)
        XCTAssertEqual(LensSelection.rampRate(from: 1.0, to: -2.0, duration: 0.35), 1.0)
        XCTAssertEqual(LensSelection.rampRate(from: 1.0, to: 2.0, duration: -0.35), 1.0)
    }

    func testRampRateHandlesVerySmallDeltaWithoutUnderflow() {
        // A sub-1% zoom nudge should still produce a finite, positive,
        // floored rate rather than 0 or a denormal/garbage value.
        let rate = LensSelection.rampRate(from: 1.0, to: 1.0001, duration: 0.35)
        XCTAssertTrue(rate.isFinite)
        XCTAssertGreaterThanOrEqual(rate, 0.1)
    }

    // MARK: Duplicate / near-duplicate level collapsing (Track B)

    func testOptionsCollapsesNearDuplicateSwitchOverFactors() {
        // A device reporting a switch-over factor indistinguishable from
        // minAvailableVideoZoomFactor (e.g. 0.5 and 0.503) should not
        // produce two visually-identical "0.5×" buttons.
        let options = LensSelection.options(
            constituentDeviceTypes: [Fixture.ultraWide, Fixture.wideAngle, Fixture.telephoto],
            minAvailableVideoZoomFactor: 0.5,
            switchOverVideoZoomFactors: [0.503, 5.0]
        )

        XCTAssertEqual(options.map(\.zoomFactor), [0.5, 5.0])
    }

    func testOptionsRejectsNonFiniteOrNonPositiveFactors() {
        let options = LensSelection.options(
            constituentDeviceTypes: [Fixture.ultraWide, Fixture.wideAngle, Fixture.telephoto],
            minAvailableVideoZoomFactor: 0.5,
            switchOverVideoZoomFactors: [.nan, 5.0]
        )

        // The NaN entry (index 1, wideAngle) is dropped; the valid
        // entries survive.
        XCTAssertEqual(options.map(\.zoomFactor), [0.5, 5.0])
        XCTAssertEqual(options.map(\.deviceType), [Fixture.ultraWide, Fixture.telephoto])
    }

    // MARK: No Wide constituent at all — raw-factor fallback

    func testNoWideConstituentFallsBackToRawFactorLabeling() {
        // Hypothetical/edge case: a virtual device with no
        // .builtInWideAngleCamera constituent at all. There is no "Wide
        // lens" to be relative to, so the label must fall back to the raw
        // factor rather than silently mislabeling or crashing.
        let options = LensSelection.options(
            constituentDeviceTypes: [Fixture.ultraWide, Fixture.telephoto],
            minAvailableVideoZoomFactor: 0.5,
            switchOverVideoZoomFactors: [3.0]
        )

        XCTAssertEqual(options.map(\.zoomFactor), [0.5, 3.0])
        XCTAssertEqual(options.map(\.label), ["0.5×", "3×"])
    }

    // MARK: displayFactor (pure conversion helper)

    func testDisplayFactorDividesByWideEntryFactor() {
        XCTAssertEqual(LensSelection.displayFactor(rawZoomFactor: 1.0, wideEntryFactor: 2.0), 0.5, accuracy: 0.0001)
        XCTAssertEqual(LensSelection.displayFactor(rawZoomFactor: 2.0, wideEntryFactor: 2.0), 1.0, accuracy: 0.0001)
        XCTAssertEqual(LensSelection.displayFactor(rawZoomFactor: 4.0, wideEntryFactor: 2.0), 2.0, accuracy: 0.0001)
    }

    func testDisplayFactorFallsBackToRawWhenNoWideEntryFactorKnown() {
        XCTAssertEqual(LensSelection.displayFactor(rawZoomFactor: 3.5, wideEntryFactor: nil), 3.5)
    }

    func testDisplayFactorFallsBackToRawForInvalidWideEntryFactor() {
        XCTAssertEqual(LensSelection.displayFactor(rawZoomFactor: 3.5, wideEntryFactor: 0), 3.5)
        XCTAssertEqual(LensSelection.displayFactor(rawZoomFactor: 3.5, wideEntryFactor: -1.0), 3.5)
        XCTAssertEqual(LensSelection.displayFactor(rawZoomFactor: 3.5, wideEntryFactor: .nan), 3.5)
    }

    // MARK: snapToNativeResolution (intelligent zoom snap)
    //
    // Device-agnostic by construction: every test passes its own
    // `secondaryNativeResolutionZoomFactors` array — nothing here assumes
    // any specific device's values (e.g. the iPhone 16 unit's measured
    // [4.0] raw). A device/format reporting an empty array (most devices,
    // most formats) must make this a pure no-op — covered below.

    func testSnapToNativeResolutionSnapsWhenWithinTolerance() {
        let snapped = LensSelection.snapToNativeResolution(
            target: 3.92, secondaryNativeResolutionZoomFactors: [4.0], tolerance: 0.15
        )
        XCTAssertEqual(snapped, 4.0)
    }

    func testSnapToNativeResolutionDoesNotSnapWhenOutsideTolerance() {
        let snapped = LensSelection.snapToNativeResolution(
            target: 3.5, secondaryNativeResolutionZoomFactors: [4.0], tolerance: 0.15
        )
        XCTAssertEqual(snapped, 3.5)
    }

    func testSnapToNativeResolutionIsNoOpForEmptyFactors() {
        // The common case: a device/format that reports no secondary
        // native-resolution points at all.
        let snapped = LensSelection.snapToNativeResolution(
            target: 4.0, secondaryNativeResolutionZoomFactors: [], tolerance: 0.15
        )
        XCTAssertEqual(snapped, 4.0)
    }

    func testSnapToNativeResolutionPicksNearestOfMultiplePoints() {
        let snapped = LensSelection.snapToNativeResolution(
            target: 4.95, secondaryNativeResolutionZoomFactors: [2.0, 5.0, 9.0], tolerance: 0.2
        )
        XCTAssertEqual(snapped, 5.0)
    }

    func testSnapToNativeResolutionRejectsNonFiniteInputs() {
        XCTAssertEqual(LensSelection.snapToNativeResolution(target: .nan, secondaryNativeResolutionZoomFactors: [4.0]).isNaN, true)
        XCTAssertEqual(LensSelection.snapToNativeResolution(target: 4.0, secondaryNativeResolutionZoomFactors: [.nan]), 4.0)
    }

    // MARK: clampedExposureBias (tap-to-exposure policy)
    //
    // Two independent limits: the device's own reported range, and
    // PRODUCT_SPEC.md §1.5's tighter ±2 EV product cap. Device ranges are
    // passed in per-test — nothing assumes the ±8 EV the current test
    // unit happens to report.

    func testExposureBiasWithinBothLimitsPassesThrough() {
        XCTAssertEqual(
            LensSelection.clampedExposureBias(1.0, deviceMin: -8, deviceMax: 8), 1.0, accuracy: 0.0001
        )
    }

    func testExposureBiasClampedByProductLimitNotDeviceRange() {
        // Device would allow ±8, but the product cap is ±2.
        XCTAssertEqual(
            LensSelection.clampedExposureBias(6.0, deviceMin: -8, deviceMax: 8), 2.0, accuracy: 0.0001
        )
        XCTAssertEqual(
            LensSelection.clampedExposureBias(-6.0, deviceMin: -8, deviceMax: 8), -2.0, accuracy: 0.0001
        )
    }

    func testExposureBiasClampedByDeviceRangeWhenNarrowerThanProductLimit() {
        // A hypothetical device narrower than the ±2 product cap must win.
        XCTAssertEqual(
            LensSelection.clampedExposureBias(1.8, deviceMin: -0.5, deviceMax: 0.5), 0.5, accuracy: 0.0001
        )
        XCTAssertEqual(
            LensSelection.clampedExposureBias(-1.8, deviceMin: -0.5, deviceMax: 0.5), -0.5, accuracy: 0.0001
        )
    }

    func testExposureBiasRejectsNonFiniteInput() {
        XCTAssertEqual(LensSelection.clampedExposureBias(.nan, deviceMin: -8, deviceMax: 8), 0)
        XCTAssertEqual(LensSelection.clampedExposureBias(.infinity, deviceMin: -8, deviceMax: 8), 0)
    }

    func testExposureBiasHandlesInvertedDeviceRangeSafely() {
        // Degenerate/contradictory device report must yield neutral, not
        // a nonsense value or a crash.
        XCTAssertEqual(LensSelection.clampedExposureBias(1.0, deviceMin: 5, deviceMax: -5), 0)
    }

    func testSnapToNativeResolutionJustInsideToleranceSnaps() {
        // 0.10 is safely inside a 0.15 tolerance without relying on exact
        // floating-point boundary equality (4.0 + 0.15 is not always
        // bit-identical to a distance of exactly 0.15).
        let snapped = LensSelection.snapToNativeResolution(
            target: 4.10, secondaryNativeResolutionZoomFactors: [4.0], tolerance: 0.15
        )
        XCTAssertEqual(snapped, 4.0)
    }
}
