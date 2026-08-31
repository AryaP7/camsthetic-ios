// ConfidenceTier.swift
// CamstheticsEngine
// Coaching system confidence tiers and score limits.

import Foundation

/// Operational confidence tiers determining active guidance dimensions and score caps.
public enum ConfidenceTier: String, Codable, Sendable, CaseIterable {
    /// Live subject detected and Target subject detected. All 5 dimensions active. Score 0–100.
    case full

    /// Live subject missing while target has a subject. Score capped at 60.
    case partial

    /// Both target and live are landscapes / scenes without subjects. Score capped at 85.
    case minimal

    /// Maximum achievable match score under this confidence tier.
    @inlinable
    public var maxScoreCap: Int {
        switch self {
        case .full:
            return 100
        case .partial:
            return 60
        case .minimal:
            return 85
        }
    }

    /// Whether On-Target lock (>=85%) is achievable in this tier.
    @inlinable
    public var canAchieveOnTarget: Bool {
        switch self {
        case .full:
            return true
        case .partial:
            return false
        case .minimal:
            return true
        }
    }
}
