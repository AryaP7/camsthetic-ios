// SubjectCategory.swift
// CamstheticsEngine
// Categorization and scoring weights for detected subjects.

import Foundation

/// Primary classification of detected visual subjects.
public enum SubjectCategory: String, Codable, Sendable, CaseIterable {
    case person
    case animal
    case object
    case scene
    case unknown

    /// Category weighting factor applied during primary subject arbitration.
    /// Derived from PRODUCT_SPEC.md 1.2.2: Person 1.0, Animals 0.9, Objects 0.4.
    @inlinable
    public var priorityWeight: Double {
        switch self {
        case .person:
            return 1.0
        case .animal:
            return 0.9
        case .object:
            return 0.4
        case .scene:
            return 0.1
        case .unknown:
            return 0.1
        }
    }
}
