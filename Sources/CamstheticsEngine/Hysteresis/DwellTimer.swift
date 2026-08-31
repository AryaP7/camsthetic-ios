// DwellTimer.swift
// CamstheticsEngine
// Enforces minimum dwell times for surfaced UI instruction slots.

import Foundation

/// Manages minimum display dwell times for surfaced coaching instruction slots to prevent visual flicker.
public struct DwellTimer: Equatable, Sendable {
    /// Minimum duration (in seconds) an instruction must remain surfaced before being swapped out (PRODUCT_SPEC.md 1.3.3).
    public static let minimumDwellTime: TimeInterval = 0.70 // 700ms

    public struct SlotState: Equatable, Sendable {
        public var instruction: CoachingInstruction?
        public var displayedTimestamp: TimeInterval?
        public var activeDimension: CoachingDimension?

        public init(
            instruction: CoachingInstruction? = nil,
            displayedTimestamp: TimeInterval? = nil,
            activeDimension: CoachingDimension? = nil
        ) {
            self.instruction = instruction
            self.displayedTimestamp = displayedTimestamp
            self.activeDimension = activeDimension ?? instruction?.dimension
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

    /// Updates the slot state with a new instruction.
    public mutating func update(slot: Int, instruction: CoachingInstruction?, currentTimestamp: TimeInterval) {
        guard slot >= 0 && slot < slots.count else { return }

        let newDim = instruction?.dimension
        if slots[slot].activeDimension != newDim {
            slots[slot].displayedTimestamp = instruction != nil ? currentTimestamp : nil
            slots[slot].activeDimension = newDim
        }
        slots[slot].instruction = instruction
    }

    /// Clears the slot immediately (e.g. when error drops below exit threshold).
    public mutating func clear(slot: Int) {
        guard slot >= 0 && slot < slots.count else { return }
        slots[slot].instruction = nil
        slots[slot].displayedTimestamp = nil
        slots[slot].activeDimension = nil
    }

    /// Resets all slot timers.
    public mutating func reset() {
        for i in 0..<slots.count {
            slots[i] = SlotState()
        }
    }
}
