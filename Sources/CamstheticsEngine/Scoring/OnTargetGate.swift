// OnTargetGate.swift
// CamstheticsEngine
// Evaluates On-Target threshold locks and auto-capture countdown gating.

import Foundation

/// State output from On-Target evaluation.
public struct OnTargetState: Equatable, Sendable {
    /// Whether current framing is locked On-Target (score >= 85% and tier is eligible).
    public var isOnTarget: Bool

    /// Progress of the sustained 600ms hold timer (0.0 to 1.0) for visual countdown ring.
    public var autoCaptureProgress: Double

    /// Whether auto-capture shutter trigger should fire at this instant.
    public var shouldTriggerAutoCapture: Bool

    public init(
        isOnTarget: Bool,
        autoCaptureProgress: Double = 0.0,
        shouldTriggerAutoCapture: Bool = false
    ) {
        self.isOnTarget = isOnTarget
        self.autoCaptureProgress = autoCaptureProgress
        self.shouldTriggerAutoCapture = shouldTriggerAutoCapture
    }
}

/// Evaluator tracking the sustained 85% On-Target condition and auto-capture triggers.
public struct OnTargetGate: Equatable, Sendable {
    /// Score threshold required to achieve On-Target framing (PRODUCT_SPEC.md 1.4.1).
    public static let onTargetScoreThreshold: Int = 85

    /// Required continuous duration (in seconds) score >= 85% before auto-capture triggers (PRODUCT_SPEC.md 1.5.2).
    public static let requiredSustainedDuration: TimeInterval = 0.60 // 600ms

    /// Minimum cooldown duration (in seconds) between consecutive auto-captures.
    public static let autoCaptureCooldown: TimeInterval = 4.00

    private var onTargetStartTime: TimeInterval?
    private var lastAutoCaptureTime: TimeInterval?

    public init() {}

    /// Evaluates current score and tier, returning updated On-Target state.
    public mutating func update(
        score: Int,
        tier: ConfidenceTier,
        timestamp: TimeInterval,
        autoCaptureEnabled: Bool = false
    ) -> OnTargetState {
        let isEligible = tier.canAchieveOnTarget && score >= Self.onTargetScoreThreshold

        if !isEligible {
            onTargetStartTime = nil
            return OnTargetState(isOnTarget: false, autoCaptureProgress: 0.0, shouldTriggerAutoCapture: false)
        }

        // On-Target is achieved
        let startTime = onTargetStartTime ?? timestamp
        if onTargetStartTime == nil {
            onTargetStartTime = startTime
        }

        let sustainedDuration = timestamp - startTime
        let progress = min(1.0, max(0.0, sustainedDuration / Self.requiredSustainedDuration))

        var shouldTrigger = false

        if autoCaptureEnabled {
            let cooldownElapsed: Bool
            if let last = lastAutoCaptureTime {
                cooldownElapsed = (timestamp - last) >= Self.autoCaptureCooldown
            } else {
                cooldownElapsed = true
            }

            if sustainedDuration >= Self.requiredSustainedDuration && cooldownElapsed {
                shouldTrigger = true
                lastAutoCaptureTime = timestamp
                // Reset start time so it doesn't immediately re-trigger without continuous re-entry
                onTargetStartTime = timestamp
            }
        }

        return OnTargetState(
            isOnTarget: true,
            autoCaptureProgress: progress,
            shouldTriggerAutoCapture: shouldTrigger
        )
    }

    /// Resets gate state.
    public mutating func reset() {
        onTargetStartTime = nil
        lastAutoCaptureTime = nil
    }
}
