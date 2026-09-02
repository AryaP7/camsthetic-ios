// DwellTimer.swift
// CamstheticsEngine
// Enforces minimum dwell times for surfaced UI instruction slots.

import Foundation

/// Manages minimum display dwell times for surfaced coaching instruction slots to prevent visual flicker.
public struct DwellTimer: Equatable, Sendable {
    /// Minimum duration (in seconds) an instruction must remain surfaced before being swapped out (PRODUCT_SPEC.md 1.3.3).
    public static let minimumDwellTime: TimeInterval = 0.70

    /// Identity of a dwelling cue: coaching dimension plus the direction / semantic form of the instruction.
    ///
    /// Numeric refinement parameters (e.g. rotation degrees) are deliberately excluded so that a continuously
    /// refined angle (`rotateClockwise(5°) -> rotateClockwise(4°) -> rotateClockwise(3°)`) is treated as the
    /// *same* dwelling instruction and keeps its running 700ms dwell window, while a genuine dimension or
    /// direction change (e.g. `rotateClockwise -> rotateCounterClockwise`, `panRight -> stepRight`) restarts it.
    public struct InstructionIdentity: Equatable, Hashable, Sendable {
        /// Coaching dimension the instruction belongs to.
        public let dimension: CoachingDimension

        /// Direction / semantic form of the instruction, independent of any numeric parameter.
        public let semantic: String

        public init(dimension: CoachingDimension, semantic: String) {
            self.dimension = dimension
            self.semantic = semantic
        }
    }

    /// Derives the dwell identity of an instruction (dimension + direction/semantic form, ignoring numeric parameters).
    public static func identity(for instruction: CoachingInstruction) -> InstructionIdentity {
        let semantic: String
        switch instruction {
        case .rotateClockwise:
            semantic = "rotateClockwise"
        case .rotateCounterClockwise:
            semantic = "rotateCounterClockwise"
        case .panRight:
            semantic = "panRight"
        case .panLeft:
            semantic = "panLeft"
        case .stepRight:
            semantic = "stepRight"
        case .stepLeft:
            semantic = "stepLeft"
        case .moveCloser:
            semantic = "moveCloser"
        case .stepBack:
            semantic = "stepBack"
        case .raisePhone:
            semantic = "raisePhone"
        case .lowerPhone:
            semantic = "lowerPhone"
        case .zoomIn:
            semantic = "zoomIn"
        case .zoomOut:
            semantic = "zoomOut"
        case .findSubject:
            semantic = "findSubject"
        case .levelHorizon:
            semantic = "levelHorizon"
        }
        return InstructionIdentity(dimension: instruction.dimension, semantic: semantic)
    }

    public struct SlotState: Equatable, Sendable {
        public var instruction: CoachingInstruction?
        public var displayedTimestamp: TimeInterval?
        public var activeIdentity: InstructionIdentity?

        /// Coaching dimension currently occupying the slot, if any.
        @inlinable
        public var activeDimension: CoachingDimension? {
            activeIdentity?.dimension
        }

        public init(
            instruction: CoachingInstruction? = nil,
            displayedTimestamp: TimeInterval? = nil,
            activeIdentity: InstructionIdentity? = nil
        ) {
            self.instruction = instruction
            self.displayedTimestamp = displayedTimestamp
            self.activeIdentity = activeIdentity ?? instruction.map(DwellTimer.identity(for:))
        }
    }

    private var slots: [SlotState]

    public init(slotCount: Int = 2) {
        self.slots = Array(repeating: SlotState(), count: slotCount)
    }

    /// Checks if a surfaced slot is eligible to be replaced by a new instruction at the current timestamp.
    public func canReplace(slot: Int, currentTimestamp: TimeInterval) -> Bool {
        guard slot >= 0 && slot < slots.count else { return true }
        guard let displayed = slots[slot].displayedTimestamp else { return true }
        return (currentTimestamp - displayed) >= Self.minimumDwellTime
    }

    /// Gets the current instruction in the specified slot.
    public func currentInstruction(slot: Int) -> CoachingInstruction? {
        guard slot >= 0 && slot < slots.count else { return nil }
        return slots[slot].instruction
    }

    /// Gets the dwell identity currently occupying the specified slot.
    public func currentIdentity(slot: Int) -> InstructionIdentity? {
        guard slot >= 0 && slot < slots.count else { return nil }
        return slots[slot].activeIdentity
    }

    /// Updates the slot state with a new instruction.
    ///
    /// The dwell window is restarted only when the *identity* of the instruction changes (dimension or
    /// direction/semantic form). Numeric refinement of the same instruction updates the displayed value
    /// while the running 700ms dwell timer continues uninterrupted.
    public mutating func update(slot: Int, instruction: CoachingInstruction?, currentTimestamp: TimeInterval) {
        guard slot >= 0 && slot < slots.count else { return }

        let newIdentity = instruction.map(Self.identity(for:))
        if slots[slot].activeIdentity != newIdentity {
            slots[slot].displayedTimestamp = instruction != nil ? currentTimestamp : nil
            slots[slot].activeIdentity = newIdentity
        }
        slots[slot].instruction = instruction
    }

    /// Clears the slot immediately (e.g. when error drops below exit threshold).
    public mutating func clear(slot: Int) {
        guard slot >= 0 && slot < slots.count else { return }
        slots[slot].instruction = nil
        slots[slot].displayedTimestamp = nil
        slots[slot].activeIdentity = nil
    }

    /// Resets all slot timers.
    public mutating func reset() {
        for i in 0..<slots.count {
            slots[i] = SlotState()
        }
    }
}
