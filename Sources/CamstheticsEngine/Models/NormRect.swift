// NormRect.swift
// CamstheticsEngine
// Pure Swift normalized rectangle representation in [0.0, 1.0] coordinate space.

import Foundation

/// A rectangle in normalized image coordinates where `(0.0, 0.0)` is top-left and `(1.0, 1.0)` is bottom-right.
public struct NormRect: Equatable, Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public static let zero = NormRect(x: 0.0, y: 0.0, width: 0.0, height: 0.0)
    public static let unit = NormRect(x: 0.0, y: 0.0, width: 1.0, height: 1.0)

    @inlinable
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    @inlinable
    public init(center: NormPoint, width: Double, height: Double) {
        self.x = center.x - width / 2.0
        self.y = center.y - height / 2.0
        self.width = width
        self.height = height
    }

    @inlinable
    public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.x = minX
        self.y = minY
        self.width = max(0.0, maxX - minX)
        self.height = max(0.0, maxY - minY)
    }

    @inlinable
    public var minX: Double { x }

    @inlinable
    public var maxX: Double { x + width }

    @inlinable
    public var minY: Double { y }

    @inlinable
    public var maxY: Double { y + height }

    @inlinable
    public var midX: Double { x + width / 2.0 }

    @inlinable
    public var midY: Double { y + height / 2.0 }

    @inlinable
    public var center: NormPoint {
        NormPoint(x: midX, y: midY)
    }

    @inlinable
    public var area: Double {
        max(0.0, width) * max(0.0, height)
    }

    @inlinable
    public var aspectRatio: Double {
        height > 0.0 ? width / height : 0.0
    }

    @inlinable
    public func contains(_ point: NormPoint) -> Bool {
        point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
    }

    @inlinable
    public func intersection(with other: NormRect) -> NormRect? {
        let newMinX = max(self.minX, other.minX)
        let newMinY = max(self.minY, other.minY)
        let newMaxX = min(self.maxX, other.maxX)
        let newMaxY = min(self.maxY, other.maxY)

        if newMaxX >= newMinX && newMaxY >= newMinY {
            return NormRect(minX: newMinX, minY: newMinY, maxX: newMaxX, maxY: newMaxY)
        }
        return nil
    }

    @inlinable
    public func union(with other: NormRect) -> NormRect {
        let newMinX = min(self.minX, other.minX)
        let newMinY = min(self.minY, other.minY)
        let newMaxX = max(self.maxX, other.maxX)
        let newMaxY = max(self.maxY, other.maxY)
        return NormRect(minX: newMinX, minY: newMinY, maxX: newMaxX, maxY: newMaxY)
    }

    @inlinable
    public func clamped(to bounds: NormRect = .unit) -> NormRect {
        let cMinX = min(max(minX, bounds.minX), bounds.maxX)
        let cMinY = min(max(minY, bounds.minY), bounds.maxY)
        let cMaxX = min(max(maxX, bounds.minX), bounds.maxX)
        let cMaxY = min(max(maxY, bounds.minY), bounds.maxY)
        return NormRect(minX: cMinX, minY: cMinY, maxX: cMaxX, maxY: cMaxY)
    }
}
