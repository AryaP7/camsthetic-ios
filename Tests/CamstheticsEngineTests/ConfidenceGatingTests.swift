// ConfidenceGatingTests.swift
// CamstheticsEngineTests

import XCTest
@testable import CamstheticsEngine

final class ConfidenceGatingTests: XCTestCase {
    func testConfidenceFloorSuppression() {
        let subject = NormRect(center: .center, width: 0.3, height: 0.5)

        // Tilt confidence below 0.35 floor (0.30)
        let lowTiltConf = DimensionConfidence(tilt: 0.30, lateral: 1.0, distance: 1.0, height: 1.0, pitch: 1.0)
        let target = CompositionParams(
            aspectRatio: 1.0,
            subjectRect: subject,
            subjectRatio: 0.5,
            tiltDegrees: 10.0, // Large tilt error
            confidences: lowTiltConf
        )
        let live = CompositionParams(
            aspectRatio: 1.0,
            subjectRect: subject,
            subjectRatio: 0.5,
            tiltDegrees: 0.0,
            confidences: .full
        )

        let delta = DeltaEngine.computeDelta(target: target, live: live)
        XCTAssertTrue(delta.isSuppressed(.tilt))

        let candidates = PriorityMapper.candidateInstructions(delta: delta, target: target, live: live)
        XCTAssertFalse(candidates.contains(where: { $0.dimension == .tilt }))
    }

    func testMissingSubjectSuppressesSubjectDimensions() {
        // Target has subject, Live does not
        let subject = NormRect(center: .center, width: 0.3, height: 0.5)
        let target = CompositionParams(
            aspectRatio: 1.0,
            subjectRect: subject,
            subjectRatio: 0.5,
            heightRatio: 0.7,
            lateralRatio: 0.8
        )
        let live = CompositionParams(
            aspectRatio: 1.0,
            subjectRect: nil,
            subjectRatio: 0.0
        )

        let delta = DeltaEngine.computeDelta(target: target, live: live)
        XCTAssertTrue(delta.isSuppressed(.lateral))
        XCTAssertTrue(delta.isSuppressed(.distance))
        XCTAssertTrue(delta.isSuppressed(.height))
    }

    func testPartialTierSurfacesFindSubject() {
        var engine = CoachingEngine()
        let subject = NormRect(center: .center, width: 0.3, height: 0.5)
        let target = CompositionParams(aspectRatio: 1.0, subjectRect: subject, subjectRatio: 0.5)
        let live = CompositionParams(aspectRatio: 1.0, subjectRect: nil, subjectRatio: 0.0)

        // Process 5 frames to settle tier resolver into PARTIAL
        var output: CoachingOutput!
        for i in 0..<5 {
            output = engine.processFrame(
                target: target,
                live: live,
                timestamp: Double(i) * 0.1
            )
        }

        XCTAssertEqual(output.tier, .partial)
        XCTAssertEqual(output.surfacedInstructions.first, .findSubject)
        XCTAssertLessThanOrEqual(output.score, 60)
    }

    func testPartialTierCombinesTiltAndFindSubject() {
        var engine = CoachingEngine()
        let subject = NormRect(center: .center, width: 0.3, height: 0.5)
        // Target has subject & tilt 5°
        let target = CompositionParams(aspectRatio: 1.0, subjectRect: subject, subjectRatio: 0.5, tiltDegrees: 5.0)
        // Live missing subject & tilt 0°
        let live = CompositionParams(aspectRatio: 1.0, subjectRect: nil, subjectRatio: 0.0, tiltDegrees: 0.0)

        // Process 5 frames to settle tier resolver into PARTIAL and tilt into active
        var output: CoachingOutput!
        for i in 0..<5 {
            output = engine.processFrame(
                target: target,
                live: live,
                timestamp: Double(i) * 0.1
            )
        }

        XCTAssertEqual(output.tier, .partial)
        XCTAssertEqual(output.surfacedInstructions.count, 2)
        XCTAssertEqual(output.surfacedInstructions[0], .rotateClockwise(degrees: 5))
        XCTAssertEqual(output.surfacedInstructions[1], .findSubject)
    }
}
