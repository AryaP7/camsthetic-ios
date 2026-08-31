// EdgeCaseTests.swift
// CamstheticsEngineTests

import XCTest
@testable import CamstheticsEngine

final class EdgeCaseTests: XCTestCase {
    func testZeroAndNearZeroSubjectRatios() {
        let zeroRatioTarget = CompositionParams(aspectRatio: 1.0, subjectRatio: 0.0)
        let zeroRatioLive = CompositionParams(aspectRatio: 1.0, subjectRatio: 0.0)

        let delta = DeltaEngine.computeDelta(target: zeroRatioTarget, live: zeroRatioLive)
        XCTAssertFalse(delta.deltaDistance.isNaN)
        XCTAssertFalse(delta.deltaDistance.isInfinite)
        XCTAssertEqual(delta.distanceRatio, 1.0, accuracy: 1e-6)
        XCTAssertEqual(delta.deltaDistance, 0.0, accuracy: 1e-6)

        // Near-zero ratio (1e-6)
        let tinyTarget = CompositionParams(aspectRatio: 1.0, subjectRatio: 1e-6)
        let tinyLive = CompositionParams(aspectRatio: 1.0, subjectRatio: 0.5)
        let tinyDelta = DeltaEngine.computeDelta(target: tinyTarget, live: tinyLive)
        XCTAssertFalse(tinyDelta.deltaDistance.isNaN)
        XCTAssertFalse(tinyDelta.deltaDistance.isInfinite)
    }

    func testNormRectEdgeCases() {
        // Zero rect
        XCTAssertEqual(NormRect.zero.area, 0.0)
        XCTAssertEqual(NormRect.zero.aspectRatio, 0.0)

        // Disjoint rect intersection
        let r1 = NormRect(x: 0.0, y: 0.0, width: 0.2, height: 0.2)
        let r2 = NormRect(x: 0.5, y: 0.5, width: 0.2, height: 0.2)
        XCTAssertNil(r1.intersection(with: r2))

        // Overlapping intersection
        let r3 = NormRect(x: 0.1, y: 0.1, width: 0.3, height: 0.3)
        guard let inter = r1.intersection(with: r3) else {
            XCTFail("Intersection should not be nil")
            return
        }
        XCTAssertEqual(inter.x, 0.1, accuracy: 1e-6)
        XCTAssertEqual(inter.y, 0.1, accuracy: 1e-6)
        XCTAssertEqual(inter.width, 0.1, accuracy: 1e-6)
        XCTAssertEqual(inter.height, 0.1, accuracy: 1e-6)
    }

    func testPointClamping() {
        let outOfBounds = NormPoint(x: -0.5, y: 1.5)
        let clamped = outOfBounds.clamped()
        XCTAssertEqual(clamped.x, 0.0)
        XCTAssertEqual(clamped.y, 1.0)
    }

    func testPitchBucketCategorization() {
        XCTAssertEqual(CameraPitchBucket.bucket(forPitchDegrees: 70.0), .overhead)
        XCTAssertEqual(CameraPitchBucket.bucket(forPitchDegrees: 30.0), .highAngle)
        XCTAssertEqual(CameraPitchBucket.bucket(forPitchDegrees: 0.0), .eyeLevel)
        XCTAssertEqual(CameraPitchBucket.bucket(forPitchDegrees: -25.0), .lowAngle)
    }
}
