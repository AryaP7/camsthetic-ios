// NormPoint.swift
// CamstheticsEngine
// Pure Swift normalized 2D point representation in [0.0, 1.0] coordinate space.

import Foundation

/// A point in normalized image coordinates where `(0.0, 0.0)` is top-left and `(1.0, 1.0)` is bottom-right.
public struct NormPoint: Equatable, Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double

    public static let zero = NormPoint(x: 0.0, y: 0.0)
    public static let center = NormPoint(x: 0.5, y: 0.5)

    @inlinable
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    /// Calculates Euclidean distance to another normalized point.
    @inlinable
    public func distance(to other: NormPoint) -> Double {
        let dx = self.x - other.x
        let dy = self.y - other.y
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Clamps coordinates to the specified range (default `0.0...1.0`).
    @inlinable
    public func clamped(to range: ClosedRange<Double> = 0.0...1.0) -> NormPoint {
        NormPoint(
            x: min(max(x, range.lowerBound), range.upperBound),
            y: min(max(y, range.lowerBound), range.upperBound)
        )
    }
}
