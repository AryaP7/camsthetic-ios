import CamstheticsEngine

// MARK: - Vision → CamstheticsEngine coordinate-space conversion (pure)
//
// Apple's Vision framework normalizes coordinates with the origin at the
// BOTTOM-LEFT, y increasing upward (documented on `VNObservation
// .boundingBox`/`VNPoint` throughout the framework's current
// documentation). `CamstheticsEngine.NormRect`/`NormPoint` use the
// opposite, TOP-LEFT-origin, y-down convention — this project's
// established screen/UI convention everywhere else (preview-layer
// geometry, `CameraMockupState.reticlePosition`, etc.; see
// `docs/PHASE2_FIDELITY10.md` for this project's established discipline
// around exactly this class of coordinate-space bug).
//
// Every Vision-sourced rect/point crosses this conversion exactly once,
// here — never assumed equal at a call site. Operates on plain tuples, not
// `VNObservation` itself, specifically so it's unit-testable with
// constructed fixtures on macOS without Vision/hardware — the same pattern
// `CaptureFormatSelection`/`LensSelection` already establish in this module
// for AVFoundation-adjacent pure logic.
public enum VisionCoordinateConversion {

    /// Converts a Vision-space normalized bounding box (bottom-left
    /// origin, y-up) to a `NormRect` (top-left origin, y-down).
    public static func normRect(
        fromVisionBoundingBoxX x: Double,
        y: Double,
        width: Double,
        height: Double
    ) -> NormRect {
        NormRect(x: x, y: 1.0 - y - height, width: width, height: height)
    }

    /// Converts a single Vision-space normalized point (bottom-left
    /// origin, y-up) to a `NormPoint` (top-left origin, y-down).
    public static func normPoint(fromVisionPointX x: Double, y: Double) -> NormPoint {
        NormPoint(x: x, y: 1.0 - y)
    }
}
