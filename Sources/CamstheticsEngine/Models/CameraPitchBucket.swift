// CameraPitchBucket.swift
// CamstheticsEngine
// Categorical classification of vertical camera pitch angles.

import Foundation

/// Discrete vertical perspective orientation of the camera.
public enum CameraPitchBucket: String, Codable, Sendable, CaseIterable {
    case eyeLevel
    case lowAngle
    case highAngle
    case overhead

    /// Classifies continuous pitch degrees into discrete perspective buckets.
    /// Pitch angle in degrees: 0° is horizontal eye level, positive is looking downward, negative is looking upward.
    public static func bucket(forPitchDegrees pitch: Double) -> CameraPitchBucket {
        if pitch > 55.0 {
            return .overhead
        } else if pitch > 15.0 {
            return .highAngle
        } else if pitch < -15.0 {
            return .lowAngle
        } else {
            return .eyeLevel
        }
    }
}
