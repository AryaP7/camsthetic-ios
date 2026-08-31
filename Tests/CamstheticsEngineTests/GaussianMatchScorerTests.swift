// GaussianMatchScorerTests.swift
// CamstheticsEngineTests

import XCTest
@testable import CamstheticsEngine

final class GaussianMatchScorerTests: XCTestCase {
    func testPerfectAlignmentScores100() {
        let delta = CompositionDelta(
            deltaTilt: 0.0,
            deltaLateral: 0.0,
            deltaDistance: 0.0,
            distanceRatio: 1.0,
            deltaHeight: 0.0,
            deltaPitch: 0.0,
            effectiveConfidence: .full
        )

        let score = GaussianMatchScorer.computeScore(delta: delta, tier: .full)
        XCTAssertEqual(score, 100)
    }

    func testScoreMonotonicityAcrossAllDimensions() {
        // Property-based test: For any dimension, reducing error never lowers the score

        // 1. Tilt monotonicity
        var previousScore = -1
        for tiltDeg in stride(from: 30.0, through: 0.0, by: -1.0) {
            let delta = CompositionDelta(
                deltaTilt: tiltDeg,
                deltaLateral: 0.0,
                deltaDistance: 0.0,
                distanceRatio: 1.0,
                deltaHeight: 0.0,
                deltaPitch: 0.0,
                effectiveConfidence: .full
            )
            let currentScore = GaussianMatchScorer.computeScore(delta: delta, tier: .full)
            if previousScore >= 0 {
                XCTAssertGreaterThanOrEqual(currentScore, previousScore, "Tilt monotonicity failed at \(tiltDeg)°")
            }
            previousScore = currentScore
        }

        // 2. Lateral monotonicity
        previousScore = -1
        for lat in stride(from: 0.50, through: 0.0, by: -0.02) {
            let delta = CompositionDelta(
                deltaTilt: 0.0,
                deltaLateral: lat,
                deltaDistance: 0.0,
                distanceRatio: 1.0,
                deltaHeight: 0.0,
                deltaPitch: 0.0,
                effectiveConfidence: .full
            )
            let currentScore = GaussianMatchScorer.computeScore(delta: delta, tier: .full)
            if previousScore >= 0 {
                XCTAssertGreaterThanOrEqual(currentScore, previousScore, "Lateral monotonicity failed at lat=\(lat)")
            }
            previousScore = currentScore
        }

        // 3. Distance monotonicity
        previousScore = -1
        for ratio in stride(from: 3.0, through: 1.0, by: -0.1) {
            let delta = CompositionDelta(
                deltaTilt: 0.0,
                deltaLateral: 0.0,
                deltaDistance: log(ratio),
                distanceRatio: ratio,
                deltaHeight: 0.0,
                deltaPitch: 0.0,
                effectiveConfidence: .full
            )
            let currentScore = GaussianMatchScorer.computeScore(delta: delta, tier: .full)
            if previousScore >= 0 {
                XCTAssertGreaterThanOrEqual(currentScore, previousScore, "Distance monotonicity failed at ratio=\(ratio)")
            }
            previousScore = currentScore
        }

        // 4. Height monotonicity
        previousScore = -1
        for h in stride(from: 0.50, through: 0.0, by: -0.02) {
            let delta = CompositionDelta(
                deltaTilt: 0.0,
                deltaLateral: 0.0,
                deltaDistance: 0.0,
                distanceRatio: 1.0,
                deltaHeight: h,
                deltaPitch: 0.0,
                effectiveConfidence: .full
            )
            let currentScore = GaussianMatchScorer.computeScore(delta: delta, tier: .full)
            if previousScore >= 0 {
                XCTAssertGreaterThanOrEqual(currentScore, previousScore, "Height monotonicity failed at h=\(h)")
            }
            previousScore = currentScore
        }
    }

    func testTierScoreCapping() {
        let perfectDelta = CompositionDelta(
            deltaTilt: 0.0,
            deltaLateral: 0.0,
            deltaDistance: 0.0,
            distanceRatio: 1.0,
            deltaHeight: 0.0,
            deltaPitch: 0.0,
            effectiveConfidence: .full
        )

        // Full tier achieves 100
        XCTAssertEqual(GaussianMatchScorer.computeScore(delta: perfectDelta, tier: .full), 100)

        // Partial tier is capped at 60
        XCTAssertEqual(GaussianMatchScorer.computeScore(delta: perfectDelta, tier: .partial), 60)

        // Minimal tier is capped at 85
        XCTAssertEqual(GaussianMatchScorer.computeScore(delta: perfectDelta, tier: .minimal), 85)
    }

    func testToleranceBoundaryScoreIsAtLeast85() {
        // When all dimensions are exactly at their entry tolerances:
        // Tilt = 2.0°, Lateral = 0.04, Distance = 0.08, Height = 0.12, Pitch = 3.0°
        let tolDelta = CompositionDelta(
            deltaTilt: 2.0,
            deltaLateral: 0.04,
            deltaDistance: log(1.08),
            distanceRatio: 1.08,
            deltaHeight: 0.12,
            deltaPitch: 3.0,
            effectiveConfidence: .full
        )

        let score = GaussianMatchScorer.computeScore(delta: tolDelta, tier: .full)
        XCTAssertGreaterThanOrEqual(score, 85, "Framing within all tolerances should achieve On-Target (>= 85%)")
    }
}
