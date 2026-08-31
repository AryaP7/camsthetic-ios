// PriorityMapperTests.swift
// CamstheticsEngineTests

import XCTest
@testable import CamstheticsEngine

final class PriorityMapperTests: XCTestCase {
    func testStrictPriorityOrdering() {
        let instructions: [CoachingInstruction] = [
            .raisePhone,                     // Height (Priority 3)
            .stepRight,                      // Lateral (Priority 1)
            .rotateClockwise(degrees: 5),    // Tilt (Priority 0)
            .moveCloser                      // Distance (Priority 2)
        ]

        let prioritized = PriorityMapper.prioritize(instructions)

        XCTAssertEqual(prioritized.count, 4)
        XCTAssertEqual(prioritized[0], .rotateClockwise(degrees: 5))
        XCTAssertEqual(prioritized[1], .stepRight)
        XCTAssertEqual(prioritized[2], .moveCloser)
        XCTAssertEqual(prioritized[3], .raisePhone)
    }

    func testTopTwoSurfacingCap() {
        let instructions: [CoachingInstruction] = [
            .rotateClockwise(degrees: 5),
            .stepRight,
            .moveCloser,
            .raisePhone
        ]

        let surfaced = PriorityMapper.surfaceTopInstructions(instructions, maxCount: 2)

        XCTAssertEqual(surfaced.count, 2)
        XCTAssertEqual(surfaced[0], .rotateClockwise(degrees: 5))
        XCTAssertEqual(surfaced[1], .stepRight)
    }

    func testPanDisambiguationRule() {
        let subject = NormRect(center: .center, width: 0.3, height: 0.5)

        // 1. Both size and height match within tolerance (ratio delta <= 0.08, height delta <= 0.12)
        let targetMatch = CompositionParams(
            aspectRatio: 1.0,
            subjectRect: subject,
            subjectRatio: 0.50,
            heightRatio: 0.50,
            lateralRatio: 0.60
        )
        let liveMatch = CompositionParams(
            aspectRatio: 1.0,
            subjectRect: subject,
            subjectRatio: 0.52, // Delta 0.02 <= 0.08
            heightRatio: 0.54, // Delta 0.04 <= 0.12
            lateralRatio: 0.50
        )

        let deltaMatch = DeltaEngine.computeDelta(target: targetMatch, live: liveMatch)
        let instrMatch = PriorityMapper.candidateInstructions(delta: deltaMatch, target: targetMatch, live: liveMatch)
        XCTAssertEqual(instrMatch.first, .panRight)

        // 2. Size differs > 0.08 -> Step
        let targetSizeDiff = CompositionParams(
            aspectRatio: 1.0,
            subjectRect: subject,
            subjectRatio: 0.65, // Delta 0.15 > 0.08
            heightRatio: 0.50,
            lateralRatio: 0.60
        )
        let deltaSizeDiff = DeltaEngine.computeDelta(target: targetSizeDiff, live: liveMatch)
        let instrSizeDiff = PriorityMapper.candidateInstructions(delta: deltaSizeDiff, target: targetSizeDiff, live: liveMatch)
        XCTAssertEqual(instrSizeDiff.first(where: { $0.dimension == .lateral }), .stepRight)
    }
}
