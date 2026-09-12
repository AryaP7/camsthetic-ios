import AVFoundation
import CoreMedia
import XCTest
@testable import CamstheticsServices

// MARK: - Phase 2.1 — CaptureFormatSelection unit tests
//
// `CaptureFormatSelection` deliberately operates on already-queried value
// types (`CMVideoDimensions`, `[AVVideoCodecType]`) rather than
// `AVCaptureDevice.Format` directly, specifically so this policy is
// testable with constructed fixtures — `AVCaptureDevice.Format` has no
// public initializer and cannot be synthesized without real hardware.
// Runs via plain `swift test`, no simulator/device needed, matching
// CamstheticsEngineTests' existing pattern.
final class CaptureFormatSelectionTests: XCTestCase {

    // MARK: largestDimensions(among:)

    func testLargestDimensionsPicksLargestByArea() {
        let small = CMVideoDimensions(width: 1920, height: 1080)
        let large = CMVideoDimensions(width: 4032, height: 3024)
        let medium = CMVideoDimensions(width: 3024, height: 2268)

        let result = CaptureFormatSelection.largestDimensions(among: [small, medium, large])

        XCTAssertEqual(result?.width, large.width)
        XCTAssertEqual(result?.height, large.height)
    }

    func testLargestDimensionsHandlesSingleEntry() {
        let only = CMVideoDimensions(width: 4032, height: 3024)

        let result = CaptureFormatSelection.largestDimensions(among: [only])

        XCTAssertEqual(result?.width, only.width)
        XCTAssertEqual(result?.height, only.height)
    }

    func testLargestDimensionsReturnsNilForEmptyList() {
        XCTAssertNil(CaptureFormatSelection.largestDimensions(among: []))
    }

    func testLargestDimensionsComparesByAreaNotWidthAlone() {
        // A very wide but short frame vs. a squarer but taller one —
        // area comparison should win, not raw width.
        let wideShort = CMVideoDimensions(width: 8000, height: 100) // area 800,000
        let squarer = CMVideoDimensions(width: 4032, height: 3024) // area ~12.2M

        let result = CaptureFormatSelection.largestDimensions(among: [wideShort, squarer])

        XCTAssertEqual(result?.width, squarer.width)
        XCTAssertEqual(result?.height, squarer.height)
    }

    // MARK: preferredCodec(among:)

    func testPreferredCodecChoosesHEVCWhenAvailable() {
        let codecs: [AVVideoCodecType] = [.jpeg, .hevc]

        XCTAssertEqual(CaptureFormatSelection.preferredCodec(among: codecs), .hevc)
    }

    func testPreferredCodecReturnsNilWhenHEVCUnavailable() {
        // Never falls back to hard-coding JPEG — nil signals "let
        // AVCapturePhotoOutput resolve its own default."
        let codecs: [AVVideoCodecType] = [.jpeg]

        XCTAssertNil(CaptureFormatSelection.preferredCodec(among: codecs))
    }

    func testPreferredCodecReturnsNilForEmptyList() {
        XCTAssertNil(CaptureFormatSelection.preferredCodec(among: []))
    }
}

// MARK: - Phase 2 Step 2 — AnalysisPixelFormatSelection unit tests
//
// Same reasoning as `CaptureFormatSelectionTests` above: operates on an
// already-queried `[OSType]` rather than `AVCaptureVideoDataOutput`
// directly, so it's testable with constructed fixtures on macOS.
final class AnalysisPixelFormatSelectionTests: XCTestCase {

    func testPrefers420fWhenBothAreOffered() {
        let formats: [OSType] = [
            kCVPixelFormatType_32BGRA,
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]

        XCTAssertEqual(
            AnalysisPixelFormatSelection.preferredPixelFormat(among: formats),
            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        )
    }

    func testFallsBackTo420vWhen420fUnavailable() {
        let formats: [OSType] = [
            kCVPixelFormatType_32BGRA,
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        ]

        XCTAssertEqual(
            AnalysisPixelFormatSelection.preferredPixelFormat(among: formats),
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        )
    }

    func testNeverSelectsBGRA() {
        // Only BGRA offered — never falls back to it; `nil` signals a
        // genuine capability gap rather than silently going full-res BGRA
        // (`docs/TECH_STACK.md`).
        XCTAssertNil(AnalysisPixelFormatSelection.preferredPixelFormat(among: [kCVPixelFormatType_32BGRA]))
    }

    func testReturnsNilForEmptyList() {
        XCTAssertNil(AnalysisPixelFormatSelection.preferredPixelFormat(among: []))
    }
}
