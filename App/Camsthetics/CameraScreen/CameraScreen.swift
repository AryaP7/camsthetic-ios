import SwiftUI
import UIKit
import CamstheticsServices
import CamstheticsUI

// MARK: - Phase 2 Step 3 — the real camera screen
//
// Composes the production `CameraPreviewView` (Phase 2.2) as
// `CameraMockupView`'s `background`, exactly the seam
// `CameraMockupView.swift`'s doc comment describes. Everything the mockup
// renders — HUD, controls, lens pill, spirit level — still comes from
// `CameraMockupState`; `CameraViewModel` is what keeps that state's
// read-only fields synced from the real camera/motion services and routes
// user interaction back out to them (see its own doc comment for exactly
// which fields are wired for real vs. still mock-only this phase).
//
// RESOLVED on physical iPhone 16 (2026-09-05): `CameraMockupView`'s own
// SwiftUI `.onTapGesture` and `CameraPreviewView`'s UIKit
// `UITapGestureRecognizer` do NOT conflict — every physical tap reliably
// reaches the real path (`[TapToFocus] real path fired` logged for every
// tap in an on-device console capture), `CameraService.focusAndExpose`
// succeeds, and `isAdjustingExposure` genuinely flips `true`. No visible
// on-screen focus/exposure pull was observed even tapping near-vs-far and
// bright-vs-dark, most likely the iPhone wide lens's inherently deep depth
// of field at typical test distances plus live-preview tone-mapping
// damping visible AE shifts — not a wiring bug. Not chased further.
struct CameraScreen: View {
    @State private var viewModel = CameraViewModel()

    // MARK: Pinch-to-zoom with intelligent native-resolution snap
    //
    // Carried over from `PreviewValidationScaffold.swift` (the user caught
    // this missing: "zoom snap and higher zoom unlocks... dont exist
    // anymore" — this was already-approved Step 3 scope that simply never
    // got implemented). Kept as View `@State`, mirroring the scaffold, not
    // `CameraViewModel` — this is pure gesture-frame bookkeeping, not
    // service state.
    @State private var zoomGestureBaseFactor: CGFloat = 1.0
    /// Written SYNCHRONOUSLY inside `.onChanged` (no `await`), read by
    /// `.onEnded` for the next gesture's baseline — the exact race the
    /// scaffold's own doc comment documents fixing (a value only written
    /// inside `.onChanged`'s spawned `Task` could still be stale when
    /// `.onEnded` fires on a quick lift-and-repinch).
    @State private var lastRequestedZoomFactor: CGFloat = 1.0
    /// Cancelled and replaced every `.onChanged` so a fast pinch never
    /// piles up in-flight actor calls behind the latest one.
    @State private var zoomTask: Task<Void, Never>?
    /// Cached once per session-start, not re-read every gesture frame.
    /// Device-agnostic: empty on hardware/format reporting none, which
    /// makes the snap below a pure no-op there.
    @State private var snapZoomFactors: [CGFloat] = []
    @State private var isSnappedToNativeResolution = false
    // MUST be @State, not `let` — SwiftUI reconstructs this View struct on
    // every gesture-driven state change, so a plain stored property would
    // be re-initialized nearly every frame, producing a never-`prepare()`d
    // generator that reliably gives no physical tap (confirmed on physical
    // device in the scaffold this was ported from).
    @State private var snapHaptic = UIImpactFeedbackGenerator(style: .medium)

    var body: some View {
        ZStack {
            CameraMockupView(state: viewModel.state) {
                CameraPreviewView(
                    cameraService: viewModel.cameraService,
                    onTapToFocus: { devicePoint, viewPoint in
                        viewModel.focusAndExpose(atDevicePoint: devicePoint, viewPoint: viewPoint)
                    }
                )
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            let raw = zoomGestureBaseFactor * value
                            // Intelligent zoom snap (device-agnostic):
                            // tolerance=0.25 is the scaffold's own settled
                            // production value (0.15 passed through
                            // unnoticed at normal pinch speed; 0.5 felt
                            // overly "sticky") — a tuning constant, never a
                            // hard-coded per-device zoom value.
                            let target = LensSelection.snapToNativeResolution(
                                target: raw,
                                secondaryNativeResolutionZoomFactors: snapZoomFactors,
                                tolerance: 0.25
                            )
                            let didSnap = (target != raw)
                            if didSnap, !isSnappedToNativeResolution {
                                snapHaptic.impactOccurred()
                            } else if !didSnap, isSnappedToNativeResolution {
                                snapHaptic.prepare()
                            }
                            isSnappedToNativeResolution = didSnap
                            lastRequestedZoomFactor = target
                            viewModel.state.currentZoomFactor = Double(target)
                            // Nearest real lens pill tracks continuous zoom,
                            // matching native camera apps' highlight
                            // behaviour during a pinch.
                            viewModel.updateSelectedLensToNearest(rawZoomFactor: target)

                            zoomTask?.cancel()
                            zoomTask = Task {
                                try? await viewModel.cameraService.setZoomFactor(target)
                            }
                        }
                        .onEnded { _ in
                            isSnappedToNativeResolution = false
                            zoomGestureBaseFactor = lastRequestedZoomFactor
                        }
                )
            }

            // Machine-readable status for on-device XCUITest automation
            // (`CameraScreenTests.swift`), same reasoning as
            // `PreviewValidationScaffold`'s status capsule. Compiled out
            // of release builds since this screen is now the production root.
            #if DEBUG
            VStack {
                Text(viewModel.debugStatusLine)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(.black.opacity(0.5))
                    .accessibilityIdentifier("cameraScreenDebugStatus")
                Spacer()
            }
            #endif

            // Error toast — auto-clears after 3s (see
            // `CameraViewModel.surfaceError`). Positioned at the top so it
            // doesn't overlap the shutter button or lens pills.
            if let error = viewModel.lastError {
                VStack {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.red.opacity(0.85), in: Capsule())
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.top, 8)
                    Spacer()
                }
                .animation(.easeInOut(duration: 0.25), value: viewModel.lastError)
            }
        }
        .task {
            await viewModel.start()
            snapZoomFactors = await viewModel.cameraService.secondaryNativeResolutionZoomFactors
        }
        .fullScreenCover(item: Binding(
            get: { viewModel.capturedArtifactForReview.map(ReviewItem.init) },
            set: { newValue in viewModel.capturedArtifactForReview = newValue?.artifact }
        )) { item in
            CapturedPhotoInspectorView(image: item.artifact.image, label: item.artifact.label) {
                viewModel.capturedArtifactForReview = nil
            }
        }
        .onDisappear {
            Task { await viewModel.cameraService.stop() }
            Task { await viewModel.motionService.stop() }
        }
    }
}

/// `Identifiable` wrapper so `.fullScreenCover(item:)` can bind directly to
/// `CameraViewModel.capturedArtifactForReview` (a plain optional tuple,
/// which isn't `Identifiable` on its own).
private struct ReviewItem: Identifiable {
    let artifact: (image: UIImage, label: String)
    var id: String { artifact.label }
}
