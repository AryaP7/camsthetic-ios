// GaussianMatchScorer.swift
// CamstheticsEngine
// Pure Swift monotonic Gaussian match scoring engine.

import Foundation

/// Gaussian match scorer computing normalized match percentage (0–100) across 5 spatial dimensions.
public enum GaussianMatchScorer {
    /// Dimension error normalization scales (sigma).
    public struct ScaleConfig: Sendable {
        public var tiltScale: Double = 6.0       // degrees
        public var lateralScale: Double = 0.12    // normalized frame
        public var distanceScale: Double = 0.24   // log ratio
        public var heightScale: Double = 0.36     // normalized frame
        public var pitchScale: Double = 9.0       // degrees

        public init(
            tiltScale: Double = 6.0,
            lateralScale: Double = 0.12,
            distanceScale: Double = 0.24,
            heightScale: Double = 0.36,
            pitchScale: Double = 9.0
        ) {
            self.tiltScale = tiltScale
            self.lateralScale = lateralScale
            self.distanceScale = distanceScale
            self.heightScale = heightScale
            self.pitchScale = pitchScale
        }
    }

    public static let defaultScaleConfig = ScaleConfig()

    /// Dimension weights matching PRODUCT_SPEC.md 1.4.1.
    public static let weightTilt: Double = 0.18
    public static let weightLateral: Double = 0.30
    public static let weightDistance: Double = 0.24
    public static let weightHeight: Double = 0.13
    public static let weightPitch: Double = 0.15

    /// Computes the raw match score (0–100) from spatial deltas.
    /// PRODUCT_SPEC.md 1.4.1:
    /// s_d = exp(-e_d^2)
    /// Score = round(100 * sum(w_d * c_d * s_d) / sum(w_d * c_d))
    public static func computeScore(
        delta: CompositionDelta,
        tier: ConfidenceTier = .full,
        scales: ScaleConfig = defaultScaleConfig
    ) -> Int {
        // 1. Normalized dimension errors
        let eTilt = abs(delta.deltaTilt) / max(1e-4, scales.tiltScale)
        let eLat = abs(delta.deltaLateral) / max(1e-4, scales.lateralScale)
        let eDist = abs(delta.deltaDistance) / max(1e-4, scales.distanceScale)
        let eHeight = abs(delta.deltaHeight) / max(1e-4, scales.heightScale)
        let ePitch = abs(delta.deltaPitch) / max(1e-4, scales.pitchScale)

        // 2. Gaussian component scores: s_d = exp(-e_d^2)
        let sTilt = exp(-(eTilt * eTilt))
        let sLat = exp(-(eLat * eLat))
        let sDist = exp(-(eDist * eDist))
        let sHeight = exp(-(eHeight * eHeight))
        let sPitch = exp(-(ePitch * ePitch))

        // 3. Effective confidences per dimension
        let cTilt = delta.effectiveConfidence.tilt
        let cLat = delta.isSuppressed(.lateral) ? 0.0 : delta.effectiveConfidence.lateral
        let cDist = delta.isSuppressed(.distance) ? 0.0 : delta.effectiveConfidence.distance
        let cHeight = delta.isSuppressed(.height) ? 0.0 : delta.effectiveConfidence.height
        let cPitch = delta.effectiveConfidence.pitch

        // 4. Weighted summation
        var weightedScoreSum = 0.0
        var totalWeightConf = 0.0

        // Tilt
        let wConfTilt = weightTilt * cTilt
        weightedScoreSum += wConfTilt * sTilt
        totalWeightConf += wConfTilt

        // Lateral
        let wConfLat = weightLateral * cLat
        weightedScoreSum += wConfLat * sLat
        totalWeightConf += wConfLat

        // Distance
        let wConfDist = weightDistance * cDist
        weightedScoreSum += wConfDist * sDist
        totalWeightConf += wConfDist

        // Height
        let wConfHeight = weightHeight * cHeight
        weightedScoreSum += wConfHeight * sHeight
        totalWeightConf += wConfHeight

        // Pitch
        let wConfPitch = weightPitch * cPitch
        weightedScoreSum += wConfPitch * sPitch
        totalWeightConf += wConfPitch

        guard totalWeightConf > 1e-6 else {
            return 0
        }

        let normalizedScore = 100.0 * (weightedScoreSum / totalWeightConf)
        let roundedScore = Int(round(normalizedScore))
        let clampedScore = max(0, min(100, roundedScore))

        // Apply confidence tier degradation cap (PRODUCT_SPEC.md 1.4.2)
        return min(clampedScore, tier.maxScoreCap)
    }
}
