// SobelEdgeTiltEstimator.swift
// CamstheticsEngine
// Pure Swift image gradient orientation analyzer and horizon tilt estimator.

import Foundation

/// Pure Swift Sobel gradient kernel analyzer that computes dominant edge orientations and estimated tilt angle.
public enum SobelEdgeTiltEstimator {
    /// Maximum confidence allowed for target-side image tilt estimation (PRODUCT_SPEC.md 1.2.3).
    public static let maxTargetTiltConfidence: Double = 0.70

    /// Result of Sobel tilt estimation.
    public struct Result: Equatable, Sendable {
        /// Estimated roll / tilt angle in degrees relative to horizontal (in [-45.0, 45.0]).
        public var tiltDegrees: Double
        /// Confidence in the estimation, in range [0.0, 0.70].
        public var confidence: Double

        public init(tiltDegrees: Double, confidence: Double) {
            self.tiltDegrees = tiltDegrees
            self.confidence = min(max(0.0, confidence), maxTargetTiltConfidence)
        }
    }

    /// Estimates tilt angle from an 8-bit grayscale pixel buffer (row-major).
    /// - Parameters:
    ///   - pixels: Grayscale byte array (0-255).
    ///   - width: Image width in pixels.
    ///   - height: Image height in pixels.
    ///   - bytesPerRow: Number of bytes per image row (stride).
    ///   - magnitudeThreshold: Minimum gradient magnitude to consider as valid edge.
    /// - Returns: Estimated tilt angle in degrees and associated confidence.
    public static func estimateTilt(
        pixels: [UInt8],
        width: Int,
        height: Int,
        bytesPerRow: Int? = nil,
        magnitudeThreshold: Double = 30.0
    ) -> Result {
        let stride = bytesPerRow ?? width
        guard width >= 3, height >= 3, pixels.count >= stride * height else {
            return Result(tiltDegrees: 0.0, confidence: 0.0)
        }

        // 90 bins covering [-45.0°, +45.0°] with 1.0° resolution
        var histogram = [Double](repeating: 0.0, count: 91)
        var totalWeight = 0.0

        for y in 1..<(height - 1) {
            let rowAbove = (y - 1) * stride
            let rowCurrent = y * stride
            let rowBelow = (y + 1) * stride

            for x in 1..<(width - 1) {
                let p00 = Double(pixels[rowAbove + x - 1])
                let p01 = Double(pixels[rowAbove + x])
                let p02 = Double(pixels[rowAbove + x + 1])

                let p10 = Double(pixels[rowCurrent + x - 1])
                let p12 = Double(pixels[rowCurrent + x + 1])

                let p20 = Double(pixels[rowBelow + x - 1])
                let p21 = Double(pixels[rowBelow + x])
                let p22 = Double(pixels[rowBelow + x + 1])

                // Sobel 3x3 convolutions
                let gx = (p02 + 2.0 * p12 + p22) - (p00 + 2.0 * p10 + p20)
                let gy = (p20 + 2.0 * p21 + p22) - (p00 + 2.0 * p01 + p02)

                let magnitude = (gx * gx + gy * gy).squareRoot()
                if magnitude >= magnitudeThreshold {
                    // Gradient angle in degrees [-180.0, 180.0]
                    let angleDeg = atan2(gy, gx) * (180.0 / .pi)

                    // Edge line orientation is perpendicular to gradient
                    var edgeAngle = angleDeg + 90.0
                    while edgeAngle > 90.0 { edgeAngle -= 180.0 }
                    while edgeAngle <= -90.0 { edgeAngle += 180.0 }

                    // Fold to deviation from nearest cardinal axis (0° horizontal or ±90° vertical)
                    var deviation: Double
                    if edgeAngle > 45.0 {
                        deviation = edgeAngle - 90.0
                    } else if edgeAngle < -45.0 {
                        deviation = edgeAngle + 90.0
                    } else {
                        deviation = edgeAngle
                    }

                    // Map [-45.0, 45.0] to bin index [0, 90]
                    let binIndex = Int(round(deviation + 45.0))
                    if binIndex >= 0 && binIndex < histogram.count {
                        histogram[binIndex] += magnitude
                        totalWeight += magnitude
                    }
                }
            }
        }

        guard totalWeight > 100.0 else {
            return Result(tiltDegrees: 0.0, confidence: 0.0)
        }

        // Find dominant peak
        var maxBin = 45
        var maxBinWeight = 0.0
        for (i, w) in histogram.enumerated() {
            if w > maxBinWeight {
                maxBinWeight = w
                maxBin = i
            }
        }

        let rawTilt = Double(maxBin) - 45.0

        // Sub-bin parabolic refinement
        var refinedTilt = rawTilt
        if maxBin > 0 && maxBin < histogram.count - 1 {
            let left = histogram[maxBin - 1]
            let center = histogram[maxBin]
            let right = histogram[maxBin + 1]
            let denom = 2.0 * (2.0 * center - left - right)
            if abs(denom) > 1e-6 {
                let offset = (left - right) / denom
                if abs(offset) <= 1.0 {
                    refinedTilt = rawTilt + offset
                }
            }
        }

        // Calculate confidence from peak concentration
        // Mass within ±3 degrees of peak vs total
        var peakClusterMass = 0.0
        let window = 3
        let startBin = max(0, maxBin - window)
        let endBin = min(histogram.count - 1, maxBin + window)
        for i in startBin...endBin {
            peakClusterMass += histogram[i]
        }

        let concentration = peakClusterMass / totalWeight
        let rawConfidence = concentration * 0.9
        let finalConfidence = min(rawConfidence, maxTargetTiltConfidence)

        return Result(tiltDegrees: refinedTilt, confidence: finalConfidence)
    }
}
