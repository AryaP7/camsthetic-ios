// CompositionParams.swift
// CamstheticsEngine
// 5D spatial and geometric parameter container.

import Foundation

/// Unified spatial composition parameters extracted from a target reference or live camera frame.
public struct CompositionParams: Equatable, Hashable, Codable, Sendable {
    /// Frame aspect ratio (width / height).
    public var aspectRatio: Double

    /// Normalized bounding box of the primary subject, if detected.
    public var subjectRect: NormRect?

    /// Keypoint anchor in normalized space (e.g. eye-line midpoint for person, center for objects).
    public var subjectAnchor: NormPoint?

    /// Category of the primary subject.
    public var subjectCategory: SubjectCategory

    /// Subject-to-frame size ratio:
    /// - For people: Normalized bounding box height (h_norm)
    /// - For objects/scenes: sqrt(Area_norm)
    public var subjectRatio: Double

    /// Roll / tilt angle in degrees relative to true horizon (0° is level).
    public var tiltDegrees: Double

    /// Pitch angle in degrees (0° is horizontal eye level, + is looking down, - is looking up).
    public var pitchDegrees: Double

    /// Categorical pitch angle classification.
    public var pitchBucket: CameraPitchBucket

    /// Vertical composition height ratio in frame (0.0 = top, 1.0 = bottom, or anchor Y).
    public var heightRatio: Double

    /// Horizontal lateral composition ratio in frame (0.0 = left, 1.0 = right, or anchor X).
    public var lateralRatio: Double

    /// Multi-dimensional confidence ratings for each extracted parameter.
    public var confidences: DimensionConfidence

    public init(
        aspectRatio: Double,
        subjectRect: NormRect? = nil,
        subjectAnchor: NormPoint? = nil,
        subjectCategory: SubjectCategory = .unknown,
        subjectRatio: Double = 0.0,
        tiltDegrees: Double = 0.0,
        pitchDegrees: Double = 0.0,
        pitchBucket: CameraPitchBucket? = nil,
        heightRatio: Double = 0.5,
        lateralRatio: Double = 0.5,
        confidences: DimensionConfidence = .full
    ) {
        self.aspectRatio = aspectRatio
        self.subjectRect = subjectRect
        self.subjectAnchor = subjectAnchor ?? subjectRect?.center
        self.subjectCategory = subjectCategory
        self.subjectRatio = max(0.0, subjectRatio)
        self.tiltDegrees = tiltDegrees
        self.pitchDegrees = pitchDegrees
        self.pitchBucket = pitchBucket ?? CameraPitchBucket.bucket(forPitchDegrees: pitchDegrees)
        self.heightRatio = heightRatio
        self.lateralRatio = lateralRatio
        self.confidences = confidences
    }

    /// Whether this composition contains a detected subject.
    @inlinable
    public var hasSubject: Bool {
        subjectRect != nil && subjectRatio > 0.001
    }
}
