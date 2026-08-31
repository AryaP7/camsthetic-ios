// CoachingEngineTests.swift
// CamstheticsEngineTests

import XCTest
@testable import CamstheticsEngine

final class CoachingEngineTests: XCTestCase {
    func testEndToEndCoachingWorkflow() {
        var engine = CoachingEngine()

        let targetSubject = NormRect(center: NormPoint(x: 0.5, y: 0.5), width: 0.4, height: 0.6)
        let target = CompositionParams(
            aspectRatio: 4.0 / 5.0, // 0.8
            subjectRect: targetSubject,
            subjectCategory: .person,
            subjectRatio: 0.6,
            tiltDegrees: 0.0,
            pitchDegrees: 0.0,
            heightRatio: 0.5,
            lateralRatio: 0.5
        )

        // Frame 1-3: Live camera is tilted (-6°) and offset (lateral = 0.35)
        let liveSubjectFar = NormRect(center: NormPoint(x: 0.35, y: 0.5), width: 0.3, height: 0.4)
        let liveFar = CompositionParams(
            aspectRatio: 16.0 / 9.0, // 1.777...
            subjectRect: liveSubjectFar,
            subjectCategory: .person,
            subjectRatio: 0.4,
            tiltDegrees: -6.0,
            pitchDegrees: 0.0,
            heightRatio: 0.5,
            lateralRatio: 0.35
        )

        _ = engine.processFrame(target: target, live: liveFar, timestamp: 0.0)
        _ = engine.processFrame(target: target, live: liveFar, timestamp: 0.1)
        let out3 = engine.processFrame(target: target, live: liveFar, timestamp: 0.2)

        XCTAssertEqual(out3.tier, .full)
        XCTAssertFalse(out3.isOnTarget)
        XCTAssertLessThan(out3.score, 85)

        // Strict priority check: Tilt should be instruction 0
        XCTAssertTrue(out3.surfacedInstructions.contains(where: { $0.dimension == .tilt }))
        XCTAssertEqual(out3.surfacedInstructions.first, .rotateClockwise(degrees: 6))

        // Now user follows instructions and levels the phone and centers subject
        let liveSubjectAligned = NormRect(center: NormPoint(x: 0.5, y: 0.5), width: 0.4, height: 0.6)
        let liveAligned = CompositionParams(
            aspectRatio: 4.0 / 5.0,
            subjectRect: liveSubjectAligned,
            subjectCategory: .person,
            subjectRatio: 0.6,
            tiltDegrees: 0.0,
            pitchDegrees: 0.0,
            heightRatio: 0.5,
            lateralRatio: 0.5
        )

        // Let exit hysteresis and dwell time clear instructions
        var outFinal: CoachingOutput!
        for i in 1...10 {
            outFinal = engine.processFrame(
                target: target,
                live: liveAligned,
                timestamp: 1.0 + Double(i) * 0.1,
                autoCaptureEnabled: true
            )
        }

        XCTAssertEqual(outFinal.tier, .full)
        XCTAssertEqual(outFinal.score, 100)
        XCTAssertTrue(outFinal.isOnTarget)
        XCTAssertTrue(outFinal.surfacedInstructions.isEmpty)
    }

    func testResetClearsInternalState() {
        var engine = CoachingEngine()
        let target = CompositionParams(aspectRatio: 1.0, tiltDegrees: 10.0)
        let live = CompositionParams(aspectRatio: 1.0, tiltDegrees: 0.0)

        // Settle active
        _ = engine.processFrame(target: target, live: live, timestamp: 0.0)
        _ = engine.processFrame(target: target, live: live, timestamp: 0.1)
        let out = engine.processFrame(target: target, live: live, timestamp: 0.2)
        XCTAssertFalse(out.surfacedInstructions.isEmpty)

        // Reset
        engine.reset()

        // After reset, 1 frame should not have surfaced cues due to 3-frame entry requirement
        let postReset = engine.processFrame(target: target, live: live, timestamp: 1.0)
        XCTAssertTrue(postReset.surfacedInstructions.isEmpty)
    }
}
