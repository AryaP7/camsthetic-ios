// MagnitudeBucket.swift
// CamstheticsEngine
// Discrete magnitude classification for visual and tactile intensity scaling.

import Foundation

/// Discrete magnitude scale indicating error severity.
public enum MagnitudeBucket: String, Codable, Sendable, CaseIterable {
    /// Within tolerance (no correction needed).
    case aligned
    /// Small deviation (fine tuning).
    case fine
    /// Moderate deviation (clear intentional movement).
    case moderate
    /// Large deviation (significant spatial repositioning).
    case coarse

    /// Classifies an error given dimension-specific thresholds.
    public static func bucket(
        error: Double,
        tolerance: Double,
        moderateThreshold: Double,
        coarseThreshold: Double
    ) -> MagnitudeBucket {
        let absErr = abs(error)
        if absErr <= tolerance {
            return .aligned
        } else if absErr <= moderateThreshold {
            return .fine
        } else if absErr <= coarseThreshold {
            return .moderate
        } else {
            return .coarse
        }
    }
}
