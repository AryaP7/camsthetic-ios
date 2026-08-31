// TierResolver.swift
// CamstheticsEngine
// Multi-frame hysteresis state machine for confidence tier resolution.

import Foundation

/// Resolves operational confidence tiers with 5-frame consecutive stability gating.
public struct TierResolver: Equatable, Sendable {
    /// Number of consecutive frames required to commit a confidence tier transition (PRODUCT_SPEC.md 1.4.2).
    public static let requiredConsecutiveFrames: Int = 5

    /// Currently active confidence tier.
    public private(set) var currentTier: ConfidenceTier

    /// Candidate tier being evaluated during transition.
    public private(set) var candidateTier: ConfidenceTier?

    /// Consecutive frame counter for candidate tier.
    public private(set) var candidateConsecutiveFrames: Int = 0

    public init(initialTier: ConfidenceTier = .full) {
        self.currentTier = initialTier
        self.candidateTier = nil
        self.candidateConsecutiveFrames = 0
    }

    /// Evaluates raw tier from Target and Live subject presence.
    /// PRODUCT_SPEC.md 1.4.2:
    /// - FULL: Live subject detected + Target subject detected.
    /// - PARTIAL: Live subject missing (dark, wall, subject out of frame).
    /// - MINIMAL: Both target and live are landscapes / scenes without subjects.
    public static func evaluateRawTier(target: CompositionParams, live: CompositionParams) -> ConfidenceTier {
        let targetHasSubject = target.hasSubject
        let liveHasSubject = live.hasSubject

        if targetHasSubject && liveHasSubject {
            return .full
        } else if targetHasSubject && !liveHasSubject {
            return .partial
        } else {
            return .minimal
        }
    }

    /// Updates the state machine with a new frame observation and returns the stable active tier.
    public mutating func update(target: CompositionParams, live: CompositionParams) -> ConfidenceTier {
        let raw = Self.evaluateRawTier(target: target, live: live)

        if raw == currentTier {
            // Raw matches current active tier: cancel any pending transition
            candidateTier = nil
            candidateConsecutiveFrames = 0
            return currentTier
        }

        // Raw differs from current tier: track candidate transition
        if candidateTier == raw {
            candidateConsecutiveFrames += 1
        } else {
            candidateTier = raw
            candidateConsecutiveFrames = 1
        }

        if candidateConsecutiveFrames >= Self.requiredConsecutiveFrames {
            // Commit transition after 5 consecutive agreeing frames
            currentTier = raw
            candidateTier = nil
            candidateConsecutiveFrames = 0
        }

        return currentTier
    }

    /// Resets the resolver to a specified initial tier.
    public mutating func reset(to tier: ConfidenceTier = .full) {
        currentTier = tier
        candidateTier = nil
        candidateConsecutiveFrames = 0
    }
}
