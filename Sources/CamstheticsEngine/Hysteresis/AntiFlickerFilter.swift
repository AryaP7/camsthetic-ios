// AntiFlickerFilter.swift
// CamstheticsEngine
// Multi-layer anti-chatter hysteresis filter and instruction surfacing arbiter.

import Foundation

/// Anti-chatter filter enforcing dual error thresholds, consecutive frame gating, and dwell timers.
public struct AntiFlickerFilter: Equatable, Sendable {
    /// Number of consecutive candidate frames required for an instruction to appear (PRODUCT_SPEC.md 1.3.3).
    public static let requiredEntryFrames: Int = 3

    /// Number of consecutive absent frames required for an active instruction to disappear (PRODUCT_SPEC.md 1.3.3).
    public static let requiredExitFrames: Int = 4

    /// Minimum dwell time in seconds before an active surfaced cue can be replaced.
    public static let minimumDwellTime: TimeInterval = 0.70

    /// Maximum number of instructions surfaced simultaneously.
    public static let maxSurfacedInstructions: Int = 2

    /// Tracking state for an individual coaching dimension.
    public struct DimensionState: Equatable, Sendable {
        public var isActive: Bool = false
        public var consecutiveCandidateFrames: Int = 0
        public var consecutiveAbsentFrames: Int = 0
        public var currentInstruction: CoachingInstruction?
    }

    private var dimensionStates: [CoachingDimension: DimensionState]
    private var dwellTimer: DwellTimer

    public init() {
        var states = [CoachingDimension: DimensionState]()
        for dim in CoachingDimension.allCases {
            states[dim] = DimensionState()
        }
        self.dimensionStates = states
        self.dwellTimer = DwellTimer(slotCount: Self.maxSurfacedInstructions)
    }

    /// Evaluates error magnitude against entry/exit thresholds for a dimension.
    public static func errorMagnitude(dimension: CoachingDimension, delta: CompositionDelta) -> Double {
        switch dimension {
        case .tilt:
            return abs(delta.deltaTilt)
        case .lateral:
            return abs(delta.deltaLateral)
        case .distance:
            return abs(delta.distanceRatio - 1.0)
        case .height:
            return abs(delta.deltaHeight)
        case .zoom:
            return abs(delta.distanceRatio - 1.0)
        }
    }

    /// Updates the hysteresis filter with a new frame evaluation and returns surfaced instructions.
    public mutating func update(
        delta: CompositionDelta,
        target: CompositionParams,
        live: CompositionParams,
        timestamp: TimeInterval,
        useZoomFallback: Bool = false
    ) -> [CoachingInstruction] {
        // Step 1: Update per-dimension active states based on dual thresholds and consecutive frame counts
        for dim in CoachingDimension.allCases {
            var state = dimensionStates[dim] ?? DimensionState()
            let error = Self.errorMagnitude(dimension: dim, delta: delta)
            let isSuppressed = delta.isSuppressed(dim)

            if !state.isActive {
                // Not active: check entry threshold
                if !isSuppressed && error >= dim.entryTolerance {
                    state.consecutiveCandidateFrames += 1
                    state.consecutiveAbsentFrames = 0

                    if state.consecutiveCandidateFrames >= Self.requiredEntryFrames {
                        state.isActive = true
                        state.consecutiveCandidateFrames = 0
                    }
                } else {
                    state.consecutiveCandidateFrames = 0
                    state.consecutiveAbsentFrames = 0
                }
            } else {
                // Active: check exit threshold
                if isSuppressed || error < dim.exitTolerance {
                    state.consecutiveAbsentFrames += 1
                    state.consecutiveCandidateFrames = 0

                    if state.consecutiveAbsentFrames >= Self.requiredExitFrames {
                        state.isActive = false
                        state.consecutiveAbsentFrames = 0
                        state.currentInstruction = nil
                    }
                } else {
                    state.consecutiveAbsentFrames = 0
                }
            }

            dimensionStates[dim] = state
        }

        // Step 2: Generate candidate instructions for all currently active dimensions
        var activeInstructions = [CoachingInstruction]()
        for dim in CoachingDimension.allCases.sorted() {
            guard let state = dimensionStates[dim], state.isActive else { continue }

            // Construct latest instruction for this active dimension
            let candidates = PriorityMapper.candidateInstructions(
                delta: delta,
                target: target,
                live: live,
                useZoomFallback: useZoomFallback
            )
            if let match = candidates.first(where: { $0.dimension == dim }) {
                var updatedState = state
                updatedState.currentInstruction = match
                dimensionStates[dim] = updatedState
                activeInstructions.append(match)
            } else if let prev = state.currentInstruction {
                // If candidate temporarily in deadband between 0.7 and 1.0, retain previous instruction
                activeInstructions.append(prev)
            }
        }

        // Step 3: Prioritize active instructions strictly: Tilt -> Lateral -> Distance -> Height -> Zoom
        let prioritized = PriorityMapper.prioritize(activeInstructions)

        // Step 4: Manage Dwell Timer slots
        var surfaced = [CoachingInstruction]()

        for slotIndex in 0..<Self.maxSurfacedInstructions {
            let currentInSlot = dwellTimer.currentInstruction(slot: slotIndex)

            if slotIndex < prioritized.count {
                let desiredInstruction = prioritized[slotIndex]

                if let current = currentInSlot {
                    // If the desired instruction is for the same dimension, update it immediately (e.g. angle update)
                    if current.dimension == desiredInstruction.dimension {
                        dwellTimer.update(slot: slotIndex, instruction: desiredInstruction, currentTimestamp: timestamp)
                        surfaced.append(desiredInstruction)
                    } else if !activeInstructions.contains(where: { $0.dimension == current.dimension }) {
                        // Current dimension has exited: replace immediately
                        dwellTimer.update(slot: slotIndex, instruction: desiredInstruction, currentTimestamp: timestamp)
                        surfaced.append(desiredInstruction)
                    } else if dwellTimer.canReplace(slot: slotIndex, currentTimestamp: timestamp) {
                        // Dwell time has elapsed: allow higher priority replacement
                        dwellTimer.update(slot: slotIndex, instruction: desiredInstruction, currentTimestamp: timestamp)
                        surfaced.append(desiredInstruction)
                    } else {
                        // Hold current instruction until dwell time completes
                        surfaced.append(current)
                    }
                } else {
                    // Empty slot: surface new instruction immediately
                    dwellTimer.update(slot: slotIndex, instruction: desiredInstruction, currentTimestamp: timestamp)
                    surfaced.append(desiredInstruction)
                }
            } else {
                // No candidate for this slot
                if let current = currentInSlot {
                    if !activeInstructions.contains(where: { $0.dimension == current.dimension }) {
                        dwellTimer.clear(slot: slotIndex)
                    } else if dwellTimer.canReplace(slot: slotIndex, currentTimestamp: timestamp) {
                        dwellTimer.clear(slot: slotIndex)
                    } else {
                        surfaced.append(current)
                    }
                }
            }
        }

        // Deduplicate surfaced output so each dimension appears at most once
        var uniqueSurfaced = [CoachingInstruction]()
        var seenDimensions = Set<CoachingDimension>()
        for instr in surfaced {
            if !seenDimensions.contains(instr.dimension) {
                seenDimensions.insert(instr.dimension)
                uniqueSurfaced.append(instr)
            }
        }

        return uniqueSurfaced
    }

    /// Resets all hysteresis counters and dwell timers.
    public mutating func reset() {
        for dim in CoachingDimension.allCases {
            dimensionStates[dim] = DimensionState()
        }
        dwellTimer.reset()
    }
}

/// Type alias for HysteresisFilter as specified in IMPLEMENTATION_PLAN.md.
public typealias HysteresisFilter = AntiFlickerFilter
