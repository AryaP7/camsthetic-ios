// SobelEdgeTiltEstimatorTests.swift
// CamstheticsEngineTests

import XCTest
@testable import CamstheticsEngine

final class SobelEdgeTiltEstimatorTests: XCTestCase {
    func testHorizontalEdgeTiltIsZero() {
        let width = 64
        let height = 64
        var pixels = [UInt8](repeating: 255, count: width * height)

        // Draw horizontal black bar across middle
        for y in 28...36 {
            for x in 0..<width {
                pixels[y * width + x] = 0
            }
        }

        let result = SobelEdgeTiltEstimator.estimateTilt(pixels: pixels, width: width, height: height)
        XCTAssertEqual(result.tiltDegrees, 0.0, accuracy: 1.5)
        XCTAssertGreaterThan(result.confidence, 0.35)
        XCTAssertLessThanOrEqual(result.confidence, SobelEdgeTiltEstimator.maxTargetTiltConfidence)
    }

    func testConfidenceCappedAt070() {
        let width = 64
        let height = 64
        var pixels = [UInt8](repeating: 255, count: width * height)

        for y in 0..<height {
            for x in 0..<width {
                if y % 4 == 0 {
                    pixels[y * width + x] = 0
                }
            }
        }

        let result = SobelEdgeTiltEstimator.estimateTilt(pixels: pixels, width: width, height: height)
        XCTAssertLessThanOrEqual(result.confidence, 0.70)
    }

    func testBlankImageYieldsZeroConfidence() {
        let width = 32
        let height = 32
        let pixels = [UInt8](repeating: 128, count: width * height)

        let result = SobelEdgeTiltEstimator.estimateTilt(pixels: pixels, width: width, height: height)
        XCTAssertEqual(result.confidence, 0.0)
    }
}
