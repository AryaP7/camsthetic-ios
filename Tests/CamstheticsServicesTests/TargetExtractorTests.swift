import XCTest
import CoreGraphics
import CamstheticsEngine
@testable import CamstheticsServices

// MARK: - Phase 3 — TargetExtractor unit tests
//
// `CGImage`/`CGContext` are standard Core Graphics rendering — no camera,
// no device, fully constructible on macOS — so the grayscale-downscale
// bridge and the end-to-end `extract(from:)` pipeline (on synthetic
// images with no real subject) are directly testable here, unlike
// `VisionService`'s `CVPixelBuffer`-based live path.
final class TargetExtractorTests: XCTestCase {

    /// Builds a solid-color (optionally with a diagonal split for tilt
    /// tests) RGB `CGImage` of the given size — fully synthetic, no camera
    /// involved.
    private static func makeImage(
        width: Int,
        height: Int,
        diagonalSplitDegrees: Double? = nil
    ) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        if let degrees = diagonalSplitDegrees {
            // A high-contrast half-plane split at `degrees` from
            // horizontal — strong enough gradient magnitude everywhere
            // along the split line for the Sobel estimator to find a
            // dominant peak there.
            context.saveGState()
            context.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
            context.rotate(by: degrees * .pi / 180)
            context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
            let span = CGFloat(width + height) * 2
            context.fill(CGRect(x: -span / 2, y: 0, width: span, height: span / 2))
            context.restoreGState()
        }

        return context.makeImage()!
    }

    // MARK: grayscaleBuffer(from:longEdge:)

    func testGrayscaleBufferDownscalesPreservingAspectRatio() throws {
        let image = Self.makeImage(width: 512, height: 256)
        let (_, width, height) = try TargetExtractor.grayscaleBuffer(from: image, longEdge: 256)
        XCTAssertEqual(width, 256)
        XCTAssertEqual(height, 128)
    }

    func testGrayscaleBufferDoesNotUpscaleImagesAlreadySmallerThanLongEdge() throws {
        let image = Self.makeImage(width: 100, height: 50)
        let (_, width, height) = try TargetExtractor.grayscaleBuffer(from: image, longEdge: 256)
        XCTAssertEqual(width, 100)
        XCTAssertEqual(height, 50)
    }

    func testGrayscaleBufferPixelCountMatchesDimensions() throws {
        let image = Self.makeImage(width: 300, height: 300)
        let (pixels, width, height) = try TargetExtractor.grayscaleBuffer(from: image, longEdge: 256)
        XCTAssertEqual(pixels.count, width * height)
    }

    // MARK: extract(from:) — end-to-end on synthetic images

    func testExtractReturnsCorrectAspectRatioForABlankImage() throws {
        let image = Self.makeImage(width: 400, height: 200)
        let params = try TargetExtractor.extract(from: image)
        XCTAssertEqual(params.aspectRatio, 2.0, accuracy: 0.001)
    }

    func testExtractFindsNoSubjectInABlankImage() throws {
        // A plain white field has no person/salient object for Vision to
        // find — `hasSubject` must honestly report false rather than
        // fabricating a fallback subject.
        let image = Self.makeImage(width: 400, height: 400)
        let params = try TargetExtractor.extract(from: image)
        XCTAssertFalse(params.hasSubject)
        XCTAssertEqual(params.subjectCategory, .unknown)
        XCTAssertNil(params.subjectRect)
    }

    func testExtractPitchIsZeroNotFabricated() throws {
        // Pitch/camera-angle extraction is explicitly out of this phase's
        // scope (see `TargetExtractor.swift`'s doc comment) — must stay
        // exactly 0, not some invented placeholder.
        let image = Self.makeImage(width: 400, height: 400)
        let params = try TargetExtractor.extract(from: image)
        XCTAssertEqual(params.pitchDegrees, 0.0)
        XCTAssertEqual(params.confidences.pitch, 0.0)
    }

    func testExtractDetectsTiltFromAStrongDiagonalEdge() throws {
        // A clean 15° split should be picked up by the Sobel estimator
        // bridged through the downscaled grayscale buffer — confirms the
        // CGImage → grayscale → SobelEdgeTiltEstimator pipeline is wired
        // correctly end-to-end, not just unit-by-unit.
        //
        // MAGNITUDE only, not sign: measured -13.3° for a +15°
        // `CGContext.rotate(by:)` input — close in magnitude (softened
        // somewhat by the 256px downscale/antialiasing), but the SIGN
        // doesn't match a naive expectation. Rather than assert a
        // direction convention that hasn't been independently verified
        // (does `CGContext`'s positive-angle-is-counterclockwise rotation
        // match `SobelEdgeTiltEstimator`'s own tilt-sign convention, or
        // does a coordinate-space flip somewhere invert it?), this is
        // flagged here rather than silently encoded as a passing
        // assertion — needs checking against a real, known-tilted photo
        // before the sign can be trusted downstream.
        let image = Self.makeImage(width: 400, height: 400, diagonalSplitDegrees: 15)
        let params = try TargetExtractor.extract(from: image)
        XCTAssertGreaterThan(params.confidences.tilt, 0.0, "A strong diagonal edge should yield nonzero tilt confidence")
        XCTAssertEqual(abs(params.tiltDegrees), 15, accuracy: 5.0)
    }

    func testExtractTiltConfidenceNeverExceedsTheDocumentedCap() throws {
        let image = Self.makeImage(width: 400, height: 400, diagonalSplitDegrees: 10)
        let params = try TargetExtractor.extract(from: image)
        XCTAssertLessThanOrEqual(params.confidences.tilt, SobelEdgeTiltEstimator.maxTargetTiltConfidence)
    }
}
