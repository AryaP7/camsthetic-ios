// Phase1RegressionTests.swift
// CamstheticsEngineTests
// Regression coverage for the Phase 1 audit findings: dwell identity under numerical refinement,
// duplicate slot collisions during dwell contention, and PARTIAL tier cue composition.

import XCTest
@testable import CamstheticsEngine

final class Phase1RegressionTests: XCTestCase {
    // MARK: - Helpers

    private func params(
        tilt: Double = 0.0,
        lateral: Double = 0.5,
        height: Double = 0.5,
        ratio: Double = 0.5,
        hasSubject: Bool = true
    ) -> CompositionParams {
        // The subject rect carries the lateral / height / size error so that both the raw delta path and
        // the aspect-normalized engine path (which re-derives the anchor from the rect) see the same values.
        let rect = NormRect(center: NormPoint(x: lateral, y: height), width: 0.3, height: ratio)
        return CompositionParams(
            aspectRatio: 1.0,
            subjectRect: hasSubject ? rect : nil,
            subjectCategory: hasSubject ? .person : .unknown,
            subjectRatio: hasSubject ? ratio : 0.0,
            tiltDegrees: tilt,
            heightRatio: height,
            lateralRatio: lateral
        )
    }

    @discardableResult
    private func step(
        _ filter: inout AntiFlickerFilter,
        target: CompositionParams,
        live: CompositionParams,
        at timestamp: TimeInterval
    ) -> [CoachingInstruction] {
        let delta = DeltaEngine.computeDelta(target: target, live: live)
        return filter.update(delta: delta, target: target, live: live, timestamp: timestamp)
    }

    private func assertUniqueDimensions(
        _ instructions: [CoachingInstruction],
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let dims = instructions.map { $0.dimension }
        XCTAssertEqual(Set(dims).count, dims.count, "Duplicate coaching dimension surfaced: \(message)", file: file, line: line)
        XCTAssertLessThanOrEqual(instructions.count, AntiFlickerFilter.maxSurfacedInstructions, message, file: file, line: line)
    }

    // MARK: - 1. Continuous angular refinement during dwell

    func testContinuousAngularRefinementDoesNotRestartDwellWindow() {
        var timer = DwellTimer(slotCount: 2)

        // Placed at t = 1.0, then continuously refined: 5° -> 4° -> 3°
        timer.update(slot: 0, instruction: .rotateClockwise(degrees: 5), currentTimestamp: 1.0)
        timer.update(slot: 0, instruction: .rotateClockwise(degrees: 4), currentTimestamp: 1.2)
        timer.update(slot: 0, instruction: .rotateClockwise(degrees: 3), currentTimestamp: 1.5)

        // Dwell identity is unchanged by numeric refinement, so the window still runs from t = 1.0
        XCTAssertEqual(timer.currentIdentity(slot: 0), DwellTimer.identity(for: .rotateClockwise(degrees: 5)))
        XCTAssertEqual(timer.currentInstruction(slot: 0), .rotateClockwise(degrees: 3))
        XCTAssertFalse(timer.canReplace(slot: 0, currentTimestamp: 1.65), "700ms dwell must still be running at t = 1.65")
        XCTAssertTrue(timer.canReplace(slot: 0, currentTimestamp: 1.70), "700ms dwell must expire 700ms after first placement")

        // A genuine direction change is a different instruction: dwell restarts
        timer.update(slot: 0, instruction: .rotateCounterClockwise(degrees: 3), currentTimestamp: 1.8)
        XCTAssertFalse(timer.canReplace(slot: 0, currentTimestamp: 2.4))
        XCTAssertTrue(timer.canReplace(slot: 0, currentTimestamp: 2.5))

        // A genuine dimension change restarts dwell
        timer.update(slot: 0, instruction: .panRight, currentTimestamp: 2.6)
        XCTAssertFalse(timer.canReplace(slot: 0, currentTimestamp: 3.2))
        XCTAssertTrue(timer.canReplace(slot: 0, currentTimestamp: 3.35))

        // Pan -> Step is a semantic change within the same dimension: dwell restarts
        timer.update(slot: 0, instruction: .stepRight, currentTimestamp: 3.4)
        XCTAssertFalse(timer.canReplace(slot: 0, currentTimestamp: 4.0))
        XCTAssertTrue(timer.canReplace(slot: 0, currentTimestamp: 4.15))
    }

    func testRefinedAngleKeepsSurfacingWhileDwelling() {
        var filter = AntiFlickerFilter()
        let live = params(tilt: 0.0)

        // Settle tilt active with 5°
        step(&filter, target: params(tilt: 5.0), live: live, at: 0.0)
        step(&filter, target: params(tilt: 5.0), live: live, at: 0.1)
        let settled = step(&filter, target: params(tilt: 5.0), live: live, at: 0.2)
        XCTAssertEqual(settled, [.rotateClockwise(degrees: 5)])

        // Continuous refinement inside the 700ms dwell window must track the newest angle
        let refined4 = step(&filter, target: params(tilt: 4.0), live: live, at: 0.3)
        XCTAssertEqual(refined4, [.rotateClockwise(degrees: 4)])

        let refined3 = step(&filter, target: params(tilt: 3.0), live: live, at: 0.5)
        XCTAssertEqual(refined3, [.rotateClockwise(degrees: 3)])

        // ...and the dwell window is still keyed to the original placement at t = 0.2
        let refined3Again = step(&filter, target: params(tilt: 3.0), live: live, at: 0.85)
        XCTAssertEqual(refined3Again, [.rotateClockwise(degrees: 3)])
    }

    // MARK: - 2. Duplicate slot collision during dwell contention

    func testDwellContentionDoesNotDuplicateSlotOrSwallowHigherPriorityCue() {
        var filter = AntiFlickerFilter()
        let live = params(tilt: 0.0, lateral: 0.50)
        let lateralOnly = params(tilt: 0.0, lateral: 0.60)
        let lateralAndTilt = params(tilt: 5.0, lateral: 0.60)

        // Lateral settles into slot 0 at t = 0.2
        step(&filter, target: lateralOnly, live: live, at: 0.0)
        step(&filter, target: lateralOnly, live: live, at: 0.1)
        let lateralSettled = step(&filter, target: lateralOnly, live: live, at: 0.2)
        XCTAssertEqual(lateralSettled, [.panRight])

        // Higher-priority tilt becomes active at t = 0.5, while slot 0 is still dwell-locked on lateral
        step(&filter, target: lateralAndTilt, live: live, at: 0.3)
        step(&filter, target: lateralAndTilt, live: live, at: 0.4)
        let contended = step(&filter, target: lateralAndTilt, live: live, at: 0.5)

        assertUniqueDimensions(contended, "dwell contention at t = 0.5")
        XCTAssertEqual(
            contended,
            [.panRight, .rotateClockwise(degrees: 5)],
            "Slot 0 must hold its dwell-locked cue for 700ms while the higher-priority cue takes the free slot"
        )

        // While slot 1 is itself dwell-locked, the arrangement stays stable and duplicate-free
        let held = step(&filter, target: lateralAndTilt, live: live, at: 0.9)
        assertUniqueDimensions(held, "post-lateral-dwell at t = 0.9")
        XCTAssertEqual(held, [.panRight, .rotateClockwise(degrees: 5)])

        // Once both dwell windows have elapsed, strict priority re-asserts itself
        let reordered = step(&filter, target: lateralAndTilt, live: live, at: 1.3)
        assertUniqueDimensions(reordered, "priority restoration at t = 1.3")
        XCTAssertEqual(reordered, [.rotateClockwise(degrees: 5), .panRight])
    }

    // MARK: - 3. PARTIAL tier: active tilt + missing subject

    func testPartialTierKeepsActiveTiltAlongsideFindSubject() {
        var engine = CoachingEngine()
        let target = params(tilt: 5.0, lateral: 0.50)
        let liveNoSubject = params(tilt: 0.0, hasSubject: false)

        // 5 frames commit the tier transition to PARTIAL; tilt is active from frame 3
        var output: CoachingOutput!
        for i in 0..<5 {
            output = engine.processFrame(target: target, live: liveNoSubject, timestamp: Double(i) * 0.1)
        }

        XCTAssertEqual(output.tier, .partial)
        XCTAssertEqual(output.surfacedInstructions, [.rotateClockwise(degrees: 5), .findSubject])
        XCTAssertLessThanOrEqual(output.score, 60, "PARTIAL tier score stays capped at 60")

        // The subject flickers back for 3 frames: lateral can go active (3-frame entry) before the tier
        // can return to FULL (5-frame transition). The tilt cue must keep its slot and the prompt must remain.
        let liveWithOffsetSubject = params(tilt: 0.0, lateral: 0.30)
        for i in 5..<8 {
            output = engine.processFrame(target: target, live: liveWithOffsetSubject, timestamp: Double(i) * 0.1)
        }

        XCTAssertEqual(output.tier, .partial)
        assertUniqueDimensions(output.surfacedInstructions, "PARTIAL tier with reappearing subject")
        XCTAssertEqual(
            output.surfacedInstructions,
            [.rotateClockwise(degrees: 5), .findSubject],
            "Active tilt cue must keep slot 0 and must not be replaced by (or crowd out) Find your subject"
        )
        XCTAssertLessThanOrEqual(output.score, 60)
    }

    // MARK: - 4. Multi-cue dynamic re-prioritization

    func testMultiCueDynamicRePrioritization() {
        var filter = AntiFlickerFilter()
        let live = params(tilt: 0.0, lateral: 0.50, height: 0.50, ratio: 0.5)

        // Height only
        let heightOnly = params(tilt: 0.0, lateral: 0.50, height: 0.70, ratio: 0.5)
        step(&filter, target: heightOnly, live: live, at: 0.0)
        step(&filter, target: heightOnly, live: live, at: 0.1)
        XCTAssertEqual(step(&filter, target: heightOnly, live: live, at: 0.2), [.raisePhone])

        // Distance (higher priority) joins while height is dwell-locked in slot 0
        let heightAndDistance = params(tilt: 0.0, lateral: 0.50, height: 0.70, ratio: 0.8)
        step(&filter, target: heightAndDistance, live: live, at: 0.3)
        step(&filter, target: heightAndDistance, live: live, at: 0.4)
        let contended = step(&filter, target: heightAndDistance, live: live, at: 0.5)
        assertUniqueDimensions(contended, "height dwell-locked while distance arrives")
        XCTAssertEqual(contended, [.raisePhone, .moveCloser])

        // Both dwell windows elapse: distance outranks height and takes slot 0
        let reordered = step(&filter, target: heightAndDistance, live: live, at: 1.3)
        assertUniqueDimensions(reordered, "re-prioritization after dwell")
        XCTAssertEqual(reordered, [.moveCloser, .raisePhone])

        // Tilt (top priority) joins: both slots are freshly dwell-locked, so it must wait
        let allThree = params(tilt: 6.0, lateral: 0.50, height: 0.70, ratio: 0.8)
        step(&filter, target: allThree, live: live, at: 1.4)
        step(&filter, target: allThree, live: live, at: 1.5)
        let waiting = step(&filter, target: allThree, live: live, at: 1.6)
        assertUniqueDimensions(waiting, "tilt waiting behind two dwell-locked slots")
        XCTAssertEqual(waiting, [.moveCloser, .raisePhone])

        // After the dwell windows expire, the two highest-priority cues surface and height is capped out
        let final = step(&filter, target: allThree, live: live, at: 2.1)
        assertUniqueDimensions(final, "final priority ordering")
        XCTAssertEqual(final, [.rotateClockwise(degrees: 6), .moveCloser])
        XCTAssertFalse(final.contains(.raisePhone), "Surfaced cap of 2 drops the lowest-priority cue")
    }

    // MARK: - 5. Simultaneous multi-slot dwell release

    func testSimultaneousMultiSlotDwellRelease() {
        var filter = AntiFlickerFilter()
        let live = params(tilt: 0.0, lateral: 0.50)
        let tiltAndLateral = params(tilt: 5.0, lateral: 0.60)

        // Both cues enter on the same frame and occupy both slots at t = 0.2
        step(&filter, target: tiltAndLateral, live: live, at: 0.0)
        step(&filter, target: tiltAndLateral, live: live, at: 0.1)
        let both = step(&filter, target: tiltAndLateral, live: live, at: 0.2)
        XCTAssertEqual(both, [.rotateClockwise(degrees: 5), .panRight])

        // Both errors resolve on the same frame: 4 absent frames release both slots together
        let aligned = params(tilt: 0.5, lateral: 0.51)
        XCTAssertEqual(step(&filter, target: aligned, live: live, at: 0.3).count, 2)
        XCTAssertEqual(step(&filter, target: aligned, live: live, at: 0.4).count, 2)
        XCTAssertEqual(step(&filter, target: aligned, live: live, at: 0.5).count, 2)
        let released = step(&filter, target: aligned, live: live, at: 0.6)
        XCTAssertTrue(released.isEmpty, "Both slots must release on the same frame")

        // No stale residue: a brand new cue takes slot 0 immediately after its 3-frame entry
        let distanceOnly = params(tilt: 0.5, lateral: 0.51, ratio: 0.8)
        step(&filter, target: distanceOnly, live: live, at: 0.7)
        step(&filter, target: distanceOnly, live: live, at: 0.8)
        let fresh = step(&filter, target: distanceOnly, live: live, at: 0.9)
        assertUniqueDimensions(fresh, "fresh cue after simultaneous release")
        XCTAssertEqual(fresh, [.moveCloser])
    }

    // MARK: - 6. Rapid subject jitter / dropouts

    func testRapidSubjectJitterAndDropouts() {
        var engine = CoachingEngine()
        let target = params(tilt: 5.0, lateral: 0.50)
        let liveWithSubject = params(tilt: 0.0, lateral: 0.35)
        let liveNoSubject = params(tilt: 0.0, hasSubject: false)

        func assertInvariants(_ output: CoachingOutput, _ frame: Int) {
            assertUniqueDimensions(output.surfacedInstructions, "frame \(frame)")
            XCTAssertFalse(output.delta.deltaTilt.isNaN, "frame \(frame)")
            XCTAssertFalse(output.delta.deltaDistance.isNaN, "frame \(frame)")
            XCTAssertFalse(output.delta.deltaDistance.isInfinite, "frame \(frame)")
            XCTAssertGreaterThanOrEqual(output.score, 0, "frame \(frame)")
            XCTAssertLessThanOrEqual(output.score, output.tier.maxScoreCap, "frame \(frame)")
            if output.tier == .partial {
                XCTAssertTrue(output.surfacedInstructions.contains(.findSubject), "PARTIAL must prompt Find your subject at frame \(frame)")
                let nonTilt = output.surfacedInstructions.filter { $0 != .findSubject && $0.dimension != .tilt }
                XCTAssertTrue(nonTilt.isEmpty, "PARTIAL must not surface subject-dependent cues at frame \(frame): \(nonTilt)")
            }
        }

        // Phase 1: single-frame dropouts every 4th frame must never flip the tier (needs 5 consecutive)
        var output: CoachingOutput!
        for frame in 0..<24 {
            let live = (frame % 4 == 3) ? liveNoSubject : liveWithSubject
            output = engine.processFrame(target: target, live: live, timestamp: Double(frame) * 0.05)
            assertInvariants(output, frame)
            XCTAssertEqual(output.tier, .full, "Transient dropouts must not degrade the tier (frame \(frame))")
        }

        // Phase 2: sustained dropout commits PARTIAL
        for frame in 24..<34 {
            output = engine.processFrame(target: target, live: liveNoSubject, timestamp: Double(frame) * 0.05)
            assertInvariants(output, frame)
        }
        XCTAssertEqual(output.tier, .partial)
        XCTAssertEqual(output.surfacedInstructions, [.rotateClockwise(degrees: 5), .findSubject])

        // Phase 3: subject recovers and the tier climbs back to FULL after 5 agreeing frames
        for frame in 34..<44 {
            output = engine.processFrame(target: target, live: liveWithSubject, timestamp: Double(frame) * 0.05)
            assertInvariants(output, frame)
        }
        XCTAssertEqual(output.tier, .full)
        XCTAssertFalse(output.surfacedInstructions.contains(.findSubject), "FULL tier must not surface the Find your subject prompt")
    }

    // MARK: - 7. Extreme small Sobel inputs

    func testExtremeSmallSobelInputs() {
        // Degenerate geometry and undersized buffers must return a safe zero-confidence result
        let degenerateCases: [(pixels: [UInt8], width: Int, height: Int)] = [
            ([], 0, 0),
            ([255], 1, 1),
            ([0, 255, 255, 0], 2, 2),
            ([UInt8](repeating: 200, count: 8), 4, 4),   // buffer smaller than width * height
            ([UInt8](repeating: 200, count: 16), -4, 4), // negative width
            ([UInt8](repeating: 200, count: 16), 4, 0)   // zero height
        ]

        for testCase in degenerateCases {
            let result = SobelEdgeTiltEstimator.estimateTilt(
                pixels: testCase.pixels,
                width: testCase.width,
                height: testCase.height
            )
            XCTAssertEqual(result.tiltDegrees, 0.0, "\(testCase.width)x\(testCase.height)")
            XCTAssertEqual(result.confidence, 0.0, "\(testCase.width)x\(testCase.height)")
        }

        // Minimum viable 3x3 with no edge energy: a single interior pixel, uniformly flat
        let flat3x3 = SobelEdgeTiltEstimator.estimateTilt(pixels: [UInt8](repeating: 128, count: 9), width: 3, height: 3)
        XCTAssertEqual(flat3x3.tiltDegrees, 0.0)
        XCTAssertEqual(flat3x3.confidence, 0.0)

        // Minimum viable 3x3 with one strong horizontal edge: level horizon, confidence within the 0.70 cap
        let edge3x3 = SobelEdgeTiltEstimator.estimateTilt(
            pixels: [0, 0, 0, 0, 0, 0, 255, 255, 255],
            width: 3,
            height: 3
        )
        XCTAssertFalse(edge3x3.tiltDegrees.isNaN)
        XCTAssertEqual(edge3x3.tiltDegrees, 0.0, accuracy: 1.5)
        XCTAssertGreaterThan(edge3x3.confidence, 0.0)
        XCTAssertLessThanOrEqual(edge3x3.confidence, SobelEdgeTiltEstimator.maxTargetTiltConfidence)

        // Minimal strips (one interior row / one interior column) must stay finite and in range
        let strip5x3 = SobelEdgeTiltEstimator.estimateTilt(
            pixels: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 255, 255, 255, 255, 255],
            width: 5,
            height: 3
        )
        XCTAssertFalse(strip5x3.tiltDegrees.isNaN)
        XCTAssertTrue(strip5x3.tiltDegrees >= -45.0 && strip5x3.tiltDegrees <= 45.0)
        XCTAssertLessThanOrEqual(strip5x3.confidence, SobelEdgeTiltEstimator.maxTargetTiltConfidence)

        let strip3x5 = SobelEdgeTiltEstimator.estimateTilt(
            pixels: [0, 0, 255, 0, 0, 255, 0, 0, 255, 0, 0, 255, 0, 0, 255],
            width: 3,
            height: 5
        )
        XCTAssertFalse(strip3x5.tiltDegrees.isNaN)
        XCTAssertTrue(strip3x5.tiltDegrees >= -45.0 && strip3x5.tiltDegrees <= 45.0)
        XCTAssertLessThanOrEqual(strip3x5.confidence, SobelEdgeTiltEstimator.maxTargetTiltConfidence)
    }
}
