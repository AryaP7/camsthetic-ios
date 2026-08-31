// AspectNormalizerTests.swift
// CamstheticsEngineTests

import XCTest
@testable import CamstheticsEngine

final class AspectNormalizerTests: XCTestCase {
    func testCommonAspectCalculation() {
        // Target 4:5 (0.8), Live 16:9 (1.777...) -> Common 0.8
        XCTAssertEqual(AspectNormalizer.commonAspect(targetAspect: 0.8, liveAspect: 16.0 / 9.0), 0.8, accuracy: 1e-6)

        // Target 16:9, Live 4:3 -> Common 4:3 (1.333...)
        XCTAssertEqual(AspectNormalizer.commonAspect(targetAspect: 16.0 / 9.0, liveAspect: 4.0 / 3.0), 4.0 / 3.0, accuracy: 1e-6)

        // Equal aspects 1:1
        XCTAssertEqual(AspectNormalizer.commonAspect(targetAspect: 1.0, liveAspect: 1.0), 1.0, accuracy: 1e-6)

        // Extreme: Target 1:3 (0.333...), Live 3:1 (3.0) -> Common 1:3
        XCTAssertEqual(AspectNormalizer.commonAspect(targetAspect: 1.0 / 3.0, liveAspect: 3.0), 1.0 / 3.0, accuracy: 1e-6)
    }

    func testCropRectGeometry() {
        // Wider image: 16:9 image cropped to 4:5 (0.8) common aspect
        let imgAspect = 16.0 / 9.0
        let commonAspect = 0.8
        let crop = AspectNormalizer.cropRect(imageAspect: imgAspect, commonAspect: commonAspect)

        let expectedWidth = 0.8 / (16.0 / 9.0) // 0.45
        let expectedX = (1.0 - 0.45) / 2.0 // 0.275

        XCTAssertEqual(crop.width, expectedWidth, accuracy: 1e-6)
        XCTAssertEqual(crop.height, 1.0, accuracy: 1e-6)
        XCTAssertEqual(crop.x, expectedX, accuracy: 1e-6)
        XCTAssertEqual(crop.y, 0.0, accuracy: 1e-6)

        // Taller image: 1:2 image cropped to 1:1 common aspect
        let tallCrop = AspectNormalizer.cropRect(imageAspect: 0.5, commonAspect: 1.0)
        XCTAssertEqual(tallCrop.width, 1.0, accuracy: 1e-6)
        XCTAssertEqual(tallCrop.height, 0.5, accuracy: 1e-6)
        XCTAssertEqual(tallCrop.x, 0.0, accuracy: 1e-6)
        XCTAssertEqual(tallCrop.y, 0.25, accuracy: 1e-6)
    }

    func testPointNormalizationRoundtrip() {
        let imgAspect = 16.0 / 9.0
        let commonAspect = 4.0 / 5.0 // 0.8

        // Center point in original image should remain center in common space
        let centerOrig = NormPoint(x: 0.5, y: 0.5)
        let centerNorm = AspectNormalizer.normalizePoint(centerOrig, imageAspect: imgAspect, commonAspect: commonAspect)
        XCTAssertEqual(centerNorm.x, 0.5, accuracy: 1e-6)
        XCTAssertEqual(centerNorm.y, 0.5, accuracy: 1e-6)

        // Arbitrary point roundtrip
        let p = NormPoint(x: 0.4, y: 0.7)
        let normP = AspectNormalizer.normalizePoint(p, imageAspect: imgAspect, commonAspect: commonAspect)
        let roundtripP = AspectNormalizer.denormalizePoint(normP, imageAspect: imgAspect, commonAspect: commonAspect)
        XCTAssertEqual(roundtripP.x, p.x, accuracy: 1e-6)
        XCTAssertEqual(roundtripP.y, p.y, accuracy: 1e-6)
    }

    func testRectNormalizationRoundtrip() {
        let imgAspect = 16.0 / 9.0
        let commonAspect = 1.0

        let rect = NormRect(x: 0.3, y: 0.2, width: 0.4, height: 0.6)
        let normRect = AspectNormalizer.normalizeRect(rect, imageAspect: imgAspect, commonAspect: commonAspect)
        let roundtripRect = AspectNormalizer.denormalizeRect(normRect, imageAspect: imgAspect, commonAspect: commonAspect)

        XCTAssertEqual(roundtripRect.x, rect.x, accuracy: 1e-6)
        XCTAssertEqual(roundtripRect.y, rect.y, accuracy: 1e-6)
        XCTAssertEqual(roundtripRect.width, rect.width, accuracy: 1e-6)
        XCTAssertEqual(roundtripRect.height, rect.height, accuracy: 1e-6)
    }

    func testExtremeAspectRatios() {
        let ratios: [(Double, Double)] = [
            (1.0 / 3.0, 3.0),
            (3.0, 1.0 / 3.0),
            (4.0 / 5.0, 16.0 / 9.0),
            (1.0, 1.0),
            (9.0 / 16.0, 4.0 / 3.0)
        ]

        for (targetAsp, liveAsp) in ratios {
            let common = AspectNormalizer.commonAspect(targetAspect: targetAsp, liveAspect: liveAsp)
            XCTAssertLessThanOrEqual(common, targetAsp + 1e-6)
            XCTAssertLessThanOrEqual(common, liveAsp + 1e-6)

            let p = NormPoint(x: 0.5, y: 0.5)
            let normT = AspectNormalizer.normalizePoint(p, imageAspect: targetAsp, commonAspect: common)
            let normL = AspectNormalizer.normalizePoint(p, imageAspect: liveAsp, commonAspect: common)
            XCTAssertEqual(normT.x, 0.5, accuracy: 1e-6)
            XCTAssertEqual(normT.y, 0.5, accuracy: 1e-6)
            XCTAssertEqual(normL.x, 0.5, accuracy: 1e-6)
            XCTAssertEqual(normL.y, 0.5, accuracy: 1e-6)
        }
    }
}
