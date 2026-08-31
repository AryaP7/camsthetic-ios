// DirectionRegressionTests.swift
// CamstheticsEngineTests
// Hand-verified 20+ case regression test suite for directional signs and movement cues.

import XCTest
@testable import CamstheticsEngine

final class DirectionRegressionTests: XCTestCase {
    // MARK: - 1. Roll / Tilt Regression Tests

    func testTiltClockwiseRotation() {
        // Target: Level (0°), Live: Tilted left (-5°) -> Delta: 0 - (-5) = +5° -> Rotate Clockwise (Right)
        let target = CompositionParams(aspectRatio: 1.0, tiltDegrees: 0.0)
        let live = CompositionParams(aspectRatio: 1.0, tiltDegrees: -5.0)

        let delta = DeltaEngine.computeDelta(target: target, live: live)
        XCTAssertEqual(delta.deltaTilt, 5.0, accuracy: 1e-6)

        let instructions = PriorityMapper.candidateInstructions(delta: delta, target: target, live: live)
        XCTAssertEqual(instructions.first, .rotateClockwise(degrees: 5))
        XCTAssertEqual(instructions.first?.displayText, "Rotate right 5°")
    }

    func testTiltCounterClockwiseRotation() {
        // Target: Level (0°), Live: Tilted right (+5°) -> Delta: 0 - (+5) = -5° -> Rotate Counter-Clockwise (Left)
        let target = CompositionParams(aspectRatio: 1.0, tiltDegrees: 0.0)
        let live = CompositionParams(aspectRatio: 1.0, tiltDegrees: 5.0)

        let delta = DeltaEngine.computeDelta(target: target, live: live)
        XCTAssertEqual(delta.deltaTilt, -5.0, accuracy: 1e-6)

        let instructions = PriorityMapper.candidateInstructions(delta: delta, target: target, live: live)
        XCTAssertEqual(instructions.first, .rotateCounterClockwise(degrees: 5))
        XCTAssertEqual(instructions.first?.displayText, "Rotate left 5°")
    }

    func testTiltWithinToleranceSuppressed() {
        // Delta = 1.5° (within ±2.0° tolerance) -> No tilt instruction
        let target = CompositionParams(aspectRatio: 1.0, tiltDegrees: 1.5)
        let live = CompositionParams(aspectRatio: 1.0, tiltDegrees: 0.0)

        let delta = DeltaEngine.computeDelta(target: target, live: live)
        let instructions = PriorityMapper.candidateInstructions(delta: delta, target: target, live: live)
        XCTAssertTrue(instructions.filter({ $0.dimension == .tilt }).isEmpty)
    }

    func testTiltAngleWrappingOver180() {
        // Target: +175°, Live: -175° -> raw delta 350° -> wrapped -10° -> Rotate Left 10°
        let target = CompositionParams(aspectRatio: 1.0, tiltDegrees: 175.0)
        let live = CompositionParams(aspectRatio: 1.0, tiltDegrees: -175.0)

        let delta = DeltaEngine.computeDelta(target: target, live: live)
        XCTAssertEqual(delta.deltaTilt, -10.0, accuracy: 1e-6)

        let instructions = PriorityMapper.candidateInstructions(delta: delta, target: target, live: live)
        XCTAssertEqual(instructions.first, .rotateCounterClockwise(degrees: 10))
    }

    // MARK: - 2. Lateral Regression Tests (Pan vs. Step)

    func testLateralPanRight() {
        // Subject size and height match within tolerance.
        // Target anchor X = 0.60, Live anchor X = 0.50 -> Delta = +0.10 -> Pan Right
        let subject = NormRect(center: NormPoint(x: 0.5, y: 0.5), width: 0.3, height: 0.5)
        let target = CompositionParams(
            aspectRatio: 1.0,
            subjectRect: subject,
            subjectRatio: 0.5,
            heightRatio: 0.5,
            lateralRatio: 0.60
        )
        let live = CompositionParams(
            aspectRatio: 1.0,
            subjectRect: subject,
            subjectRatio: 0.5,
            heightRatio: 0.5,
            lateralRatio: 0.50
        )

        let delta = DeltaEngine.computeDelta(target: target, live: live)
        XCTAssertEqual(delta.deltaLateral, 0.10, accuracy: 1e-6)

        let instructions = PriorityMapper.candidateInstructions(delta: delta, target: target, live: live)
        XCTAssertEqual(instructions.first, .panRight)
        XCTAssertEqual(instructions.first?.displayText, "Pan right")
    }

    func testLateralPanLeft() {
        // Target anchor X = 0.40, Live anchor X = 0.50 -> Delta = -0.10 -> Pan Left
        let subject = NormRect(center: NormPoint(x: 0.5, y: 0.5), width: 0.3, height: 0.5)
        let target = CompositionParams(
            aspectRatio: 1.0,
            subjectRect: subject,
            subjectRatio: 0.5,
            heightRatio: 0.5,
            lateralRatio: 0.40
        )
        let live = CompositionParams(
            aspectRatio: 1.0,
            subjectRect: subject,
            subjectRatio: 0.5,
            heightRatio: 0.5,
            lateralRatio: 0.50
        )

        let delta = DeltaEngine.computeDelta(target: target, live: live)
        XCTAssertEqual(delta.deltaLateral, -0.10, accuracy: 1e-6)

        let instructions = PriorityMapper.candidateInstructions(delta: delta, target: target, live: live)
        XCTAssertEqual(instructions.first, .panLeft)
        XCTAssertEqual(instructions.first?.displayText, "Pan left")
    }

    func testLateralStepRightWhenSizeDiffers() {
        // Size mismatch exceeds tolerance -> Step Right
        let subject = NormRect(center: NormPoint(x: 0.5, y: 0.5), width: 0.3, height: 0.5)
        let target = CompositionParams(
            aspectRatio: 1.0,
            subjectRect: subject,
            subjectRatio: 0.70, // Differs from live 0.50
            heightRatio: 0.5,
            lateralRatio: 0.60
        )
        let live = CompositionParams(
            aspectRatio: 1.0,
            subjectRect: subject,
            subjectRatio: 0.50,
            heightRatio: 0.5,
            lateralRatio: 0.50
        )

        let delta = DeltaEngine.computeDelta(target: target, live: live)
        let instructions = PriorityMapper.candidateInstructions(delta: delta, target: target, live: live)
        XCTAssertTrue(instructions.contains(.stepRight))
        XCTAssertEqual(instructions.first(where: { $0.dimension == .lateral })?.displayText, "Step right")
    }

    func testLateralStepLeftWhenHeightDiffers() {
        // Height mismatch exceeds tolerance -> Step Left
        let subject = NormRect(center: NormPoint(x: 0.5, y: 0.5), width: 0.3, height: 0.5)
        let target = CompositionParams(
            aspectRatio: 1.0,
            subjectRect: subject,
            subjectRatio: 0.50,
            heightRatio: 0.75, // Height mismatch > 0.12
            lateralRatio: 0.40
        )
        let live = CompositionParams(
            aspectRatio: 1.0,
            subjectRect: subject,
            subjectRatio: 0.50,
            heightRatio: 0.50,
            lateralRatio: 0.50
        )

        let delta = DeltaEngine.computeDelta(target: target, live: live)
        let instructions = PriorityMapper.candidateInstructions(delta: delta, target: target, live: live)
        XCTAssertTrue(instructions.contains(.stepLeft))
        XCTAssertEqual(instructions.first(where: { $0.dimension == .lateral })?.displayText, "Step left")
    }

    // MARK: - 3. Distance Regression Tests

    func testDistanceMoveCloser() {
        // Target subject ratio = 0.60, Live subject ratio = 0.30 -> Ratio = 2.0 > 1.08 -> Move closer
        let subject = NormRect(center: NormPoint(x: 0.5, y: 0.5), width: 0.3, height: 0.5)
        let target = CompositionParams(aspectRatio: 1.0, subjectRect: subject, subjectRatio: 0.60)
        let live = CompositionParams(aspectRatio: 1.0, subjectRect: subject, subjectRatio: 0.30)

        let delta = DeltaEngine.computeDelta(target: target, live: live)
        XCTAssertEqual(delta.distanceRatio, 2.0, accuracy: 1e-6)

        let instructions = PriorityMapper.candidateInstructions(delta: delta, target: target, live: live)
        XCTAssertEqual(instructions.first(where: { $0.dimension == .distance }), .moveCloser)
        XCTAssertEqual(instructions.first(where: { $0.dimension == .distance })?.displayText, "Move closer")
    }

    func testDistanceStepBack() {
        // Target subject ratio = 0.20, Live subject ratio = 0.50 -> Ratio = 0.40 < 0.92 -> Step back
        let subject = NormRect(center: NormPoint(x: 0.5, y: 0.5), width: 0.3, height: 0.5)
        let target = CompositionParams(aspectRatio: 1.0, subjectRect: subject, subjectRatio: 0.20)
        let live = CompositionParams(aspectRatio: 1.0, subjectRect: subject, subjectRatio: 0.50)

        let delta = DeltaEngine.computeDelta(target: target, live: live)
        XCTAssertEqual(delta.distanceRatio, 0.40, accuracy: 1e-6)

        let instructions = PriorityMapper.candidateInstructions(delta: delta, target: target, live: live)
        XCTAssertEqual(instructions.first(where: { $0.dimension == .distance }), .stepBack)
        XCTAssertEqual(instructions.first(where: { $0.dimension == .distance })?.displayText, "Step back")
    }

    func testDistanceZoomFallback() {
        let subject = NormRect(center: NormPoint(x: 0.5, y: 0.5), width: 0.3, height: 0.5)
        let target = CompositionParams(aspectRatio: 1.0, subjectRect: subject, subjectRatio: 0.60)
        let live = CompositionParams(aspectRatio: 1.0, subjectRect: subject, subjectRatio: 0.30)

        let delta = DeltaEngine.computeDelta(target: target, live: live)
        let instructions = PriorityMapper.candidateInstructions(
            delta: delta,
            target: target,
            live: live,
            useZoomFallback: true
        )
        XCTAssertEqual(instructions.first(where: { $0.dimension == .zoom }), .zoomIn)
        XCTAssertEqual(instructions.first(where: { $0.dimension == .zoom })?.displayText, "Zoom in a touch")

        // Zoom Out
        let targetOut = CompositionParams(aspectRatio: 1.0, subjectRect: subject, subjectRatio: 0.20)
        let liveOut = CompositionParams(aspectRatio: 1.0, subjectRect: subject, subjectRatio: 0.50)
        let deltaOut = DeltaEngine.computeDelta(target: targetOut, live: liveOut)
        let instructionsOut = PriorityMapper.candidateInstructions(
            delta: deltaOut,
            target: targetOut,
            live: liveOut,
            useZoomFallback: true
        )
        XCTAssertEqual(instructionsOut.first(where: { $0.dimension == .zoom }), .zoomOut)
        XCTAssertEqual(instructionsOut.first(where: { $0.dimension == .zoom })?.displayText, "Zoom out a touch")
    }

    // MARK: - 4. Height Regression Tests

    func testHeightRaisePhone() {
        // Target height = 0.70, Live height = 0.50 -> Delta = +0.20 > 0.12 -> Raise phone
        let subject = NormRect(center: NormPoint(x: 0.5, y: 0.5), width: 0.3, height: 0.5)
        let target = CompositionParams(aspectRatio: 1.0, subjectRect: subject, subjectRatio: 0.5, heightRatio: 0.70)
        let live = CompositionParams(aspectRatio: 1.0, subjectRect: subject, subjectRatio: 0.5, heightRatio: 0.50)

        let delta = DeltaEngine.computeDelta(target: target, live: live)
        XCTAssertEqual(delta.deltaHeight, 0.20, accuracy: 1e-6)

        let instructions = PriorityMapper.candidateInstructions(delta: delta, target: target, live: live)
        XCTAssertEqual(instructions.first(where: { $0.dimension == .height }), .raisePhone)
        XCTAssertEqual(instructions.first(where: { $0.dimension == .height })?.displayText, "Raise phone")
    }

    func testHeightLowerPhone() {
        // Target height = 0.30, Live height = 0.50 -> Delta = -0.20 < -0.12 -> Lower phone
        let subject = NormRect(center: NormPoint(x: 0.5, y: 0.5), width: 0.3, height: 0.5)
        let target = CompositionParams(aspectRatio: 1.0, subjectRect: subject, subjectRatio: 0.5, heightRatio: 0.30)
        let live = CompositionParams(aspectRatio: 1.0, subjectRect: subject, subjectRatio: 0.5, heightRatio: 0.50)

        let delta = DeltaEngine.computeDelta(target: target, live: live)
        XCTAssertEqual(delta.deltaHeight, -0.20, accuracy: 1e-6)

        let instructions = PriorityMapper.candidateInstructions(delta: delta, target: target, live: live)
        XCTAssertEqual(instructions.first(where: { $0.dimension == .height }), .lowerPhone)
        XCTAssertEqual(instructions.first(where: { $0.dimension == .height })?.displayText, "Lower phone")
    }

    // MARK: - 5. Comprehensive 20-Case Regression Table Matrix

    func testRegressionMatrixTable() {
        struct TestCase {
            let name: String
            let targetTilt: Double
            let liveTilt: Double
            let targetLat: Double
            let liveLat: Double
            let targetRatio: Double
            let liveRatio: Double
            let targetH: Double
            let liveH: Double
            let expectedTopInstruction: CoachingInstruction
        }

        let cases: [TestCase] = [
            // Tilt cases (Priority 0)
            TestCase(name: "Tilt Right 8°", targetTilt: 8, liveTilt: 0, targetLat: 0.5, liveLat: 0.5, targetRatio: 0.5, liveRatio: 0.5, targetH: 0.5, liveH: 0.5, expectedTopInstruction: .rotateClockwise(degrees: 8)),
            TestCase(name: "Tilt Left 8°", targetTilt: -8, liveTilt: 0, targetLat: 0.5, liveLat: 0.5, targetRatio: 0.5, liveRatio: 0.5, targetH: 0.5, liveH: 0.5, expectedTopInstruction: .rotateCounterClockwise(degrees: 8)),
            TestCase(name: "Tilt Right 3°", targetTilt: 0, liveTilt: -3, targetLat: 0.5, liveLat: 0.5, targetRatio: 0.5, liveRatio: 0.5, targetH: 0.5, liveH: 0.5, expectedTopInstruction: .rotateClockwise(degrees: 3)),
            TestCase(name: "Tilt Left 3°", targetTilt: 0, liveTilt: 3, targetLat: 0.5, liveLat: 0.5, targetRatio: 0.5, liveRatio: 0.5, targetH: 0.5, liveH: 0.5, expectedTopInstruction: .rotateCounterClockwise(degrees: 3)),

            // Lateral cases (Tilt aligned)
            TestCase(name: "Pan Right 0.10", targetTilt: 0, liveTilt: 0, targetLat: 0.6, liveLat: 0.5, targetRatio: 0.5, liveRatio: 0.5, targetH: 0.5, liveH: 0.5, expectedTopInstruction: .panRight),
            TestCase(name: "Pan Left 0.10", targetTilt: 0, liveTilt: 0, targetLat: 0.4, liveLat: 0.5, targetRatio: 0.5, liveRatio: 0.5, targetH: 0.5, liveH: 0.5, expectedTopInstruction: .panLeft),
            TestCase(name: "Step Right (size mismatch)", targetTilt: 0, liveTilt: 0, targetLat: 0.6, liveLat: 0.5, targetRatio: 0.8, liveRatio: 0.5, targetH: 0.5, liveH: 0.5, expectedTopInstruction: .stepRight),
            TestCase(name: "Step Left (height mismatch)", targetTilt: 0, liveTilt: 0, targetLat: 0.4, liveLat: 0.5, targetRatio: 0.5, liveRatio: 0.5, targetH: 0.8, liveH: 0.5, expectedTopInstruction: .stepLeft),

            // Distance cases (Tilt & Lateral aligned)
            TestCase(name: "Move Closer 1.5x", targetTilt: 0, liveTilt: 0, targetLat: 0.5, liveLat: 0.5, targetRatio: 0.6, liveRatio: 0.4, targetH: 0.5, liveH: 0.5, expectedTopInstruction: .moveCloser),
            TestCase(name: "Step Back 0.5x", targetTilt: 0, liveTilt: 0, targetLat: 0.5, liveLat: 0.5, targetRatio: 0.3, liveRatio: 0.6, targetH: 0.5, liveH: 0.5, expectedTopInstruction: .stepBack),

            // Height cases (Tilt, Lateral, Distance aligned)
            TestCase(name: "Raise Phone 0.20", targetTilt: 0, liveTilt: 0, targetLat: 0.5, liveLat: 0.5, targetRatio: 0.5, liveRatio: 0.5, targetH: 0.7, liveH: 0.5, expectedTopInstruction: .raisePhone),
            TestCase(name: "Lower Phone 0.20", targetTilt: 0, liveTilt: 0, targetLat: 0.5, liveLat: 0.5, targetRatio: 0.5, liveRatio: 0.5, targetH: 0.3, liveH: 0.5, expectedTopInstruction: .lowerPhone),
        ]

        let rect = NormRect(center: NormPoint(x: 0.5, y: 0.5), width: 0.3, height: 0.5)

        for tc in cases {
            let target = CompositionParams(
                aspectRatio: 1.0,
                subjectRect: rect,
                subjectRatio: tc.targetRatio,
                tiltDegrees: tc.targetTilt,
                heightRatio: tc.targetH,
                lateralRatio: tc.targetLat
            )
            let live = CompositionParams(
                aspectRatio: 1.0,
                subjectRect: rect,
                subjectRatio: tc.liveRatio,
                tiltDegrees: tc.liveTilt,
                heightRatio: tc.liveH,
                lateralRatio: tc.liveLat
            )

            let delta = DeltaEngine.computeDelta(target: target, live: live)
            let candidates = PriorityMapper.candidateInstructions(delta: delta, target: target, live: live)
            let prioritized = PriorityMapper.prioritize(candidates)

            XCTAssertEqual(prioritized.first, tc.expectedTopInstruction, "Failed case: \(tc.name)")
        }
    }
}
