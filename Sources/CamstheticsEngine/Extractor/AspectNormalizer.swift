// AspectNormalizer.swift
// CamstheticsEngine
// Aspect ratio normalization and coordinate space transformation.

import Foundation

/// Mathematical coordinate transformer that maps arbitrary image aspect ratios into a unified common aspect space.
public enum AspectNormalizer {
    /// Computes the common aspect ratio between target and live frames.
    /// PRODUCT_SPEC.md 1.2.1: aspect_common = min(aspect_target, aspect_live).
    @inlinable
    public static func commonAspect(targetAspect: Double, liveAspect: Double) -> Double {
        guard targetAspect > 0.0, liveAspect > 0.0 else {
            return 1.0
        }
        return min(targetAspect, liveAspect)
    }

    /// Computes the normalized center-crop rectangle within an image of `imageAspect` to fit `commonAspect`.
    public static func cropRect(imageAspect: Double, commonAspect: Double) -> NormRect {
        guard imageAspect > 0.0, commonAspect > 0.0 else {
            return .unit
        }

        if imageAspect > commonAspect {
            // Image is wider than common aspect: center-crop horizontally
            let cropWidth = commonAspect / imageAspect
            let cropX = (1.0 - cropWidth) / 2.0
            return NormRect(x: cropX, y: 0.0, width: cropWidth, height: 1.0)
        } else if imageAspect < commonAspect {
            // Image is taller than common aspect: center-crop vertically
            let cropHeight = imageAspect / commonAspect
            let cropY = (1.0 - cropHeight) / 2.0
            return NormRect(x: 0.0, y: cropY, width: 1.0, height: cropHeight)
        } else {
            // Exactly matching aspect ratio
            return .unit
        }
    }

    /// Transforms a point from original normalized image space to common normalized aspect space.
    public static func normalizePoint(_ point: NormPoint, imageAspect: Double, commonAspect: Double) -> NormPoint {
        let crop = cropRect(imageAspect: imageAspect, commonAspect: commonAspect)
        guard crop.width > 0.0, crop.height > 0.0 else { return point }

        let normX = (point.x - crop.x) / crop.width
        let normY = (point.y - crop.y) / crop.height
        return NormPoint(x: normX, y: normY)
    }

    /// Inversely transforms a point from common normalized aspect space back to original image space.
    public static func denormalizePoint(_ point: NormPoint, imageAspect: Double, commonAspect: Double) -> NormPoint {
        let crop = cropRect(imageAspect: imageAspect, commonAspect: commonAspect)
        let origX = crop.x + point.x * crop.width
        let origY = crop.y + point.y * crop.height
        return NormPoint(x: origX, y: origY)
    }

    /// Transforms a rectangle from original normalized image space to common normalized aspect space.
    public static func normalizeRect(_ rect: NormRect, imageAspect: Double, commonAspect: Double) -> NormRect {
        let crop = cropRect(imageAspect: imageAspect, commonAspect: commonAspect)
        guard crop.width > 0.0, crop.height > 0.0 else { return rect }

        let normX = (rect.x - crop.x) / crop.width
        let normY = (rect.y - crop.y) / crop.height
        let normW = rect.width / crop.width
        let normH = rect.height / crop.height

        return NormRect(x: normX, y: normY, width: normW, height: normH)
    }

    /// Inversely transforms a rectangle from common normalized aspect space back to original image space.
    public static func denormalizeRect(_ rect: NormRect, imageAspect: Double, commonAspect: Double) -> NormRect {
        let crop = cropRect(imageAspect: imageAspect, commonAspect: commonAspect)
        let origX = crop.x + rect.x * crop.width
        let origY = crop.y + rect.y * crop.height
        let origW = rect.width * crop.width
        let origH = rect.height * crop.height

        return NormRect(x: origX, y: origY, width: origW, height: origH)
    }

    /// Transforms full composition parameters to common aspect space.
    public static func normalizeComposition(_ params: CompositionParams, commonAspect: Double) -> CompositionParams {
        var updated = params

        if let subjectRect = params.subjectRect {
            let normRect = normalizeRect(subjectRect, imageAspect: params.aspectRatio, commonAspect: commonAspect)
            updated.subjectRect = normRect

            if params.subjectCategory == .person {
                updated.subjectRatio = normRect.height
            } else {
                updated.subjectRatio = normRect.area.squareRoot()
            }
        }

        if let anchor = params.subjectAnchor {
            let normAnchor = normalizePoint(anchor, imageAspect: params.aspectRatio, commonAspect: commonAspect)
            updated.subjectAnchor = normAnchor
            updated.lateralRatio = normAnchor.x
            updated.heightRatio = normAnchor.y
        } else if let rect = updated.subjectRect {
            updated.lateralRatio = rect.midX
            updated.heightRatio = rect.midY
        }

        updated.aspectRatio = commonAspect
        return updated
    }
}
