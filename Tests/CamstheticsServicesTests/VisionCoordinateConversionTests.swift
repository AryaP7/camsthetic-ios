import XCTest
import CamstheticsEngine
@testable import CamstheticsServices

// MARK: - Phase 3 — VisionCoordinateConversion unit tests
//
// `VisionCoordinateConversion` operates on plain doubles (never
// `VNObservation` itself, which can't be synthesized without Vision/
// hardware), so this is testable with constructed fixtures on macOS —
// matching `CaptureFormatSelectionTests`/`LensSelectionTests`'s
// established pattern in this module.
final class VisionCoordinateConversionTests: XCTestCase {

    // MARK: normRect(fromVisionBoundingBoxX:y:width:height:)
    //
    // Vision: bottom-left origin, y-up. CamstheticsEngine.NormRect:
    // top-left origin, y-down.

    func testNormRectFlipsAVisionRectPinnedToTheBottomToTheTop() {
        // A Vision rect at the very bottom (y=0, height=0.2) — in Vision's
        // bottom-left-origin space this sits at the bottom of the frame,
        // which is the TOP-left-origin space's bottom too (y = 1 - 0 - 0.2
        // = 0.8, i.e. its far edge reaches y=1.0 — the bottom of the
        // top-left-origin frame). Anchoring on both ends this way avoids a
        // test that would pass under an accidental double-negation.
        let rect = VisionCoordinateConversion.normRect(
            fromVisionBoundingBoxX: 0.1, y: 0.0, width: 0.3, height: 0.2
        )
        XCTAssertEqual(rect.x, 0.1, accuracy: 0.0001)
        XCTAssertEqual(rect.y, 0.8, accuracy: 0.0001)
        XCTAssertEqual(rect.width, 0.3, accuracy: 0.0001)
        XCTAssertEqual(rect.height, 0.2, accuracy: 0.0001)
        // Its far (bottom) edge in the flipped space must land exactly at
        // the frame's bottom (1.0), confirming the flip anchors correctly
        // rather than just negating y in place.
        XCTAssertEqual(rect.maxY, 1.0, accuracy: 0.0001)
    }

    func testNormRectPinnedToTheTopInVisionSpaceFlipsToTheBottomInEngineSpace() {
        // A Vision rect at the very top (y=0.8, height=0.2, i.e. reaching
        // Vision's y=1.0 ceiling) must flip to sit at the very TOP of
        // NormRect's space (y=0.0).
        let rect = VisionCoordinateConversion.normRect(
            fromVisionBoundingBoxX: 0.1, y: 0.8, width: 0.3, height: 0.2
        )
        XCTAssertEqual(rect.y, 0.0, accuracy: 0.0001)
        XCTAssertEqual(rect.maxY, 0.2, accuracy: 0.0001)
    }

    func testNormRectCenteredRectMapsToItself() {
        // A rect symmetric about the vertical center (y=0.4, height=0.2,
        // spanning 0.4...0.6) is its own fixed point under a vertical
        // flip — a useful sanity check independent of which direction is
        // "up".
        let rect = VisionCoordinateConversion.normRect(
            fromVisionBoundingBoxX: 0.25, y: 0.4, width: 0.5, height: 0.2
        )
        XCTAssertEqual(rect.x, 0.25, accuracy: 0.0001)
        XCTAssertEqual(rect.y, 0.4, accuracy: 0.0001)
        XCTAssertEqual(rect.width, 0.5, accuracy: 0.0001)
        XCTAssertEqual(rect.height, 0.2, accuracy: 0.0001)
    }

    func testNormRectFullFrameMapsToFullFrame() {
        let rect = VisionCoordinateConversion.normRect(
            fromVisionBoundingBoxX: 0.0, y: 0.0, width: 1.0, height: 1.0
        )
        XCTAssertEqual(rect, NormRect.unit)
    }

    // MARK: normPoint(fromVisionPointX:y:)

    func testNormPointFlipsBottomToTop() {
        let point = VisionCoordinateConversion.normPoint(fromVisionPointX: 0.3, y: 0.0)
        XCTAssertEqual(point.x, 0.3, accuracy: 0.0001)
        XCTAssertEqual(point.y, 1.0, accuracy: 0.0001)
    }

    func testNormPointFlipsTopToBottom() {
        let point = VisionCoordinateConversion.normPoint(fromVisionPointX: 0.3, y: 1.0)
        XCTAssertEqual(point.x, 0.3, accuracy: 0.0001)
        XCTAssertEqual(point.y, 0.0, accuracy: 0.0001)
    }

    func testNormPointCenterMapsToCenter() {
        let point = VisionCoordinateConversion.normPoint(fromVisionPointX: 0.5, y: 0.5)
        XCTAssertEqual(point, NormPoint.center)
    }
}
