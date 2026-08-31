// HysteresisTests.swift
// CamstheticsEngineTests

import XCTest
@testable import CamstheticsEngine

final class HysteresisTests: XCTestCase {
    func testThreeConsecutiveFramesRequiredForEntry() {
        var filter = AntiFlickerFilter()
        let subject = NormRect(center: .center, width: 0.3, height: 0.5)

        // Error: Tilt = 5° (exceeds 2.0° entry tolerance)
        let target = CompositionParams(aspectRatio: 1.0, subjectRect: subject, subjectRatio: 0.5, tiltDegrees: 5.0)
        let live = CompositionParams(aspectRatio: 1.0, subjectRect: subject, subjectRatio: 0.5, tiltDegrees: 0.0)
        let delta = DeltaEngine.computeDelta(target: target, live: live)

        // Frame 1: candidate count = 1 -> not surfaced yet
        let out1 = filter.update(delta: delta, target: target, live: live, timestamp: 0.0)
        XCTAssertTrue(out1.isEmpty)

        // Frame 2: candidate count = 2 -> not surfaced yet
        let out2 = filter.update(delta: delta, target: target, live: live, timestamp: 0.1)
        XCTAssertTrue(out2.isEmpty)

        // Frame 3: candidate count = 3 -> active! Surfaced!
        let out3 = filter.update(delta: delta, target: target, live: live, timestamp: 0.2)
        XCTAssertEqual(out3.first, .rotateClockwise(degrees: 5))
    }

    func testFourConsecutiveFramesRequiredForExit() {
        var filter = AntiFlickerFilter()
        let subject = NormRect(center: .center, width: 0.3, height: 0.5)

        let targetTilted = CompositionParams(aspectRatio: 1.0, subjectRect: subject, subjectRatio: 0.5, tiltDegrees: 5.0)
        let liveLevel = CompositionParams(aspectRatio: 1.0, subjectRect: subject, subjectRatio: 0.5, tiltDegrees: 0.0)
        let deltaTilted = DeltaEngine.computeDelta(target: targetTilted, live: liveLevel)

        // Settle into active state (3 frames)
        _ = filter.update(delta: deltaTilted, target: targetTilted, live: liveLevel, timestamp: 0.0)
        _ = filter.update(delta: deltaTilted, target: targetTilted, live: liveLevel, timestamp: 0.1)
        let activeOut = filter.update(delta: deltaTilted, target: targetTilted, live: liveLevel, timestamp: 0.2)
        XCTAssertEqual(activeOut.first, .rotateClockwise(degrees: 5))

        // Now error drops to 0.5° (< 1.4° exit tolerance)
        let targetAligned = CompositionParams(aspectRatio: 1.0, subjectRect: subject, subjectRatio: 0.5, tiltDegrees: 0.5)
        let deltaAligned = DeltaEngine.computeDelta(target: targetAligned, live: liveLevel)

        // Absent Frame 1 (timestamp 0.3): still surfaced
        let exit1 = filter.update(delta: deltaAligned, target: targetAligned, live: liveLevel, timestamp: 0.3)
        XCTAssertEqual(exit1.first, .rotateClockwise(degrees: 5))

        // Absent Frame 2 (timestamp 0.4): still surfaced
        let exit2 = filter.update(delta: deltaAligned, target: targetAligned, live: liveLevel, timestamp: 0.4)
        XCTAssertEqual(exit2.first, .rotateClockwise(degrees: 5))

        // Absent Frame 3 (timestamp 0.5): still surfaced
        let exit3 = filter.update(delta: deltaAligned, target: targetAligned, live: liveLevel, timestamp: 0.5)
        XCTAssertEqual(exit3.first, .rotateClockwise(degrees: 5))

        // Absent Frame 4 (timestamp 1.0 - past 700ms dwell time): disappears!
        let exit4 = filter.update(delta: deltaAligned, target: targetAligned, live: liveLevel, timestamp: 1.0)
        XCTAssertTrue(exit4.isEmpty)
    }

    func testDeadbandBetween07And10RetainsActiveState() {
        var filter = AntiFlickerFilter()
        let subject = NormRect(center: .center, width: 0.3, height: 0.5)

        let targetTilted = CompositionParams(aspectRatio: 1.0, subjectRect: subject, subjectRatio: 0.5, tiltDegrees: 5.0)
        let liveLevel = CompositionParams(aspectRatio: 1.0, subjectRect: subject, subjectRatio: 0.5, tiltDegrees: 0.0)
        let deltaTilted = DeltaEngine.computeDelta(target: targetTilted, live: liveLevel)

        // Settle active
        _ = filter.update(delta: deltaTilted, target: targetTilted, live: liveLevel, timestamp: 0.0)
        _ = filter.update(delta: deltaTilted, target: targetTilted, live: liveLevel, timestamp: 0.1)
        _ = filter.update(delta: deltaTilted, target: targetTilted, live: liveLevel, timestamp: 0.2)

        // Error enters deadband: 1.6° (between 1.4° exit and 2.0° entry)
        let targetDeadband = CompositionParams(aspectRatio: 1.0, subjectRect: subject, subjectRatio: 0.5, tiltDegrees: 1.6)
        let deltaDeadband = DeltaEngine.computeDelta(target: targetDeadband, live: liveLevel)

        // Even after 10 frames in deadband, instruction remains active!
        for i in 1...10 {
            let out = filter.update(delta: deltaDeadband, target: targetDeadband, live: liveLevel, timestamp: 0.2 + Double(i) * 0.1)
            XCTAssertFalse(out.isEmpty, "Frame \(i) in deadband should remain active")
        }
    }

    func testMinimumDwellTimeEnforcement() {
        var timer = DwellTimer(slotCount: 2)

        // Slot 0 displays instruction at t = 1.0
        timer.update(slot: 0, instruction: .rotateClockwise(degrees: 5), currentTimestamp: 1.0)

        // At t = 1.50 (500ms elapsed < 700ms), cannot replace
        XCTAssertFalse(timer.canReplace(slot: 0, currentTimestamp: 1.50))

        // At t = 1.70 (700ms elapsed == 700ms), can replace
        XCTAssertTrue(timer.canReplace(slot: 0, currentTimestamp: 1.70))

        // At t = 2.00 (1000ms elapsed > 700ms), can replace
        XCTAssertTrue(timer.canReplace(slot: 0, currentTimestamp: 2.00))
    }

    func testContinuousAngleRefinementDoesNotResetDwellTime() {
        var timer = DwellTimer(slotCount: 2)

        // Slot 0 displays tilt at t = 1.0
        timer.update(slot: 0, instruction: .rotateClockwise(degrees: 5), currentTimestamp: 1.0)

        // Continuous refinements at t = 1.2, 1.4, 1.6 (same dimension .tilt)
        timer.update(slot: 0, instruction: .rotateClockwise(degrees: 4), currentTimestamp: 1.2)
        timer.update(slot: 0, instruction: .rotateClockwise(degrees: 3), currentTimestamp: 1.4)
        timer.update(slot: 0, instruction: .rotateClockwise(degrees: 2), currentTimestamp: 1.6)

        // At t = 1.75 (750ms since initial placement at t=1.0), slot 0 should now be eligible for replacement!
        XCTAssertTrue(timer.canReplace(slot: 0, currentTimestamp: 1.75))
    }

    func testSurfacedInstructionDeduplication() {
        var filter = AntiFlickerFilter()
        let subject = NormRect(center: .center, width: 0.3, height: 0.5)

        // Target requires tilt (5°) and lateral (+0.10)
        let target = CompositionParams(
            aspectRatio: 1.0,
            subjectRect: subject,
            subjectRatio: 0.5,
            tiltDegrees: 5.0,
            lateralRatio: 0.60
        )
        let live = CompositionParams(
            aspectRatio: 1.0,
            subjectRect: subject,
            subjectRatio: 0.5,
            tiltDegrees: 0.0,
            lateralRatio: 0.50
        )
        let delta = DeltaEngine.computeDelta(target: target, live: live)

        // Settle active
        _ = filter.update(delta: delta, target: target, live: live, timestamp: 0.0)
        _ = filter.update(delta: delta, target: target, live: live, timestamp: 0.1)
        let surfaced = filter.update(delta: delta, target: target, live: live, timestamp: 0.2)

        // Ensure unique dimensions
        let dims = surfaced.map { $0.dimension }
        XCTAssertEqual(dims.count, Set(dims).count)
    }
}
