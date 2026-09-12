import SwiftUI
import AVFoundation
import CamstheticsServices

// MARK: - Phase 2.2 — Preview pipeline
//
// This is production architecture (unlike App/Camsthetics/CaptureFidelityProof/,
// which remains untouched). It hosts a live viewfinder that reads frames
// from CameraService's existing AVCaptureSession — it never creates a
// second session, never touches the bytes AVCapturePhotoOutput produces,
// and never resizes/re-encodes/processes what it displays. Preview is a
// pure display surface (docs/ARCHITECTURE.md §4.4's Preview pipeline
// contract: "Presentation only... Never [reaches disk]").
//
// This file lives in the App target rather than CamstheticsServices
// because SwiftUI has no layer-hosting API without UIKit's
// `UIViewRepresentable` (verified against Apple's current documentation:
// "SwiftUI doesn't support using layers directly, so instead, the app
// hosts this layer in a UIView subclass"), and UIKit is unavailable on
// macOS — which CamstheticsServices/CamstheticsEngine deliberately still
// build and test on (ADR-001, ARCHITECTURE.md §6.1's macOS-speed test
// tier). Keeping this UIKit-dependent wrapper in the iOS-only App target
// preserves that fast cross-platform test loop for the rest of the
// package. The idealized module path in ARCHITECTURE.md §3.1
// (`CamstheticsUI/Viewfinder/CameraPreviewView.swift`) assumes a
// UIKit-capable package target; this is a deliberate, documented
// deviation forced by that platform constraint, not a scope shortcut.

/// `UIView` subclass whose backing layer is `AVCaptureVideoPreviewLayer` —
/// the idiomatic hosting pattern per Apple's current documentation.
final class PreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        // Force-cast is safe: `layerClass` above guarantees this view's
        // backing layer is always an AVCaptureVideoPreviewLayer.
        layer as! AVCaptureVideoPreviewLayer
    }
}

/// SwiftUI wrapper hosting the live camera preview surface. Binds to
/// `CameraService`'s existing session via `attachPreviewLayer(_:)` —
/// never constructs an `AVCaptureSession` of its own.
///
/// Attaches exactly once per `PreviewUIView`'s lifetime (in `makeUIView`),
/// not on every `updateUIView` call. Previously this attached on every
/// SwiftUI re-render (e.g. whenever `CameraPreviewView`'s health overlay
/// changed and caused a body re-evaluation), which recreated a fresh
/// `AVCaptureDevice.RotationCoordinator` and KVO observation each time —
/// churn that could plausibly contribute to jank. `CameraService
/// .attachPreviewLayer(_:)` is safe to call before `start()` has
/// configured the session (it defers rotation setup until `start()`
/// completes), so a single attach-at-creation call is sufficient
/// regardless of whether the session has started yet.
struct CameraPreviewSurface: UIViewRepresentable {
    let cameraService: CameraService
    /// Called on tap with BOTH coordinate spaces, because the caller
    /// needs each for a different job: `devicePoint` (normalized
    /// sensor space, 0…1) is what `CameraService.focusAndExpose` requires,
    /// while `viewPoint` is where the reticle should be drawn on screen.
    ///
    /// The conversion deliberately happens HERE rather than in
    /// `CameraService`: `captureDevicePointConverted(fromLayerPoint:)` is
    /// the only correct way to account for `videoGravity` cropping and
    /// rotation, and only this layer knows that geometry. The actor has
    /// no business knowing about view coordinates.
    var onTapToFocus: ((_ devicePoint: CGPoint, _ viewPoint: CGPoint) -> Void)?

    /// Tracks the one preview layer this representable instance is
    /// responsible for, purely so `dismantleUIView` (a `static` function
    /// with no access to `self`) can detach it — and now also owns the
    /// tap-gesture target/action.
    final class Coordinator: NSObject {
        let cameraService: CameraService
        var onTapToFocus: ((CGPoint, CGPoint) -> Void)?

        init(cameraService: CameraService, onTapToFocus: ((CGPoint, CGPoint) -> Void)?) {
            self.cameraService = cameraService
            self.onTapToFocus = onTapToFocus
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let view = recognizer.view as? PreviewUIView else { return }
            let viewPoint = recognizer.location(in: view)
            let devicePoint = view.previewLayer.captureDevicePointConverted(fromLayerPoint: viewPoint)
            onTapToFocus?(devicePoint, viewPoint)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(cameraService: cameraService, onTapToFocus: onTapToFocus)
    }

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        // Approved aspect-fill viewfinder behavior — fills the bounds,
        // cropping rather than letterboxing. This affects only the
        // on-screen presentation, never the saved photo's framing.
        view.previewLayer.videoGravity = .resizeAspectFill

        // MEASURED FIX (Live Preview Quality Optimization Investigation,
        // Phase 2 hardware checkpoint): before this, `previewLayer
        // .contentsScale` measured 1.0 on a 3x-Retina iPhone 16 — a
        // freshly-created layer's `contentsScale` does not always get
        // auto-synced to the hosting screen's scale purely by being added
        // to a `UIViewRepresentable`'s view hierarchy (unlike a plain
        // `UIView.layer`, which UIKit's own display machinery keeps in
        // sync once genuinely part of a window). A `contentsScale` of 1.0
        // means the layer's compositor allocates a backing surface at 1/3
        // the pixel density this Retina screen needs, which the display
        // then upscales — a real, measurable, engineering-fixable source
        // of preview softness, not the Apple-private-pipeline gap. Fixed
        // by setting it explicitly to the hosting screen's actual scale.
        // This affects on-screen presentation only — never the saved
        // photo, which never touches this layer.
        view.previewLayer.contentsScale = UIScreen.main.scale

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tap)

        Task { await cameraService.attachPreviewLayer(view.previewLayer) }
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        // Attachment still happens exactly once, in makeUIView (see the
        // type's doc comment). Only the tap closure is refreshed here, so
        // it never captures a stale SwiftUI state snapshot.
        context.coordinator.onTapToFocus = onTapToFocus
    }

    static func dismantleUIView(_ uiView: PreviewUIView, coordinator: Coordinator) {
        let cameraService = coordinator.cameraService
        let layer = uiView.previewLayer
        Task { await cameraService.detachPreviewLayer(layer) }
    }
}

/// Public entry point: the live viewfinder, reflecting `CameraService`'s
/// session-health state (Phase 2.1) so a black/frozen preview during an
/// interruption or runtime error is never presented as if it were live.
///
/// Deliberately minimal per the Phase 2.2 scope: no analysis, no Vision,
/// no Motion, no CompositionParams/CoachingEngine wiring, no Photo
/// Library — just the preview surface, tap-to-focus/expose routing, and
/// its own health-driven presentation state.
public struct CameraPreviewView: View {
    let cameraService: CameraService
    /// Optional tap-to-focus hook. Receives an already-converted DEVICE
    /// point (normalized sensor space, for `CameraService.focusAndExpose`)
    /// plus the VIEW point (for positioning a reticle). Omitted by
    /// callers that don't want tap-to-focus.
    let onTapToFocus: ((_ devicePoint: CGPoint, _ viewPoint: CGPoint) -> Void)?
    @State private var health: CameraSessionHealth = .idle

    public init(
        cameraService: CameraService,
        onTapToFocus: ((_ devicePoint: CGPoint, _ viewPoint: CGPoint) -> Void)? = nil
    ) {
        self.cameraService = cameraService
        self.onTapToFocus = onTapToFocus
    }

    public var body: some View {
        ZStack {
            CameraPreviewSurface(cameraService: cameraService, onTapToFocus: onTapToFocus)
                .ignoresSafeArea()

            switch health {
            case .running:
                EmptyView()
            case .idle:
                statusOverlay("Starting camera…")
            case .interrupted(let reason):
                statusOverlay("Camera interrupted: \(reason)")
            case .recovering:
                statusOverlay("Resuming camera…")
            case .failed(let description):
                statusOverlay("Camera error: \(description)")
            }
        }
        .task {
            for await update in await cameraService.healthUpdates() {
                health = update
            }
        }
    }

    private func statusOverlay(_ message: String) -> some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.black.opacity(0.6), in: Capsule())
    }
}
