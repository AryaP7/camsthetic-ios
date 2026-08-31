// CoachingInstruction.swift
// CamstheticsEngine
// Actionable human-executable camera movement instructions.

import Foundation

/// Discrete, actionable physical movement cues issued to the photographer.
public enum CoachingInstruction: Equatable, Hashable, Codable, Sendable {
    // Tilt / Roll
    case rotateClockwise(degrees: Int)
    case rotateCounterClockwise(degrees: Int)

    // Lateral (Pan vs. Step disambiguated)
    case panRight
    case panLeft
    case stepRight
    case stepLeft

    // Distance
    case moveCloser
    case stepBack

    // Height
    case raisePhone
    case lowerPhone

    // Zoom Fallback
    case zoomIn
    case zoomOut

    // Guidance Prompts
    case findSubject
    case levelHorizon

    /// Associated coaching dimension for priority mapping and slot arbitration.
    @inlinable
    public var dimension: CoachingDimension {
        switch self {
        case .rotateClockwise, .rotateCounterClockwise, .levelHorizon:
            return .tilt
        case .panRight, .panLeft, .stepRight, .stepLeft:
            return .lateral
        case .moveCloser, .stepBack:
            return .distance
        case .raisePhone, .lowerPhone:
            return .height
        case .zoomIn, .zoomOut:
            return .zoom
        case .findSubject:
            return .lateral
        }
    }

    /// User-facing text string matching PRODUCT_SPEC.md 1.3.2 templates.
    public var displayText: String {
        switch self {
        case .rotateClockwise(let degrees):
            return "Rotate right \(degrees)°"
        case .rotateCounterClockwise(let degrees):
            return "Rotate left \(degrees)°"
        case .panRight:
            return "Pan right"
        case .panLeft:
            return "Pan left"
        case .stepRight:
            return "Step right"
        case .stepLeft:
            return "Step left"
        case .moveCloser:
            return "Move closer"
        case .stepBack:
            return "Step back"
        case .raisePhone:
            return "Raise phone"
        case .lowerPhone:
            return "Lower phone"
        case .zoomIn:
            return "Zoom in a touch"
        case .zoomOut:
            return "Zoom out a touch"
        case .findSubject:
            return "Find your subject"
        case .levelHorizon:
            return "Level horizon"
        }
    }

    /// Associated SF Symbol name for the instruction badge.
    public var sfSymbolName: String {
        switch self {
        case .rotateClockwise:
            return "arrow.clockwise"
        case .rotateCounterClockwise:
            return "arrow.counterclockwise"
        case .panRight, .stepRight:
            return "arrow.right"
        case .panLeft, .stepLeft:
            return "arrow.left"
        case .moveCloser:
            return "arrow.down.forward.and.arrow.up.backward"
        case .stepBack:
            return "arrow.up.forward.and.arrow.down.backward"
        case .raisePhone:
            return "arrow.up"
        case .lowerPhone:
            return "arrow.down"
        case .zoomIn:
            return "plus.magnifyingglass"
        case .zoomOut:
            return "minus.magnifyingglass"
        case .findSubject:
            return "person.crop.circle.badge.questionmark"
        case .levelHorizon:
            return "camera.metering.matrix"
        }
    }
}
