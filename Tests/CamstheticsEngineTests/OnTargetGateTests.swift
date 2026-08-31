// OnTargetGateTests.swift
// CamstheticsEngineTests

import XCTest
@testable import CamstheticsEngine

final class OnTargetGateTests: XCTestCase {
    func testOnTargetScoreThreshold() {
        var gate = OnTargetGate()

        // Score 84% -> Not on target
        let state84 = gate.update(score: 84, tier: .full, timestamp: 0.0)
        XCTAssertFalse(state84.isOnTarget)

        // Score 85% -> On target!
        let state85 = gate.update(score: 85, tier: .full, timestamp: 0.1)
        XCTAssertTrue(state85.isOnTarget)

        // Score 90% -> On target!
        let state90 = gate.update(score: 90, tier: .full, timestamp: 0.2)
        XCTAssertTrue(state90.isOnTarget)
    }

    func testAutoCaptureSustainedTimer() {
        var gate = OnTargetGate()

        // t = 0.0: Score 88% enters On-Target
        let s0 = gate.update(score: 88, tier: .full, timestamp: 0.0, autoCaptureEnabled: true)
        XCTAssertTrue(s0.isOnTarget)
        XCTAssertEqual(s0.autoCaptureProgress, 0.0, accuracy: 1e-4)
        XCTAssertFalse(s0.shouldTriggerAutoCapture)

        // t = 0.30 (300ms elapsed = 50% progress)
        let s300 = gate.update(score: 88, tier: .full, timestamp: 0.30, autoCaptureEnabled: true)
        XCTAssertTrue(s300.isOnTarget)
        XCTAssertEqual(s300.autoCaptureProgress, 0.50, accuracy: 1e-4)
        XCTAssertFalse(s300.shouldTriggerAutoCapture)

        // t = 0.60 (600ms elapsed = 100% progress -> trigger shutter!)
        let s600 = gate.update(score: 88, tier: .full, timestamp: 0.60, autoCaptureEnabled: true)
        XCTAssertTrue(s600.isOnTarget)
        XCTAssertEqual(s600.autoCaptureProgress, 1.00, accuracy: 1e-4)
        XCTAssertTrue(s600.shouldTriggerAutoCapture)
    }

    func testAutoCaptureCooldown() {
        var gate = OnTargetGate()

        // Trigger capture at t = 0.60
        _ = gate.update(score: 88, tier: .full, timestamp: 0.0, autoCaptureEnabled: true)
        let fired = gate.update(score: 88, tier: .full, timestamp: 0.60, autoCaptureEnabled: true)
        XCTAssertTrue(fired.shouldTriggerAutoCapture)

        // At t = 2.0 (1.4s after capture, within 4.0s cooldown): should NOT trigger
        let duringCooldown = gate.update(score: 88, tier: .full, timestamp: 2.0, autoCaptureEnabled: true)
        XCTAssertFalse(duringCooldown.shouldTriggerAutoCapture)

        // At t = 5.0 (4.4s after capture, cooldown passed & sustained): should trigger again
        _ = gate.update(score: 88, tier: .full, timestamp: 4.4, autoCaptureEnabled: true)
        let secondFired = gate.update(score: 88, tier: .full, timestamp: 5.0, autoCaptureEnabled: true)
        XCTAssertTrue(secondFired.shouldTriggerAutoCapture)
    }

    func testPartialTierCannotAchieveOnTarget() {
        var gate = OnTargetGate()

        // Even with score 85% in PARTIAL, tier is not eligible
        let state = gate.update(score: 85, tier: .partial, timestamp: 1.0, autoCaptureEnabled: true)
        XCTAssertFalse(state.isOnTarget)
        XCTAssertFalse(state.shouldTriggerAutoCapture)
    }
}
