// DimensionConfidence.swift
// CamstheticsEngine
// Multi-dimensional confidence container and suppression logic.

import Foundation

/// Per-dimension confidence values ranging from 0.0 (unconfident) to 1.0 (fully confident).
public struct DimensionConfidence: Equatable, Hashable, Codable, Sendable {
    public var tilt: Double
    public var lateral: Double
    public var distance: Double
    public var height: Double
    public var pitch: Double

    /// Confidence floor threshold below which coaching cues are suppressed.
    /// PRODUCT_SPEC.md 1.3.1: Any dimension where min(Conf_target, Conf_live) < 0.35 is suppressed.
    public static let confidenceFloor: Double = 0.35

    public static let full = DimensionConfidence(
        tilt: 1.0,
        lateral: 1.0,
        distance: 1.0,
        height: 1.0,
        pitch: 1.0
    )

    public static let zero = DimensionConfidence(
        tilt: 0.0,
        lateral: 0.0,
        distance: 0.0,
        height: 0.0,
        pitch: 0.0
    )

    public init(
        tilt: Double = 1.0,
        lateral: Double = 1.0,
        distance: Double = 1.0,
        height: Double = 1.0,
        pitch: Double = 1.0
    ) {
        self.tilt = max(0.0, min(1.0, tilt))
        self.lateral = max(0.0, min(1.0, lateral))
        self.distance = max(0.0, min(1.0, distance))
        self.height = max(0.0, min(1.0, height))
        self.pitch = max(0.0, min(1.0, pitch))
    }

    /// Retrieves confidence for a specific coaching dimension.
    @inlinable
    public func confidence(for dimension: CoachingDimension) -> Double {
        switch dimension {
        case .tilt: return tilt
        case .lateral: return lateral
        case .distance: return distance
        case .height: return height
        case .zoom: return distance
        }
    }

    /// Computes the element-wise minimum confidence between two sets of observations.
    public func elementwiseMin(with other: DimensionConfidence) -> DimensionConfidence {
        DimensionConfidence(
            tilt: min(self.tilt, other.tilt),
            lateral: min(self.lateral, other.lateral),
            distance: min(self.distance, other.distance),
            height: min(self.height, other.height),
            pitch: min(self.pitch, other.pitch)
        )
    }

    /// Checks whether a given dimension is suppressed due to confidence dropping below the floor.
    @inlinable
    public func isSuppressed(dimension: CoachingDimension) -> Bool {
        confidence(for: dimension) < Self.confidenceFloor
    }
}
