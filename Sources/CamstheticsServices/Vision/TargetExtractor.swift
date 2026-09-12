import Foundation
import CoreGraphics
import Vision
import CamstheticsEngine

// MARK: - Phase 3 — TargetExtractor (one-shot still-image composition extraction)
//
// `docs/PRODUCT_SPEC.md` §1.1: "Target CompositionParams are extracted in
// background (<500ms)" once a reference image is ingested.
// `docs/IMPLEMENTATION_PLAN.md` Phase 3 deliverable: "TargetExtractor
// extracting target CompositionParams from still images in <500ms."
//
// Bridges a `CGImage` into the SAME pure engines already built and tested
// elsewhere — never reimplements their math:
//   - `VisionSubjectExtraction` (shared with `VisionService`) for subject
//     detection/eye-line anchor — the live and target sides use the
//     identical Vision→SubjectCandidate bridge, so they can't silently
//     diverge.
//   - `CamstheticsEngine.SobelEdgeTiltEstimator` for target-side tilt,
//     confidence capped 0.70 (`PRODUCT_SPEC.md` §1.2.2) — this file's job
//     is decoding/downscaling a `CGImage` into the grayscale byte buffer
//     that pure kernel expects, not reimplementing the kernel itself.
//
// Pitch/camera-angle extraction (`PRODUCT_SPEC.md` §1.2's "perspective
// vanishing point convergence, eye-line vertical position... torso
// foreshortening ratio") is NOT implemented here — out of this phase's
// explicit scope (Part B3 of the approved plan: this phase delivers
// `VisionService` + `TargetExtractor`'s subject/tilt extraction only).
// `pitchDegrees`/`confidences.pitch` are left at 0.0 accordingly, not
// silently fabricated.
public enum TargetExtractorError: LocalizedError, Sendable {
    case grayscaleContextCreationFailed
    case inferenceFailed(String)

    public var errorDescription: String? {
        switch self {
        case .grayscaleContextCreationFailed:
            return "Could not create a grayscale bitmap context for tilt estimation."
        case .inferenceFailed(let description):
            return "Vision inference failed: \(description)"
        }
    }
}

public enum TargetExtractor {

    /// Long-edge cap for the downscaled grayscale buffer fed to the Sobel
    /// estimator — `docs/ARCHITECTURE.md` §4.2: "downscaled grayscale
    /// CGImage (≤256px)".
    public static let sobelDownscaleLongEdge = 256

    /// Extracts `CompositionParams` from a still reference image. Runs
    /// synchronously on the calling thread/task — callers wanting this off
    /// the main thread should call it from a background `Task`, matching
    /// `PRODUCT_SPEC.md` §1.1's "extracted in background" requirement
    /// (this function makes no threading decision of its own).
    public static func extract(from cgImage: CGImage) throws -> CompositionParams {
        guard cgImage.width > 0, cgImage.height > 0 else {
            return CompositionParams(aspectRatio: 1.0, confidences: .zero)
        }
        let aspectRatio = Double(cgImage.width) / Double(cgImage.height)

        let candidates: [SubjectCandidate]
        do {
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            candidates = try VisionSubjectExtraction.detectSubjectCandidates(using: handler)
        } catch {
            throw TargetExtractorError.inferenceFailed(error.localizedDescription)
        }

        // No sticky-lock arbitration needed for a one-shot still — just
        // the single highest-scoring candidate, using the EXACT same
        // scoring formula live arbitration uses
        // (`SubjectSelector.scoreCandidate`, `PRODUCT_SPEC.md` §1.2.2).
        let primary = candidates.max { SubjectSelector.scoreCandidate($0) < SubjectSelector.scoreCandidate($1) }

        let tilt = try Self.estimateTilt(from: cgImage)

        let subjectRatio: Double
        if let rect = primary?.rect {
            subjectRatio = (primary?.category == .person) ? rect.height : rect.area.squareRoot()
        } else {
            subjectRatio = 0.0
        }

        return CompositionParams(
            aspectRatio: aspectRatio,
            subjectRect: primary?.rect,
            subjectAnchor: primary?.anchor,
            subjectCategory: primary?.category ?? .unknown,
            subjectRatio: subjectRatio,
            tiltDegrees: tilt.tiltDegrees,
            pitchDegrees: 0.0,
            heightRatio: primary?.anchor?.y ?? 0.5,
            lateralRatio: primary?.anchor?.x ?? 0.5,
            confidences: DimensionConfidence(
                tilt: tilt.confidence,
                lateral: primary != nil ? (primary?.confidence ?? 0) : 0.0,
                distance: primary != nil ? (primary?.confidence ?? 0) : 0.0,
                height: primary != nil ? (primary?.confidence ?? 0) : 0.0,
                pitch: 0.0
            )
        )
    }

    // MARK: Grayscale downscale bridge → SobelEdgeTiltEstimator

    static func estimateTilt(from cgImage: CGImage) throws -> SobelEdgeTiltEstimator.Result {
        let (pixels, width, height) = try Self.grayscaleBuffer(from: cgImage, longEdge: sobelDownscaleLongEdge)
        return SobelEdgeTiltEstimator.estimateTilt(pixels: pixels, width: width, height: height)
    }

    /// Renders `cgImage` into an 8-bit grayscale buffer, downscaled so its
    /// long edge is at most `longEdge` pixels (aspect-preserving) — the
    /// exact input shape `SobelEdgeTiltEstimator.estimateTilt` expects.
    /// Uses `CGContext`'s own grayscale color space conversion (device-
    /// agnostic, no manual luma-weighting formula to get subtly wrong).
    static func grayscaleBuffer(
        from cgImage: CGImage,
        longEdge: Int
    ) throws -> (pixels: [UInt8], width: Int, height: Int) {
        let longestSide = max(cgImage.width, cgImage.height)
        let scale = longestSide > longEdge ? Double(longEdge) / Double(longestSide) : 1.0
        let width = max(1, Int((Double(cgImage.width) * scale).rounded()))
        let height = max(1, Int((Double(cgImage.height) * scale).rounded()))

        guard let colorSpace = CGColorSpace(name: CGColorSpace.linearGray),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
              )
        else {
            throw TargetExtractorError.grayscaleContextCreationFailed
        }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let data = context.data else {
            throw TargetExtractorError.grayscaleContextCreationFailed
        }
        let buffer = data.bindMemory(to: UInt8.self, capacity: width * height)
        return (Array(UnsafeBufferPointer(start: buffer, count: width * height)), width, height)
    }
}
