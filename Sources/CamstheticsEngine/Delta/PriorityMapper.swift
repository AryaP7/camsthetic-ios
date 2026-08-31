// PriorityMapper.swift
// CamstheticsEngine
// Mapping raw geometric deltas to human-executable instructions and priority ordering.

import Foundation

/// Maps geometric deltas to prioritized human-executable movement instructions.
public enum PriorityMapper {
    /// Evaluates raw delta against entry tolerances and produces candidate instructions for each active dimension.
    public static func candidateInstructions(
        delta: CompositionDelta,
        target: CompositionParams,
        live: CompositionParams,
        useZoomFallback: Bool = false
    ) -> [CoachingInstruction] {
        var candidates = [CoachingInstruction]()

        // 1. Roll / Tilt Dimension (Priority 0)
        if !delta.isSuppressed(.tilt) {
            let absTilt = abs(delta.deltaTilt)
            if absTilt >= CoachingDimension.tilt.entryTolerance {
                let roundedDeg = max(1, Int(round(absTilt)))
                if delta.deltaTilt > 0.0 {
                    candidates.append(.rotateClockwise(degrees: roundedDeg))
                } else {
                    candidates.append(.rotateCounterClockwise(degrees: roundedDeg))
                }
            }
        }

        // 2. Lateral Dimension (Priority 1)
        if !delta.isSuppressed(.lateral) {
            let absLat = abs(delta.deltaLateral)
            if absLat >= CoachingDimension.lateral.entryTolerance {
                // Lateral Kind Disambiguation:
                // If subject size and height match within tolerance, instruct "Pan".
                // Otherwise instruct "Step".
                let sizeMatches = abs(delta.distanceRatio - 1.0) <= CoachingDimension.distance.entryTolerance
                let heightMatches = abs(delta.deltaHeight) <= CoachingDimension.height.entryTolerance

                let isPan = sizeMatches && heightMatches

                if delta.deltaLateral > 0.0 {
                    candidates.append(isPan ? .panRight : .stepRight)
                } else {
                    candidates.append(isPan ? .panLeft : .stepLeft)
                }
            }
        }

        // 3. Distance Dimension (Priority 2)
        if !delta.isSuppressed(.distance) {
            if useZoomFallback {
                if delta.distanceRatio > (1.0 + CoachingDimension.distance.entryTolerance) {
                    candidates.append(.zoomIn)
                } else if delta.distanceRatio < (1.0 - CoachingDimension.distance.entryTolerance) {
                    candidates.append(.zoomOut)
                }
            } else {
                if delta.distanceRatio > (1.0 + CoachingDimension.distance.entryTolerance) {
                    candidates.append(.moveCloser)
                } else if delta.distanceRatio < (1.0 - CoachingDimension.distance.entryTolerance) {
                    candidates.append(.stepBack)
                }
            }
        }

        // 4. Height Dimension (Priority 3)
        if !delta.isSuppressed(.height) {
            let absH = abs(delta.deltaHeight)
            if absH >= CoachingDimension.height.entryTolerance {
                if delta.deltaHeight > 0.0 {
                    candidates.append(.raisePhone)
                } else {
                    candidates.append(.lowerPhone)
                }
            }
        }

        return candidates
    }

    /// Sorts and filters candidate instructions according to strict priority order.
    /// PRODUCT_SPEC.md 1.3.3: Prioritized strictly in order: Tilt -> Lateral -> Distance -> Height -> Zoom.
    public static func prioritize(_ instructions: [CoachingInstruction]) -> [CoachingInstruction] {
        instructions.sorted { $0.dimension < $1.dimension }
    }

    /// Caps surfaced instructions to at most `maxCount` (default 2) highest-priority cues.
    public static func surfaceTopInstructions(
        _ instructions: [CoachingInstruction],
        maxCount: Int = 2
    ) -> [CoachingInstruction] {
        Array(prioritize(instructions).prefix(maxCount))
    }
}
