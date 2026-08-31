// SubjectSelector.swift
// CamstheticsEngine
// Primary subject arbitration with sticky lock tracking.

import Foundation

/// A detected subject candidate considered during primary subject arbitration.
public struct SubjectCandidate: Equatable, Hashable, Identifiable, Sendable {
    public var id: String
    public var rect: NormRect
    public var category: SubjectCategory
    public var confidence: Double
    public var anchor: NormPoint?

    public init(
        id: String = UUID().uuidString,
        rect: NormRect,
        category: SubjectCategory = .person,
        confidence: Double = 1.0,
        anchor: NormPoint? = nil
    ) {
        self.id = id
        self.rect = rect
        self.category = category
        self.confidence = min(max(0.0, confidence), 1.0)
        self.anchor = anchor ?? rect.center
    }
}

/// State machine for primary subject arbitration with sticky lock stability.
public struct SubjectSelector: Equatable, Sendable {
    /// Threshold score difference required for a challenger to steal focus (PRODUCT_SPEC.md 1.2.2).
    public static let challengerDeltaThreshold: Double = 0.15

    /// Required consecutive frames with challenger exceeding threshold to switch focus.
    public static let requiredChallengerFrames: Int = 4

    /// ID of currently locked primary subject.
    public private(set) var activeSubjectId: String?

    /// ID of current challenger subject.
    public private(set) var challengerId: String?

    /// Consecutive frame count for current challenger.
    public private(set) var challengerConsecutiveFrames: Int = 0

    public init() {}

    /// Computes static arbitration score for a single candidate.
    /// PRODUCT_SPEC.md 1.2.2: Score = 0.45 * AreaNorm + 0.25 * CategoryWeight + 0.20 * Centrality + 0.10 * Confidence.
    public static func scoreCandidate(_ candidate: SubjectCandidate) -> Double {
        let areaNorm = min(1.0, max(0.0, candidate.rect.area / 0.50))
        let catWeight = candidate.category.priorityWeight
        let distFromCenter = candidate.rect.center.distance(to: NormPoint(x: 0.5, y: 0.5))
        let centrality = max(0.0, 1.0 - (distFromCenter / 0.7071))
        let conf = candidate.confidence

        return 0.45 * areaNorm + 0.25 * catWeight + 0.20 * centrality + 0.10 * conf
    }

    /// Evaluates a list of candidates and returns the selected primary subject, updating sticky lock state.
    public mutating func update(candidates: [SubjectCandidate]) -> SubjectCandidate? {
        guard !candidates.isEmpty else {
            activeSubjectId = nil
            challengerId = nil
            challengerConsecutiveFrames = 0
            return nil
        }

        // Score each candidate
        let scored = candidates.map { (candidate: $0, score: Self.scoreCandidate($0)) }
        guard let highest = scored.max(by: { $0.score < $1.score }) else {
            return nil
        }

        // If no active subject currently, immediately lock to highest
        guard let currentId = activeSubjectId,
              let currentMatch = scored.first(where: { $0.candidate.id == currentId }) else {
            activeSubjectId = highest.candidate.id
            challengerId = nil
            challengerConsecutiveFrames = 0
            return highest.candidate
        }

        // Check if highest is the currently locked subject
        if highest.candidate.id == currentId {
            challengerId = nil
            challengerConsecutiveFrames = 0
            return currentMatch.candidate
        }

        // Challenger detected: check if delta threshold (>= 0.15) is satisfied
        let delta = highest.score - currentMatch.score
        if delta >= Self.challengerDeltaThreshold {
            if challengerId == highest.candidate.id {
                challengerConsecutiveFrames += 1
            } else {
                challengerId = highest.candidate.id
                challengerConsecutiveFrames = 1
            }

            if challengerConsecutiveFrames >= Self.requiredChallengerFrames {
                // Challenger wins sticky lock
                activeSubjectId = highest.candidate.id
                challengerId = nil
                challengerConsecutiveFrames = 0
                return highest.candidate
            }
        } else {
            challengerId = nil
            challengerConsecutiveFrames = 0
        }

        // Retain currently locked subject
        return currentMatch.candidate
    }

    /// Resets sticky lock state.
    public mutating func reset() {
        activeSubjectId = nil
        challengerId = nil
        challengerConsecutiveFrames = 0
    }
}
