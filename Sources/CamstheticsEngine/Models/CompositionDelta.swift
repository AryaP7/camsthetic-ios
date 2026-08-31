// CompositionDelta.swift
// CamstheticsEngine
// 5D signed spatial discrepancies between Target and Live compositions.

import Foundation

/// 5D signed geometric differences calculated between Target and Live observations.
public struct CompositionDelta: Equatable, Hashable, Codable, Sendable {
    /// Delta tilt: Target_tilt - Live_tilt (degrees).
    public var deltaTilt: Double

    /// Delta lateral: Target_centerX - Live_centerX (normalized frame coordinate).
    public var deltaLateral: Double

    /// Delta distance: ln(Target_ratio / max(Live_ratio, eps)).
    public var deltaDistance: Double

    /// Raw ratio of Target subject size to Live subject size (Target_ratio / Live_ratio).
    public var distanceRatio: Double

    /// Delta height: Target_height - Live_height (normalized frame coordinate).
    public var deltaHeight: Double

    /// Delta pitch: Target_pitch - Live_pitch (degrees).
    public var deltaPitch: Double

    /// Element-wise minimum confidence between Target and Live observations.
    public var effectiveConfidence: DimensionConfidence

    /// Set of dimensions that are suppressed due to low confidence (< 0.35).
    public var suppressedDimensions: Set<CoachingDimension>

    public init(
        deltaTilt: Double,
        deltaLateral: Double,
        deltaDistance: Double,
        distanceRatio: Double,
        deltaHeight: Double,
        deltaPitch: Double,
        effectiveConfidence: DimensionConfidence,
        suppressedDimensions: Set<CoachingDimension> = []
    ) {
        self.deltaTilt = deltaTilt
        self.deltaLateral = deltaLateral
        self.deltaDistance = deltaDistance
        self.distanceRatio = distanceRatio
        self.deltaHeight = deltaHeight
        self.deltaPitch = deltaPitch
        self.effectiveConfidence = effectiveConfidence
        self.suppressedDimensions = suppressedDimensions
    }

    /// Checks if a dimension is suppressed.
    @inlinable
    public func isSuppressed(_ dimension: CoachingDimension) -> Bool {
        suppressedDimensions.contains(dimension)
    }
}
