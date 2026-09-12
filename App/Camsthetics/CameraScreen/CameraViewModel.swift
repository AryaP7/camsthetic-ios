import Foundation
import Observation
import CoreGraphics
import UIKit
import CamstheticsServices
import CamstheticsEngine
import CamstheticsUI

// MARK: - Phase 2 Step 3 — real camera screen view model (App target only)
//
// Owns the real `CameraService`/`MotionService` AND a `CamstheticsUI
// .CameraMockupState`, and keeps the latter's read-only presentation
// fields (health, lens options, roll/level) synced from the real services.
// Lives in the App target — never `CamstheticsServices` or `CamstheticsUI`
// — specifically so those two targets stay free of a dependency edge on
// each other (`Package.swift`'s `dependencies: []` on both), per the
// approved plan.
//
// `CameraMockupState` is `final` and its interaction methods
// (`selectLens`, `triggerMockCapture`, …) are its own — this type cannot
// subclass or override them. So the OUTGOING direction (user tap → real
// hardware call) is wired by observing the exact state properties those
// methods mutate via `withObservationTracking`, then issuing the matching
// real call once the mock's own optimistic UI update has already landed.
// This is deliberate, not a workaround: the UI updates instantly (same
// feel as the pure mockup), and the hardware follows.
@MainActor
@Observable
final class CameraViewModel {
    let cameraService = CameraService()
    let motionService = MotionService()
    let visionService = VisionService()
    let state = CameraMockupState()

    /// The real lens options last received from `CameraService`, kept
    /// alongside `state.lensOptions` (the `MockLensOption` projection of
    /// the same list) so a real `selectLens(_:)` call can be issued when
    /// the UI's `selectedLensID` changes.
    private var realLensOptions: [LensOption] = []
    private var lastObservedLensID: String?
    private var lastObservedShutterPressed = false
    private var lastObservedExposureBiasEV: Double = 0

    /// The value `CameraService.setExposureTargetBias` actually applied
    /// (post-clamp), for on-screen/diagnostic verification that dragging
    /// the exposure slider really reaches hardware — not just
    /// `CameraMockupState.exposureBiasEV`, which updates optimistically
    /// whether or not the real call ever fires.
    private(set) var appliedExposureBiasEV: Float?

    /// The latest `VisionService` observation, updated at 10Hz. Downstream
    /// consumers (Phase 5's coaching coordinator) read this — not
    /// `VisionService.latestObservation`, which requires an actor hop.
    private(set) var currentObservation: VisionObservation?

    /// Top-ranked candidate from the latest observation, selected by
    /// `SubjectSelector.scoreCandidate` — the same scoring used in the
    /// standalone `VisionSmokeTestView`. `nil` when no candidates are
    /// detected or no observations have arrived yet.
    private(set) var topCandidate: SubjectCandidate?

    /// Most recent hardware error, auto-cleared after a short delay.
    /// Displayed as a brief toast by `CameraScreen`.
    private(set) var lastError: String?
    private var errorClearTask: Task<Void, Never>?

    /// The most recently captured photo, decoded for on-screen review —
    /// closes a real gap the user caught: `PreviewValidationScaffold.swift`
    /// already had a pinch-zoom/pan review viewer
    /// (`CapturedPhotoInspectorView`) for exactly this, but it was never
    /// carried into this production screen, so captures here previously
    /// vanished silently. `nil` hides the review sheet; set back to `nil`
    /// by `CameraScreen` on dismiss. Still explicitly NOT a Photos-library
    /// save — that's Phase 6 (`PRODUCT_SPEC.md` §1.6); this is same-session
    /// in-memory review only, matching what the scaffold already did.
    var capturedArtifactForReview: (image: UIImage, label: String)?

    private var didStart = false

    /// Starts authorization → session → motion, then begins every
    /// observation loop. Idempotent — a second call (e.g. `.task` re-firing
    /// on a SwiftUI re-render) is a no-op.
    func start() async {
        guard !didStart else { return }
        didStart = true

        state.cameraHealth = .starting
        guard await cameraService.requestAuthorizationIfNeeded() else {
            state.cameraHealth = .permissionDenied
            return
        }

        do {
            try await cameraService.start()
        } catch {
            state.cameraHealth = .failed(description: error.localizedDescription)
            return
        }

        // Sensor-only, best-effort: a device/simulator with no motion
        // hardware must not block the camera screen itself (spirit level
        // simply never leaves its mock default in that case).
        try? await motionService.start()

        observeSelectedLensID()
        observeShutterPress()
        observeExposureBias()

        async let health: () = observeHealth()
        async let lensOptions: () = observeLensOptions()
        async let motion: () = observeMotion()
        async let vision: () = runVisionPipeline()
        _ = await (health, lensOptions, motion, vision)
    }

    /// Updates `state.selectedLensID` to whichever real lens option is
    /// nearest `rawZoomFactor`, so `LensZoomPill`'s highlight tracks a live
    /// continuous pinch the way native camera apps do — WITHOUT triggering
    /// `observeSelectedLensID()`'s real `CameraService.selectLens(_:)` call
    /// (a ramped, discrete-button transition that would fight a
    /// simultaneously-issued frame-by-frame `setZoomFactor(_:)` from the
    /// pinch gesture itself). Setting `lastObservedLensID` in lockstep is
    /// what suppresses that: `observeSelectedLensID()` only calls hardware
    /// when it sees a value it hasn't already recorded as the last one it
    /// (or this method) applied.
    func updateSelectedLensToNearest(rawZoomFactor: CGFloat) {
        guard let match = realLensOptions.min(by: {
            abs(Double($0.zoomFactor) - Double(rawZoomFactor)) < abs(Double($1.zoomFactor) - Double(rawZoomFactor))
        }) else { return }
        lastObservedLensID = match.id
        state.selectedLensID = match.id
    }

    // MARK: Real → mock (read-only sync)

    private func observeHealth() async {
        for await health in await cameraService.healthUpdates() {
            state.cameraHealth = Self.presentation(for: health)
        }
    }

    private func observeLensOptions() async {
        for await options in await cameraService.lensOptionsUpdates() {
            realLensOptions = options
            state.lensOptions = options.map {
                MockLensOption(id: $0.id, label: $0.label, zoomFactor: Double($0.zoomFactor))
            }
            // Keep the UI's current selection consistent with the real
            // list — e.g. the very first delivery, before any tap has
            // happened, should reflect whichever lens the session actually
            // started on rather than the mock's hard-coded default.
            let currentFactor = await cameraService.currentVideoZoomFactor
            if let match = options.min(by: {
                abs(Double($0.zoomFactor) - Double(currentFactor)) < abs(Double($1.zoomFactor) - Double(currentFactor))
            }) {
                lastObservedLensID = match.id
                state.selectedLensID = match.id
                state.currentZoomFactor = Double(match.zoomFactor)
            }
        }
    }

    private func observeMotion() async {
        for await attitude in await motionService.attitudeUpdates() {
            state.rollDegrees = attitude.rollDegrees
            state.isLevel = AttitudeMath.isLevel(rollDegrees: attitude.rollDegrees)
        }
    }

    /// Wires `CameraService`'s analysis frames into `VisionService` and
    /// observes the resulting observations — the same pattern
    /// `VisionSmokeTestView` uses (lines 70-73), lifted into the
    /// production view model so candidates flow to Phase 5's coaching
    /// coordinator rather than a throwaway overlay.
    private func runVisionPipeline() async {
        let frames = await cameraService.analysisFrameUpdates()
        async let consuming: () = visionService.consume(frames)
        async let observing: () = observeVisionOutput()
        _ = await (consuming, observing)
    }

    private func observeVisionOutput() async {
        for await observation in await visionService.observationUpdates() {
            currentObservation = observation
            topCandidate = observation.candidates.max {
                SubjectSelector.scoreCandidate($0) < SubjectSelector.scoreCandidate($1)
            }
        }
    }

    // MARK: Error surfacing

    /// Sets `lastError` and schedules an auto-clear after 3 seconds.
    /// Subsequent errors restart the timer so only the latest is visible.
    private func surfaceError(_ error: Error) {
        lastError = error.localizedDescription
        errorClearTask?.cancel()
        errorClearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.lastError = nil
        }
    }

    // MARK: Mock → real (outgoing hardware calls)

    /// Re-registers itself after every fire — `withObservationTracking`'s
    /// `onChange` fires exactly once per registration, per Swift's
    /// Observation framework contract.
    private func observeSelectedLensID() {
        withObservationTracking {
            _ = state.selectedLensID
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                let newID = self.state.selectedLensID
                if newID != self.lastObservedLensID {
                    self.lastObservedLensID = newID
                    if let match = self.realLensOptions.first(where: { $0.id == newID }) {
                        do {
                            try await self.cameraService.selectLens(match)
                        } catch {
                            self.surfaceError(error)
                        }
                    }
                }
                self.observeSelectedLensID()
            }
        }
    }

    private func observeShutterPress() {
        withObservationTracking {
            _ = state.isShutterPressed
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                let pressed = self.state.isShutterPressed
                if pressed && !self.lastObservedShutterPressed {
                    self.lastObservedShutterPressed = true
                    await self.capturePhoto()
                } else if !pressed {
                    self.lastObservedShutterPressed = false
                }
                self.observeShutterPress()
            }
        }
    }

    /// `FocusExposureReticle`'s sun-icon drag/VoiceOver-adjust ONLY ever
    /// mutated `CameraMockupState.exposureBiasEV` — this was a genuine gap
    /// (never wired to `CameraService.setExposureTargetBias` at all, not a
    /// subtle hardware-visibility issue like tap-to-focus). Same
    /// observation-tracking pattern as lens selection/shutter above.
    private func observeExposureBias() {
        withObservationTracking {
            _ = state.exposureBiasEV
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                let newValue = self.state.exposureBiasEV
                if newValue != self.lastObservedExposureBiasEV {
                    self.lastObservedExposureBiasEV = newValue
                    do {
                        self.appliedExposureBiasEV = try await self.cameraService.setExposureTargetBias(Float(newValue))
                    } catch {
                        // See `observeSelectedLensID()`'s equivalent comment: no
                        // error-surfacing affordance in `CameraMockupState` yet.
                        self.surfaceError(error)
                    }
                }
                self.observeExposureBias()
            }
        }
    }

    private func capturePhoto() async {
        do {
            let artifact = try await cameraService.capturePhoto()
            // Decodes the SAME unmodified bytes `capturePhoto()` returned —
            // this never resizes/re-encodes them, matching
            // `CapturedPhotoInspectorView`'s own documented contract.
            guard let image = UIImage(data: artifact.data) else { return }
            let zoomLabel = await cameraService.displayLabel(forRawZoomFactor: CGFloat(state.currentZoomFactor))
            capturedArtifactForReview = (
                image: image,
                label: "\(zoomLabel) — \(Int(image.size.width))×\(Int(image.size.height))"
            )
        } catch {
            surfaceError(error)
        }
    }

    // MARK: Tap-to-focus (wired directly — no tracking needed, see
    // `CameraPreviewView.onTapToFocus`)

    func focusAndExpose(atDevicePoint devicePoint: CGPoint, viewPoint: CGPoint) {
        state.focusAndExpose(at: viewPoint)
        Task {
            do {
                try await cameraService.focusAndExpose(atDevicePoint: devicePoint)
            } catch {
                surfaceError(error)
            }
        }
    }

    // MARK: TEMPORARY — machine-readable status for XCUITest automation
    // (see `CameraScreen.swift`'s debug status Text). `pipe|key=value`
    // rather than free text so a test can split/parse it without brittle
    // string-prefix matching.
    var debugStatusLine: String {
        let exposureApplied = appliedExposureBiasEV.map { String(format: "%.2f", $0) } ?? "nil"
        let candidateInfo = topCandidate.map {
            "category=\($0.category.rawValue) conf=\(String(format: "%.2f", $0.confidence))"
        } ?? "none"
        return "health=\(state.cameraHealth)|lens=\(state.selectedLensID)|zoom=\(state.currentZoomFactor)"
            + "|exposureRequested=\(String(format: "%.2f", state.exposureBiasEV))|exposureApplied=\(exposureApplied)"
            + "|reticle=\(state.reticlePosition.map { "\(Int($0.x)),\(Int($0.y))" } ?? "nil")"
            + "|isLevel=\(state.isLevel)|roll=\(String(format: "%.2f", state.rollDegrees))"
            + "|vision=\(candidateInfo)"
    }

    // MARK: CameraSessionHealth → CameraHealthPresentation

    private static func presentation(for health: CameraSessionHealth) -> CameraHealthPresentation {
        switch health {
        case .idle: .idle
        case .running: .running
        case .interrupted(let reason): .interrupted(reason: reason)
        case .recovering: .recovering
        case .failed(let description): .failed(description: description)
        }
    }
}
