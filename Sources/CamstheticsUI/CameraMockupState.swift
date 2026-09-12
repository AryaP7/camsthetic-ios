import Foundation
import CoreGraphics

// MARK: - Mock state for the camera UI mockup (Track B)
//
// Deliberately NOT a `CameraService`/`CoachingSessionCoordinator`
// substitute — no AVFoundation, no CamstheticsEngine, no real device
// values anywhere in this file. Every value here is either a fixed mock
// default or mutated by mock UI interactions. Its shape mirrors what the
// real capture/coaching layers will eventually need to inject (lens
// options, match score, instruction copy, roll angle, exposure bias,
// focal length) — see `CameraMockupView.swift`'s doc comment for how a
// real state source could replace this later without restructuring the
// layout.

/// One selectable lens/zoom pill, mirroring the shape of
/// `CamstheticsServices.LensOption` (Track A) without depending on it —
/// this module has zero dependency on `CamstheticsServices`.
public struct MockLensOption: Identifiable, Equatable, Sendable {
    public let id: String
    public let label: String
    /// Mirrors `LensOption.zoomFactor` — the raw zoom value this pill
    /// represents, kept separate from `label` so a UI-level "current zoom"
    /// readout (e.g. during a drag/ramp) doesn't have to parse display text.
    public let zoomFactor: Double

    public init(id: String, label: String, zoomFactor: Double) {
        self.id = id
        self.label = label
        self.zoomFactor = zoomFactor
    }
}

/// UI-facing presentation of camera session health. Deliberately NOT
/// `CamstheticsServices.CameraSessionHealth` — this module has zero
/// dependency on `CamstheticsServices` (Track A/Track B architectural
/// separation; `CameraMockupView.swift`'s doc comment explains the same
/// principle for the preview background). A future integration layer
/// (in the App target, alongside where `CameraPreviewView.swift` already
/// bridges `CamstheticsServices` to SwiftUI) maps the real
/// `CameraSessionHealth` plus `CameraService.authorizationStatus` into
/// this shape — `.starting` and `.permissionDenied` have no direct
/// `CameraSessionHealth` equivalent (they're derived from the moment
/// `start()` is awaited, and from `AVAuthorizationStatus`, respectively).
public enum CameraHealthPresentation: Equatable, Sendable {
    case idle
    case starting
    case running
    case interrupted(reason: String)
    case recovering
    case failed(description: String)
    case permissionDenied
}

/// The four documented capture modes — `docs/DESIGN_SYSTEM.md` §4's mode
/// carousel (`PHOTO COACH SCAN PORTRAIT`).
public enum CaptureMode: String, CaseIterable, Identifiable, Sendable {
    case photo = "PHOTO"
    case coach = "COACH"
    case scan = "SCAN"
    case portrait = "PORTRAIT"

    public var id: String { rawValue }
}

@MainActor
@Observable
public final class CameraMockupState {

    // Mode
    public var selectedMode: CaptureMode = .coach

    // Lens / zoom — mirrors DESIGN_SYSTEM.md §4's `.5 / 1x / 2 / 3` capsule.
    public var lensOptions: [MockLensOption] = [
        MockLensOption(id: "0.5", label: ".5", zoomFactor: 0.5),
        MockLensOption(id: "1", label: "1x", zoomFactor: 1),
        MockLensOption(id: "2", label: "2", zoomFactor: 2),
        MockLensOption(id: "3", label: "3", zoomFactor: 3)
    ]
    public var selectedLensID: String = "1"
    /// Mirrors `CameraService.currentVideoZoomFactor` — kept as its own
    /// field (not derived from `selectedLensID`) so a future real
    /// integration can reflect an in-progress ramp's live value, not just
    /// the destination lens.
    public var currentZoomFactor: Double = 1.0

    // Camera session health — see `CameraHealthPresentation`'s doc comment.
    public var cameraHealth: CameraHealthPresentation = .running

    // Coaching HUD
    public var matchScore: Int = 62
    public var isOnTarget: Bool = false
    public var instructionSymbolName: String = "arrow.counterclockwise"
    public var instructionText: String = "Rotate left 3°"
    public var rollDegrees: Double = -3.2
    public var isLevel: Bool = false
    public var showRuleOfThirdsGrid: Bool = true

    // Tap-to-focus / exposure — DESIGN_SYSTEM.md §4 item, PRODUCT_SPEC.md §1.5.
    public var reticlePosition: CGPoint?
    public var isExposureExpanded: Bool = false
    public var exposureBiasEV: Double = 0.0
    public var isAEAFLocked: Bool = false

    // Focal length readout (mock; structure ready for a real value later).
    public var focalLengthMM: Double = 24

    // Top status bar
    public var isFlashOn: Bool = false
    public var isRawEnabled: Bool = false
    public var isDrawerExpanded: Bool = false

    // Shutter / capture (mock only — never calls AVCapturePhotoOutput)
    public var isShutterPressed: Bool = false
    public var isAutoCaptureArmed: Bool = false
    public var autoCaptureProgress: Double?

    // Last-photo thumbnail — nil is the documented "no capture yet" empty state.
    public var lastPhotoThumbnailSystemImage: String?

    public init() {}

    // MARK: Mock interaction handlers
    //
    // These mutate only this object's own properties — never touch
    // AVFoundation, never call CameraService, never call
    // AVCapturePhotoOutput. Suitable for a demo/preview surface only.

    public func selectLens(_ option: MockLensOption) {
        selectedLensID = option.id
        currentZoomFactor = option.zoomFactor
    }

    public func selectMode(_ mode: CaptureMode) {
        selectedMode = mode
    }

    public func toggleGrid() {
        showRuleOfThirdsGrid.toggle()
    }

    public func toggleFlash() {
        isFlashOn.toggle()
    }

    public func toggleDrawer() {
        isDrawerExpanded.toggle()
    }

    public func focusAndExpose(at point: CGPoint) {
        reticlePosition = point
        isExposureExpanded = true
        isAEAFLocked = false
    }

    public func dragExposure(to ev: Double) {
        exposureBiasEV = max(-2.0, min(2.0, ev))
    }

    public func lockAEAF() {
        isAEAFLocked = true
    }

    public func clearReticle() {
        reticlePosition = nil
        isExposureExpanded = false
        isAEAFLocked = false
        exposureBiasEV = 0
    }

    /// Mock shutter press — pure visual state, never touches
    /// `AVCapturePhotoOutput`. Simulates the press/release spring and a
    /// brief "captured" flash on the thumbnail.
    public func triggerMockCapture() {
        isShutterPressed = true
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            self?.isShutterPressed = false
            self?.lastPhotoThumbnailSystemImage = "photo.fill"
        }
    }
}
