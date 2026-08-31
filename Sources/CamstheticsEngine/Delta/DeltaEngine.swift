// DeltaEngine.swift
// CamstheticsEngine
// 5D spatial delta computation and confidence gating engine.

import Foundation

/// Pure mathematical engine that calculates signed discrepancies between Target and Live compositions.
public enum DeltaEngine {
    public static let epsilonRatio: Double = 1e-4

    /// Wraps an angular delta in degrees to the range `[-180.0, 180.0]`.
    @inlinable
    public static func wrapAngleDegrees(_ angle: Double) -> Double {
        var wrapped = angle.truncatingRemainder(dividingBy: 360.0)
        if wrapped > 180.0 {
            wrapped -= 360.0
        } else if wrapped < -180.0 {
            wrapped += 360.0
        }
        return wrapped
    }

    /// Computes the 5D geometric delta between Target and Live compositions.
    /// PRODUCT_SPEC.md 1.3.1:
    /// - Delta_tilt = Target_tilt - Live_tilt
    /// - Delta_lateral = Target_centerX - Live_centerX
    /// - Delta_distance = ln(Target_ratio / max(Live_ratio, eps))
    /// - Delta_height = Target_height - Live_height
    /// - Confidence Floor: Any dimension where min(Conf_target, Conf_live) < 0.35 is suppressed.
    public static func computeDelta(
        target: CompositionParams,
        live: CompositionParams
    ) -> CompositionDelta {
        // Effective element-wise min confidence
        let effConf = target.confidences.elementwiseMin(with: live.confidences)

        // 1. Tilt Delta
        let rawDeltaTilt = target.tiltDegrees - live.tiltDegrees
        let deltaTilt = wrapAngleDegrees(rawDeltaTilt)

        // 2. Lateral Delta (Target anchor X - Live anchor X)
        let targetLat = target.lateralRatio
        let liveLat = live.lateralRatio
        let deltaLateral = targetLat - liveLat

        // 3. Distance Delta (Log ratio)
        let targetRatio = max(0.0, target.subjectRatio)
        let liveRatio = max(0.0, live.subjectRatio)

        let distRatio: Double
        let deltaDist: Double

        if targetRatio < epsilonRatio && liveRatio < epsilonRatio {
            distRatio = 1.0
            deltaDist = 0.0
        } else if liveRatio < epsilonRatio {
            distRatio = targetRatio / epsilonRatio
            deltaDist = log(distRatio)
        } else if targetRatio < epsilonRatio {
            distRatio = epsilonRatio / liveRatio
            deltaDist = log(distRatio)
        } else {
            distRatio = targetRatio / liveRatio
            deltaDist = log(distRatio)
        }

        // 4. Height Delta (Target anchor Y - Live anchor Y)
        let targetH = target.heightRatio
        let liveH = live.heightRatio
        let deltaHeight = targetH - liveH

        // 5. Pitch Delta
        let rawDeltaPitch = target.pitchDegrees - live.pitchDegrees
        let deltaPitch = wrapAngleDegrees(rawDeltaPitch)

        // Confidence Suppression Check (Floor < 0.35)
        var suppressed = Set<CoachingDimension>()
        for dim in CoachingDimension.allCases {
            if effConf.isSuppressed(dimension: dim) {
                suppressed.insert(dim)
            }
        }

        // Also suppress subject-dependent dimensions if subjects are missing
        if !target.hasSubject || !live.hasSubject {
            suppressed.insert(.lateral)
            suppressed.insert(.distance)
            suppressed.insert(.height)
        }

        return CompositionDelta(
            deltaTilt: deltaTilt,
            deltaLateral: deltaLateral,
            deltaDistance: deltaDist,
            distanceRatio: distRatio,
            deltaHeight: deltaHeight,
            deltaPitch: deltaPitch,
            effectiveConfidence: effConf,
            suppressedDimensions: suppressed
        )
    }
}
