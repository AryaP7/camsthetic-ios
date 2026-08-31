// CoachingDimension.swift
// CamstheticsEngine
// Coaching dimensions, tolerances, priority ordering, and scoring weights.

import Foundation

/// The spatial dimensions evaluated during live coaching.
public enum CoachingDimension: String, Codable, Sendable, CaseIterable, Comparable {
    case tilt
    case lateral
    case distance
    case height
    case zoom

    /// Priority ranking: Tilt (0) > Lateral (1) > Distance (2) > Height (3) > Zoom (4).
    @inlinable
    public var priorityIndex: Int {
        switch self {
        case .tilt: return 0
        case .lateral: return 1
        case .distance: return 2
        case .height: return 3
        case .zoom: return 4
        }
    }

    @inlinable
    public static func < (lhs: CoachingDimension, rhs: CoachingDimension) -> Bool {
        lhs.priorityIndex < rhs.priorityIndex
    }

    /// Entry error tolerance threshold (1.0 * Tol).
    @inlinable
    public var entryTolerance: Double {
        switch self {
        case .tilt:
            return 2.0 // degrees
        case .lateral:
            return 0.04 // normalized frame ratio (4%)
        case .distance:
            return 0.08 // size ratio delta (e.g. 1.08x or 0.92x)
        case .height:
            return 0.12 // normalized height delta (12%)
        case .zoom:
            return 0.08
        }
    }

    /// Exit error hysteresis threshold (0.7 * Tol).
    @inlinable
    public var exitTolerance: Double {
        entryTolerance * 0.7
    }

    /// Scoring weight assigned in Gaussian match score formula.
    /// PRODUCT_SPEC.md 1.4.1: Tilt 0.18, Lateral 0.30, Distance 0.24, Height 0.13, Pitch 0.15.
    @inlinable
    public var scoringWeight: Double {
        switch self {
        case .tilt: return 0.18
        case .lateral: return 0.30
        case .distance: return 0.24
        case .height: return 0.13
        case .zoom: return 0.0
        }
    }

    /// Default normalization scale (sigma) for Gaussian scoring: s_d = exp(-(error / scale)^2).
    @inlinable
    public var scoringScale: Double {
        switch self {
        case .tilt: return 6.0 // degrees
        case .lateral: return 0.12 // normalized frame
        case .distance: return 0.24 // log ratio
        case .height: return 0.36 // normalized frame
        case .zoom: return 0.24
        }
    }
}
