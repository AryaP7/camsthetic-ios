// TierResolverTests.swift
// CamstheticsEngineTests

import XCTest
@testable import CamstheticsEngine

final class TierResolverTests: XCTestCase {
    func testRawTierEvaluation() {
        let subject = NormRect(center: .center, width: 0.3, height: 0.5)

        let targetWithSubject = CompositionParams(aspectRatio: 1.0, subjectRect: subject, subjectRatio: 0.5)
        let liveWithSubject = CompositionParams(aspectRatio: 1.0, subjectRect: subject, subjectRatio: 0.5)
        let targetNoSubject = CompositionParams(aspectRatio: 1.0, subjectRect: nil, subjectRatio: 0.0)
        let liveNoSubject = CompositionParams(aspectRatio: 1.0, subjectRect: nil, subjectRatio: 0.0)

        // Target + Live -> FULL
        XCTAssertEqual(TierResolver.evaluateRawTier(target: targetWithSubject, live: liveWithSubject), .full)

        // Target + No Live -> PARTIAL
        XCTAssertEqual(TierResolver.evaluateRawTier(target: targetWithSubject, live: liveNoSubject), .partial)

        // No Target + No Live -> MINIMAL
        XCTAssertEqual(TierResolver.evaluateRawTier(target: targetNoSubject, live: liveNoSubject), .minimal)
    }

    func testFiveFrameHysteresisForTransition() {
        var resolver = TierResolver(initialTier: .full)
        let subject = NormRect(center: .center, width: 0.3, height: 0.5)

        let target = CompositionParams(aspectRatio: 1.0, subjectRect: subject, subjectRatio: 0.5)
        let liveMissing = CompositionParams(aspectRatio: 1.0, subjectRect: nil, subjectRatio: 0.0)

        // Frames 1-4: Live subject drops out, but resolver holds FULL
        for frame in 1...4 {
            let tier = resolver.update(target: target, live: liveMissing)
            XCTAssertEqual(tier, .full, "Frame \(frame) should remain FULL due to hysteresis")
        }

        // Frame 5: Sustained dropout -> commits to PARTIAL
        let tier5 = resolver.update(target: target, live: liveMissing)
        XCTAssertEqual(tier5, .partial, "Frame 5 should commit transition to PARTIAL")
    }

    func testTransientDropoutRecovery() {
        var resolver = TierResolver(initialTier: .full)
        let subject = NormRect(center: .center, width: 0.3, height: 0.5)

        let target = CompositionParams(aspectRatio: 1.0, subjectRect: subject, subjectRatio: 0.5)
        let livePresent = CompositionParams(aspectRatio: 1.0, subjectRect: subject, subjectRatio: 0.5)
        let liveMissing = CompositionParams(aspectRatio: 1.0, subjectRect: nil, subjectRatio: 0.0)

        // 3 frames of momentary dropout
        _ = resolver.update(target: target, live: liveMissing)
        _ = resolver.update(target: target, live: liveMissing)
        _ = resolver.update(target: target, live: liveMissing)

        // Frame 4: Subject reappears!
        let recoveredTier = resolver.update(target: target, live: livePresent)
        XCTAssertEqual(recoveredTier, .full)

        // Dropout counter should have reset
        XCTAssertNil(resolver.candidateTier)
        XCTAssertEqual(resolver.candidateConsecutiveFrames, 0)
    }
}
