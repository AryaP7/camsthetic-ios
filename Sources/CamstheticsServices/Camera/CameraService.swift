import AVFoundation
import CoreMedia
import Foundation

// MARK: - Production camera-capture, preview, and lens-selection pipeline
//
// This file is production architecture, not a proof-of-concept. Its capture
// path reproduces, with actor isolation instead of manual GCD, exactly the
// capture configuration the Phase 2.0 physical-device proof already
// validated as Trial C — video output absent — and, as of the Step 2
// analysis output below, Trial A — video output attached and actively
// receiving frames
// (`App/Camsthetics/CaptureFidelityProof/CaptureFidelityProofHarness.swift`,
// `docs/PHASE2_CAPTURE_PROOF.md`, `docs/DECISIONS.md` ADR-013). That proof
// covered a throwaway harness; this production wiring needs its own
// FIDELITY-02 re-proof before being trusted (`docs/DECISIONS.md` ADR-013's
// own consequence).
//
// Scope (Phase 2.1 capture + Phase 2.2 preview + post-2.2 lens/zoom
// selection + Phase 2 Step 2 analysis output, per the approved plans):
//   - AVCaptureSession lifecycle, authorization, interruption/runtime-error
//     handling.
//   - ONE back camera input — the best available *virtual* multi-camera
//     device this physical iPhone offers (triple/dual-wide/dual), falling
//     back to a single physical wide-angle camera where that's all the
//     hardware has. Discovered at runtime via `AVCaptureDevice
//     .DiscoverySession`; never hard-codes which lenses a given iPhone
//     model has (`DECISIONS.md` ADR-011, `PRODUCT_SPEC.md` FIDELITY-08).
//   - Lens/zoom level selection (0.5×/1×/telephoto, where present) is
//     implemented as `AVCaptureDevice.videoZoomFactor` changes on that
//     SAME virtual device instance — never as an `AVCaptureDeviceInput`
//     swap, never as a digital crop layered on top of a fixed lens. This
//     is the same mechanism the native Camera app's lens pills use: the
//     virtual device internally crossfades to the appropriate physical
//     constituent as the zoom factor crosses a documented switch-over
//     threshold. See `LensSelection`/`selectLens(_:)` below.
//   - One `AVCapturePhotoOutput`. Runtime-queried maxPhotoDimensions and
//     codec, exactly as ADR-010/FIDELITY-06 require and the harness already
//     proved on-device. Lens/zoom selection never touches this output or
//     reconfigures the session — see `selectLens(_:)`'s doc comment for
//     why that's safe.
//   - One `AVCaptureVideoPreviewLayer` binding (Phase 2.2) — display only.
//   - One `AVCaptureVideoDataOutput` (analysis, Phase 2 Step 2). Native
//     YUV, throttled, single-frame-in-flight — see
//     `AnalysisFrameProcessor`. Frames are exposed via
//     `analysisFrameUpdates()` for a future consumer; Vision itself is
//     NOT wired here.
//   - No Vision, no Motion→engine wiring, no coaching UI. Those remain
//     separately-gated later phases. (`MotionService` exists as its own
//     sensor-only service — see `Sources/CamstheticsServices/Motion/` —
//     but nothing in this file consumes it.)
//
// Hard constraint this file honors, unchanged from the Phase 2.0 harness:
// the only artifact `capturePhoto()` can return is the exact bytes of
// `AVCapturePhoto.fileDataRepresentation()` — no resize, re-encode,
// tone-map, Core Image processing, bitmap reconstruction, or
// screenshot-based capture anywhere in this path (see
// `PhotoCaptureProcessor.swift`). Lens/zoom selection changes what the
// SAME photo output sees through the SAME device, exactly as it would in
// the native Camera app — it never becomes a second source of photo data.

// MARK: - Session health

/// Observable session-health state `CameraService` surfaces so a future
/// coordinator/UI can react to camera lifecycle events it otherwise has no
/// visibility into. No existing architecture document addressed
/// interruption/runtime-error handling before this file — this closes that
/// gap.
public enum CameraSessionHealth: Equatable, Sendable {
    /// Configured (or not yet configured) but not currently running —
    /// either before the first `start()` or after `stop()`.
    case idle
    /// `AVCaptureSession.isRunning` — frames are flowing.
    case running
    /// `AVCaptureSession.wasInterruptedNotification` fired. `reason` is a
    /// debug description of `AVCaptureSession.InterruptionReason` (e.g.
    /// another app took the camera, a multitasking restriction, system
    /// pressure) rather than the enum itself, to keep this type trivially
    /// `Sendable` without extra ceremony this phase doesn't need.
    case interrupted(reason: String)
    /// Between `AVCaptureSession.interruptionEndedNotification` firing and
    /// the session confirming it's running again. Distinct from
    /// `.interrupted` so the UI can show a "recovering" state rather than
    /// either a stale interrupted banner or an instant, potentially
    /// misleading jump straight to `.running`.
    case recovering
    /// `AVCaptureSession.runtimeErrorNotification` fired.
    case failed(description: String)
}

// MARK: - Errors

public enum CameraServiceError: LocalizedError, Sendable {
    case cameraAccessDenied
    case noCameraDevice
    case cannotAddInput
    case cannotAddPhotoOutput
    case cannotAddAnalysisOutput
    case noSupportedPhotoDimensions
    case noSupportedAnalysisPixelFormat
    case sessionNotRunning
    case captureFailed(String)
    case fileDataRepresentationUnavailable
    case lensSelectionFailed(String)
    case focusExposureFailed(String)

    public var errorDescription: String? {
        switch self {
        case .cameraAccessDenied:
            return "Camera access was denied."
        case .noCameraDevice:
            return "No usable back camera is available on this device."
        case .cannotAddInput:
            return "AVCaptureSession refused the camera input."
        case .cannotAddPhotoOutput:
            return "AVCaptureSession refused the AVCapturePhotoOutput."
        case .cannotAddAnalysisOutput:
            return "AVCaptureSession refused the AVCaptureVideoDataOutput (analysis)."
        case .noSupportedPhotoDimensions:
            return "activeFormat.supportedMaxPhotoDimensions was empty."
        case .noSupportedAnalysisPixelFormat:
            return "AVCaptureVideoDataOutput offered neither 420f nor 420v pixel format."
        case .sessionNotRunning:
            return "The capture session is not running — call start() first."
        case .captureFailed(let description):
            return "Photo capture failed: \(description)"
        case .fileDataRepresentationUnavailable:
            return "AVCapturePhoto.fileDataRepresentation() returned nil — no artifact produced."
        case .lensSelectionFailed(let description):
            return "Lens selection failed: \(description)"
        case .focusExposureFailed(let description):
            return "Focus/exposure adjustment failed: \(description)"
        }
    }
}

// MARK: - Captured artifact

/// The result of one `CameraService.capturePhoto()` call.
public struct CapturedPhotoArtifact: Sendable {
    /// Exact, unmodified bytes of `AVCapturePhoto.fileDataRepresentation()`.
    /// This is the only thing a caller may treat as "the photo."
    public let data: Data
}

// MARK: - Capture-format selection (pure, hardware-independent policy)

/// Pure capture-format selection policy, operating only on already-queried
/// value types (`CMVideoDimensions`, `AVVideoCodecType`) rather than on
/// `AVCaptureDevice`/`AVCaptureDevice.Format` directly, specifically so it
/// is unit-testable with constructed fixtures — `AVCaptureDevice.Format`
/// has no public initializer and cannot be synthesized without real
/// hardware.
///
/// Runtime-queried, never hard-coded (`DECISIONS.md` ADR-010,
/// `PRODUCT_SPEC.md` FIDELITY-06) — this is the exact selection policy the
/// Phase 2.0 proof harness validated on physical iPhone 16 hardware
/// (`CaptureFidelityProofHarness.swift`), reproduced here for production
/// use.
public enum CaptureFormatSelection {

    /// The largest entry among a format's `supportedMaxPhotoDimensions`, by
    /// pixel area. `nil` if the list is empty.
    public static func largestDimensions(among dimensions: [CMVideoDimensions]) -> CMVideoDimensions? {
        dimensions.max { lhs, rhs in
            Int64(lhs.width) * Int64(lhs.height) < Int64(rhs.width) * Int64(rhs.height)
        }
    }

    /// HEVC preferred where available; `nil` (letting
    /// `AVCapturePhotoOutput` resolve its own device-appropriate default,
    /// documented as a fallback rather than assumed) when it isn't offered.
    /// Never hard-codes JPEG.
    public static func preferredCodec(among codecs: [AVVideoCodecType]) -> AVVideoCodecType? {
        codecs.contains(.hevc) ? .hevc : nil
    }
}

/// Pure selection of the analysis output's pixel format from an
/// already-queried `availableVideoPixelFormatTypes` list — never
/// `videoSettings = nil` (which defaults to BGRA), and never hard-coded,
/// since `docs/TECH_STACK.md` explicitly rejects a shared full-res BGRA
/// analysis output in favour of native YUV.
public enum AnalysisPixelFormatSelection {

    /// 420f (full-range) preferred — it needs no video-range→full-range
    /// expansion for a Vision consumer that wants full luma precision;
    /// 420v (video-range) as the documented fallback where 420f isn't
    /// offered. `nil` only if a device offers neither, which would be a
    /// genuine capability gap to surface rather than silently default to
    /// BGRA.
    public static func preferredPixelFormat(among formats: [OSType]) -> OSType? {
        if formats.contains(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) {
            return kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        }
        if formats.contains(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) {
            return kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        }
        return nil
    }
}

// MARK: - Lens/zoom selection (pure, hardware-independent policy)

/// One selectable optical lens/zoom level — derived at runtime from a
/// specific physical iPhone's actual camera hardware, never asserted.
public struct LensOption: Identifiable, Equatable, Sendable {
    /// Stable per-session identity (not persisted across devices/runs).
    public let id: String
    /// Display label derived from the actual `AVCaptureDevice
    /// .videoZoomFactor` this option selects (e.g. "0.5×", "1×", "3×") —
    /// not Apple's cosmetically-adjusted marketing multiplier
    /// (`displayVideoZoomFactorMultiplier` is iOS 18+ only; this
    /// project's deployment target is iOS 17, so the raw zoom factor is
    /// shown honestly rather than guessed at).
    public let label: String
    /// The `videoZoomFactor` value that selects this lens level.
    public let zoomFactor: CGFloat
    /// Which physical constituent this level corresponds to, for
    /// diagnostics/testing (e.g. the temporary validation scaffold).
    public let deviceType: AVCaptureDevice.DeviceType

    public init(id: String, label: String, zoomFactor: CGFloat, deviceType: AVCaptureDevice.DeviceType) {
        self.id = id
        self.label = label
        self.zoomFactor = zoomFactor
        self.deviceType = deviceType
    }
}

/// Pure derivation of selectable lens/zoom levels from already-queried
/// device values (constituent device types, in order; the zoom factor at
/// which each constituent becomes active). Operates only on plain value
/// types — never on `AVCaptureDevice` itself — specifically so it is
/// unit-testable with constructed fixtures, matching
/// `CaptureFormatSelection`'s established pattern in this file.
///
/// One selectable level per physical lens the device actually has — never
/// a fabricated intermediate "2×" digital-crop pseudo-level on a device
/// that has no second lens there. This directly answers the product
/// requirement for *optical* lens levels, not digital zoom dressed up as
/// a lens choice.
public enum LensSelection {

    /// - Parameters:
    ///   - constituentDeviceTypes: `AVCaptureDevice.constituentDevices`'s
    ///     device types, in order. Empty for a non-virtual (single-lens)
    ///     device.
    ///   - minAvailableVideoZoomFactor: the device's
    ///     `minAvailableVideoZoomFactor` (this is the entry zoom factor
    ///     for the first/widest constituent — below 1.0 on devices whose
    ///     first constituent is an ultra-wide lens; exactly 1.0 on devices
    ///     without one).
    ///   - switchOverVideoZoomFactors: the device's
    ///     `virtualDeviceSwitchOverVideoZoomFactors` — one fewer entry
    ///     than `constituentDeviceTypes`, marking the zoom factor at which
    ///     each subsequent constituent becomes active.
    public static func options(
        constituentDeviceTypes: [AVCaptureDevice.DeviceType],
        minAvailableVideoZoomFactor: CGFloat,
        switchOverVideoZoomFactors: [CGFloat]
    ) -> [LensOption] {
        guard !constituentDeviceTypes.isEmpty else {
            // Non-virtual device: exactly one selectable level.
            return [
                LensOption(id: "single", label: label(for: 1.0), zoomFactor: 1.0, deviceType: .builtInWideAngleCamera)
            ]
        }

        var entryFactors: [CGFloat] = [minAvailableVideoZoomFactor]
        entryFactors.append(contentsOf: switchOverVideoZoomFactors)

        // Physical-device validation (Phase 2 hardware checkpoint) found
        // that on real hardware `minAvailableVideoZoomFactor` is not
        // guaranteed to equal the ultra-wide constituent's canonical 0.5 —
        // it can instead report 1.0, shifting every subsequent constituent's
        // entry factor up by the same amount (observed: ultra-wide entry
        // 1.0, wide entry 2.0, instead of the conventional 0.5/1.0). The
        // RAW factors are still exactly what must be passed to
        // `videoZoomFactor`/`ramp(toVideoZoomFactor:withRate:)` — that part
        // was always correct. What was wrong is using that raw, absolute
        // factor as the DISPLAY label: Apple's own convention (native
        // Camera's lens pills, and `videoZoomFactor`'s documented "1.0 =
        // full field of view") defines "1×" as the WIDE lens specifically,
        // not "whatever the first constituent's raw entry factor is". So
        // the label is derived relative to the Wide constituent's own
        // entry factor when one is present, leaving `zoomFactor` (what
        // actually drives the hardware) untouched either way. This is a
        // label correction, not a fabricated digital-zoom level — the
        // constituent this option selects, and the physical lens that
        // becomes active, are unchanged.
        let wideEntryFactor: CGFloat? = {
            guard let wideIndex = constituentDeviceTypes.firstIndex(of: .builtInWideAngleCamera),
                  wideIndex < entryFactors.count else { return nil }
            let factor = entryFactors[wideIndex]
            return (factor.isFinite && factor > 0) ? factor : nil
        }()

        // Defensive: entryFactors should have exactly one entry per
        // constituent by construction (Apple's documented invariant), but
        // never index out of bounds if a future OS ever violates it. Also
        // reject non-finite factors (NaN/±infinity) outright — a
        // malformed value here would otherwise become an unusable or
        // crashing lens option.
        let count = min(entryFactors.count, constituentDeviceTypes.count)
        let candidates: [LensOption] = (0..<count).compactMap { index in
            let factor = entryFactors[index]
            guard factor.isFinite, factor > 0 else { return nil }
            let type = constituentDeviceTypes[index]
            return LensOption(
                id: "\(type.rawValue)-\(index)",
                label: label(for: displayFactor(rawZoomFactor: factor, wideEntryFactor: wideEntryFactor)),
                zoomFactor: factor,
                deviceType: type
            )
        }

        // Collapse duplicate/near-duplicate levels (e.g. a device
        // reporting a switch-over factor equal to, or indistinguishable
        // from, the previous entry) — keep the first occurrence, since
        // entries are already in ascending constituent order. Two
        // options the user couldn't visually or functionally tell apart
        // would just be confusing UI, not a second real lens.
        var deduped: [LensOption] = []
        for candidate in candidates {
            if let last = deduped.last, abs(last.zoomFactor - candidate.zoomFactor) < 0.01 {
                continue
            }
            deduped.append(candidate)
        }
        return deduped
    }

    /// Honest, direct formatting of a (typically already wide-relative —
    /// see `options(...)`'s doc comment) zoom factor value — e.g.
    /// `0.5` → `"0.5×"`, `2.0` → `"2×"`.
    public static func label(for zoomFactor: CGFloat) -> String {
        if zoomFactor == zoomFactor.rounded() {
            return "\(Int(zoomFactor))×"
        }
        return String(format: "%.1f×", zoomFactor)
    }

    /// Converts a RAW `videoZoomFactor` value (what actually drives the
    /// hardware) into the Wide-lens-relative value that should be
    /// *displayed* (what `options(...)` labels its `LensOption`s with) —
    /// shared by both the discrete lens buttons and any continuous
    /// zoom-gesture UI, so a mid-pinch readout and a snapped-to lens
    /// button always agree on what to call the same raw factor.
    /// `nil`/non-finite/non-positive `wideEntryFactor` (no Wide constituent
    /// known) falls back to the raw factor unchanged, matching
    /// `options(...)`'s own fallback.
    public static func displayFactor(rawZoomFactor: CGFloat, wideEntryFactor: CGFloat?) -> CGFloat {
        guard let wideEntryFactor, wideEntryFactor.isFinite, wideEntryFactor > 0 else {
            return rawZoomFactor
        }
        return rawZoomFactor / wideEntryFactor
    }

    /// Given a RAW target zoom factor (e.g. a live pinch gesture's current
    /// value) and a device/format's discovered
    /// `secondaryNativeResolutionZoomFactors` (see
    /// `CameraService.secondaryNativeResolutionZoomFactors`), returns the
    /// nearest one if the target is within `tolerance` of it, else returns
    /// `target` unchanged.
    ///
    /// This is the device-agnostic "intelligent zoom snap": it never
    /// hard-codes which factor to snap to (e.g. "2.0" or "4.0") — it
    /// reads whatever THIS device/format reports at runtime and snaps to
    /// whichever of those points is close to where the gesture already
    /// is. A device/format reporting no secondary-native points (empty
    /// array — most devices, most formats) makes this a pure no-op, which
    /// is the correct behavior there, not a missing feature.
    ///
    /// `secondaryNativeResolutionZoomFactors` marks the zoom factor at
    /// which a device switches to a genuinely different, non-upscaled
    /// pixel-sampling mode (Apple's public API for e.g. an in-sensor
    /// "Fusion"-style crop) — landing exactly on it during a continuous
    /// pinch gesture is measurably better than stopping 0.05 short of it,
    /// so snapping there when the gesture is already close is a
    /// legitimate, evidence-backed UX improvement, not a guess.
    /// Clamps a requested exposure-bias value (EV) into the range that is
    /// BOTH supported by the device and permitted by the product spec.
    ///
    /// Two independent limits, deliberately applied in this order:
    ///  1. the device's own reported `minExposureTargetBias ...
    ///     maxExposureTargetBias` (±8 EV on the current test unit, but
    ///     runtime-queried — never assumed),
    ///  2. `PRODUCT_SPEC.md` §1.5's tighter ±2.0 EV product limit, which
    ///     exists so a drag gesture can't push exposure somewhere a user
    ///     can't easily recover from.
    ///
    /// Pure and hardware-free so it unit-tests on macOS with constructed
    /// fixtures, matching `LensSelection`/`CaptureFormatSelection`'s
    /// established pattern. Non-finite input returns 0 (neutral), never
    /// NaN — a NaN reaching `setExposureTargetBias` would throw.
    public static func clampedExposureBias(
        _ requested: Float,
        deviceMin: Float,
        deviceMax: Float,
        productLimit: Float = 2.0
    ) -> Float {
        guard requested.isFinite else { return 0 }
        let lowerBound = max(deviceMin, -abs(productLimit))
        let upperBound = min(deviceMax, abs(productLimit))
        guard lowerBound <= upperBound else { return 0 }
        return min(max(requested, lowerBound), upperBound)
    }

    public static func snapToNativeResolution(
        target: CGFloat,
        secondaryNativeResolutionZoomFactors: [CGFloat],
        tolerance: CGFloat = 0.15
    ) -> CGFloat {
        guard target.isFinite, tolerance.isFinite, tolerance >= 0 else { return target }
        guard let nearest = secondaryNativeResolutionZoomFactors
            .filter({ $0.isFinite })
            .min(by: { abs($0 - target) < abs($1 - target) })
        else { return target }
        return abs(nearest - target) <= tolerance ? nearest : target
    }

    /// The `rate` to pass to `AVCaptureDevice.ramp(toVideoZoomFactor:withRate:)`
    /// so a transition from `current` to `target` takes approximately
    /// `duration` seconds, regardless of how large the jump is.
    ///
    /// Apple's current documentation states `rate` is "specified in powers
    /// of two per second," with the zoom factor changing at an
    /// *exponential* rate during the ramp — a fixed `rate` therefore
    /// produces wildly different durations for different jumps (e.g.
    /// 0.5×→1× is a 1-stop change; 0.5×→5× is over a 2-stop change). This
    /// is a pure function over already-queried values (never touches
    /// `AVCaptureDevice` itself), so it's unit-testable with synthetic
    /// fixtures, matching `CaptureFormatSelection`/`LensSelection.options`'s
    /// established pattern in this file.
    ///
    /// Returns a rate floored at `0.1` (never zero/negative — `ramp`'s
    /// `rate` parameter has no meaningful zero-duration behavior),
    /// ceilinged at `Self.maxRampRate` (an extreme jump — e.g. a
    /// malformed multi-stop factor — should still ramp smoothly rather
    /// than degenerate into the same near-instant snap the old
    /// hard-coded `rate: 8.0` produced), and `1.0` when `current`/
    /// `target`/`duration` aren't finite and strictly positive, or
    /// `current == target` (a degenerate/no-op case where the exact rate
    /// value doesn't matter).
    public static func rampRate(from current: CGFloat, to target: CGFloat, duration: Float) -> Float {
        guard
            current.isFinite, current > 0,
            target.isFinite, target > 0,
            current != target,
            duration.isFinite, duration > 0
        else {
            return 1.0
        }
        let stops = abs(Float(log2(Double(target / current))))
        guard stops.isFinite else { return 1.0 }
        return min(max(stops / duration, minRampRate), maxRampRate)
    }

    /// Never slower than this — an extremely long requested `duration`
    /// would otherwise compute a near-zero rate and produce a
    /// practically-never-finishing ramp.
    private static let minRampRate: Float = 0.1
    /// Never faster than this — bounds how "snappy" even a pathological
    /// multi-stop jump can look, so it stays a visible ramp rather than
    /// degenerating into the instant-jump feel this whole function exists
    /// to avoid.
    private static let maxRampRate: Float = 6.0
}

// MARK: - CameraService

/// Owns the app's single `AVCaptureSession`. Actor isolation is the
/// session-configuration serialization guarantee — no separate
/// `DispatchQueue` is needed (`docs/ARCHITECTURE.md` §5: "actor
/// CameraService — AVCaptureSession management, Photo output").
public actor CameraService {

    // MARK: State this actor owns

    private let session = AVCaptureSession()
    private var device: AVCaptureDevice?
    private let photoOutput = AVCapturePhotoOutput()
    private var isConfigured = false

    /// Analysis path (Phase 2 Step 2). Native YUV, 10Hz-throttled, single
    /// frame in flight — see `AnalysisFrameProcessor`. `nil` only if
    /// `configureCaptureSession()` never ran (matches `device`'s pattern).
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private var analysisFrameProcessor: AnalysisFrameProcessor?
    private var analysisContinuations: [UUID: AsyncStream<AnalysisFrame>.Continuation] = [:]
    /// 10Hz — `docs/IMPLEMENTATION_PLAN.md` §Phase 2's analysis throttle
    /// rate. A stored constant (not a magic number at the call site) so a
    /// future FIDELITY-02 re-proof or jitter measurement can reference the
    /// exact value this session was configured with.
    public static let analysisThrottleHz: Double = 10.0

    /// Keeps each in-flight capture's delegate alive for the duration of
    /// its request — `capturePhoto(with:delegate:)` does not retain its
    /// delegate.
    private var activeCaptureProcessors: [Int64: PhotoCaptureProcessor] = [:]

    private var healthContinuations: [UUID: AsyncStream<CameraSessionHealth>.Continuation] = [:]
    private var currentHealth: CameraSessionHealth = .idle

    /// Owns the rotation coordinator/observation for whichever preview
    /// layer is currently attached (Phase 2.2). One at a time — this phase
    /// does not support multiple simultaneous preview surfaces.
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?
    /// A preview layer that called `attachPreviewLayer(_:)` before `start()`
    /// had configured `device` — its rotation setup is finished once
    /// `start()` completes. `weak` because ownership belongs to the
    /// SwiftUI view hierarchy, not this actor.
    private weak var pendingPreviewLayer: AVCaptureVideoPreviewLayer?

    private var lensOptionsContinuations: [UUID: AsyncStream<[LensOption]>.Continuation] = [:]
    /// KVO observation of `device.minAvailableVideoZoomFactor` — Apple's
    /// current documentation states this property "is key-value
    /// observable," which is why lens options are exposed reactively
    /// (`lensOptionsUpdates()`) rather than only via a single point-in-time
    /// `availableLensOptions()` read: the usable zoom range can change
    /// after `start()` returns (e.g. once the session settles), and a
    /// one-shot read taken immediately after `startRunning()` is not
    /// guaranteed to reflect the final range.
    private var minZoomObservation: NSKeyValueObservation?

    public init() {}

    // MARK: Session health

    /// A stream of session-health transitions a future coordinator/UI can
    /// observe. Immediately yields the current health on subscription.
    public func healthUpdates() -> AsyncStream<CameraSessionHealth> {
        let id = UUID()
        // `.bufferingNewest(1)`: a subscriber only ever cares about the
        // current health, never a backlog of stale transitions — this
        // also bounds memory if a subscriber is slow/never reads, rather
        // than the default unbounded buffer.
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            healthContinuations[id] = continuation
            continuation.yield(currentHealth)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeHealthContinuation(id: id) }
            }
        }
    }

    private func removeHealthContinuation(id: UUID) {
        healthContinuations.removeValue(forKey: id)
    }

    // MARK: Analysis frames (Phase 2 Step 2)

    /// A stream of throttled analysis frames for a future Vision consumer
    /// (Phase 3). Yields nothing until the session is configured and
    /// running — there is no "current frame" to replay on subscription
    /// the way `healthUpdates()`/`lensOptionsUpdates()` replay their
    /// latest value, since holding onto a stale `CVPixelBuffer` across
    /// subscriptions would fight the single-frame-in-flight gate for no
    /// benefit.
    public func analysisFrameUpdates() -> AsyncStream<AnalysisFrame> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            analysisContinuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeAnalysisContinuation(id: id) }
            }
        }
    }

    private func removeAnalysisContinuation(id: UUID) {
        analysisContinuations.removeValue(forKey: id)
    }

    private func publishAnalysisFrame(_ frame: AnalysisFrame) {
        for continuation in analysisContinuations.values {
            continuation.yield(frame)
        }
    }

    private func updateHealth(_ health: CameraSessionHealth) {
        currentHealth = health
        for continuation in healthContinuations.values {
            continuation.yield(health)
        }
    }

    // MARK: Authorization

    /// Current camera authorization status. Does not prompt.
    public var authorizationStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    /// Requests camera access if not yet determined; returns whether the
    /// app is authorized afterward. A caller must check this (or `start()`'s
    /// thrown error) before relying on live frames — until access is
    /// granted, AVFoundation only vends black frames (verified against
    /// Apple's current documentation for
    /// `AVCaptureDevice.requestAccess(for:completionHandler:)`).
    public func requestAuthorizationIfNeeded() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    continuation.resume(returning: granted)
                }
            }
        default:
            return false
        }
    }

    // MARK: Session lifecycle (the only paths that touch startRunning/stopRunning)

    /// Requests authorization if needed, configures the capture-only
    /// pipeline on first call, subscribes to interruption/runtime-error
    /// notifications, and starts the session running.
    public func start() async throws {
        guard await requestAuthorizationIfNeeded() else {
            throw CameraServiceError.cameraAccessDenied
        }

        if !isConfigured {
            try configureCaptureSession()
            subscribeToSessionNotifications()
            isConfigured = true
            print(debugCameraTopologyDescription())
            subscribeToZoomRangeChanges()

            // A preview layer may have already called `attachPreviewLayer`
            // before `device` existed (SwiftUI's preview view and this
            // start() call race in the general case) — finish its rotation
            // setup now that the device is known, without requiring the
            // caller to attach again. See `attachPreviewLayer(_:)`.
            if let device, let pendingPreviewLayer {
                configureRotation(for: pendingPreviewLayer, device: device)
                self.pendingPreviewLayer = nil
            }
        }

        if !session.isRunning {
            session.startRunning()
            updateHealth(.running)
        }
    }

    /// Stops the session. Safe to call even if not running.
    public func stop() {
        if session.isRunning {
            session.stopRunning()
        }
        updateHealth(.idle)
    }

    // MARK: Device discovery

    /// Priority order to search for the back camera in, best first. Never
    /// hard-codes which of these a given iPhone actually has — this is
    /// just the search order; `discoverBackCamera()` takes whichever one
    /// the device reports (`DECISIONS.md` ADR-011, `PRODUCT_SPEC.md`
    /// FIDELITY-08).
    ///
    /// The virtual multi-camera types (triple/dual-wide/dual) are listed
    /// first: selecting one of these — rather than a single physical
    /// `.builtInWideAngleCamera`, which is all the previous Phase 2.1
    /// implementation ever requested — is *why* 0.5×/telephoto lens
    /// selection becomes possible at all. `.builtInWideAngleCamera` alone
    /// only ever exposes the single 1× physical lens, regardless of how
    /// many lenses the iPhone actually has, because that constant asks
    /// AVFoundation for that one specific physical device and nothing
    /// else.
    private static let backCameraDeviceTypePriority: [AVCaptureDevice.DeviceType] = {
        // The virtual multi-camera types (triple/dual-wide/dual) are
        // iOS/iPadOS/Mac-Catalyst/tvOS only — explicitly unavailable on
        // plain macOS (verified via the SDK's own availability
        // annotations), since Macs have no such multi-lens camera
        // ecosystem. Guarded so this target still builds and tests on
        // macOS (ARCHITECTURE.md §6.1's macOS-speed test tier); production
        // behavior (iOS) gets the full priority list.
        #if os(iOS)
        return [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera]
        #else
        return [.builtInWideAngleCamera]
        #endif
    }()

    /// Discovers the best available back camera on THIS physical device at
    /// runtime. Per Apple's current documentation, `DiscoverySession`
    /// "automatically sorts its devices list based on the device types you
    /// asked for," so the first result (if any) is the best match for
    /// `backCameraDeviceTypePriority`'s order.
    private func discoverBackCamera() -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: Self.backCameraDeviceTypePriority,
            mediaType: .video,
            position: .back
        )
        return discovery.devices.first
    }

    /// Read-only diagnostic snapshot of the actual configured camera
    /// topology on THIS physical device — deviceType, constituents, zoom
    /// range, switch-over factors, active format — printed once after
    /// configuration (`start()`) so real hardware behavior can be
    /// inspected on the console rather than assumed. Never used to drive
    /// any behavior; this is inspection only, same spirit as
    /// `ImageArtifactIntrospection` in the Phase 2.0 harness.
    private func debugCameraTopologyDescription() -> String {
        guard let device else { return "[CameraTopology] No device configured." }

        var lines = ["[CameraTopology]"]
        lines.append("deviceType: \(device.deviceType.rawValue)")
        lines.append("localizedName: \(device.localizedName)")
        lines.append("position: \(device.position.rawValue)")

        // isVirtualDevice, constituentDevices, min/maxAvailableVideoZoomFactor,
        // virtualDeviceSwitchOverVideoZoomFactors, videoZoomFactor, and
        // Format.videoMaxZoomFactor are all iOS/iPadOS/Mac-Catalyst/tvOS
        // only — explicitly unavailable on plain macOS. Guarded so this
        // target still builds and tests on macOS; this whole method's
        // output is only meaningful on iOS regardless.
        #if os(iOS)
        lines.append("isVirtualDevice: \(device.isVirtualDevice)")
        let constituents = device.constituentDevices
        lines.append("constituentDevices.count: \(constituents.count)")
        for (index, constituent) in constituents.enumerated() {
            lines.append("  [\(index)] \(constituent.deviceType.rawValue) — \(constituent.localizedName)")
        }
        lines.append("minAvailableVideoZoomFactor: \(device.minAvailableVideoZoomFactor)")
        lines.append("maxAvailableVideoZoomFactor: \(device.maxAvailableVideoZoomFactor)")
        lines.append("virtualDeviceSwitchOverVideoZoomFactors: \(device.virtualDeviceSwitchOverVideoZoomFactors)")
        lines.append("videoZoomFactor (current): \(device.videoZoomFactor)")
        lines.append("activeFormat.videoMaxZoomFactor: \(device.activeFormat.videoMaxZoomFactor)")
        #endif

        for range in device.activeFormat.videoSupportedFrameRateRanges {
            lines.append("activeFormat.frameRateRange: \(range.minFrameRate)-\(range.maxFrameRate) fps")
        }
        lines.append("activeFormat.formatDescription: \(device.activeFormat.formatDescription)")

        // HDR/exposure/focus/white-balance state — read-only, never sets
        // anything. Kept as permanent diagnostic visibility (cheap: pure
        // property reads, no session reconfiguration) after the Phase 2
        // preview-quality investigation used it to confirm these were
        // already all correctly on (HDR supported+enabled+auto-adjusted,
        // continuous AE/AF/AWB) before ruling out a missing-toggle
        // explanation for preview softness.
        #if os(iOS)
        lines.append("activeFormat.isVideoHDRSupported: \(device.activeFormat.isVideoHDRSupported)")
        lines.append("automaticallyAdjustsVideoHDREnabled: \(device.automaticallyAdjustsVideoHDREnabled)")
        lines.append("isVideoHDREnabled: \(device.isVideoHDREnabled)")
        lines.append("activeColorSpace: \(device.activeColorSpace.rawValue)")
        lines.append("exposureMode: \(device.exposureMode.rawValue), focusMode: \(device.focusMode.rawValue), whiteBalanceMode: \(device.whiteBalanceMode.rawValue)")
        #endif

        return lines.joined(separator: "\n")
    }

    // MARK: Session configuration (capture pipeline)

    /// Configures the capture pipeline: the best available back camera
    /// (virtual multi-camera where present — see `discoverBackCamera()`),
    /// one `AVCapturePhotoOutput`, and (Phase 2 Step 2) one
    /// `AVCaptureVideoDataOutput` analysis path. Renamed from
    /// `configureCaptureOnlySession()` now that it's no longer capture-only.
    private func configureCaptureSession() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        if session.canSetSessionPreset(.photo) {
            session.sessionPreset = .photo
        }

        guard let camera = discoverBackCamera() else {
            throw CameraServiceError.noCameraDevice
        }
        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input) else {
            throw CameraServiceError.cannotAddInput
        }
        session.addInput(input)
        device = camera

        // Live Preview Quality Optimization Investigation (Phase 2
        // hardware checkpoint) — a MEASURED fix, not a guess. Without
        // this, AVFoundation's default frame-duration negotiation for
        // this device/format landed at ~15fps even though
        // `activeFormat.videoSupportedFrameRateRanges` advertises up to
        // 30fps (confirmed via a diagnostic `AVCaptureVideoDataOutput`
        // probe on this exact session: avgFPS=15.00, jitterMs=13.2,
        // dropped=0 — a stable cap, not overload/backpressure). This
        // requests only the MINIMUM frame duration (maximum fps) —
        // `activeVideoMaxFrameDuration` is deliberately left at its
        // default so low-light auto-exposure can still lengthen exposure
        // toward the format's advertised minimum frame rate when the
        // scene needs it; this only raises the ceiling, never forces a
        // fixed rate. Every connection reading this session's frames —
        // including the preview layer's — draws from the same underlying
        // cadence. Frame rate has no bearing on a single photo's pixels
        // (structurally independent per ADR-009/the Phase 2.0 proof), so
        // this cannot affect `capturePhoto()`'s output.
        if let fastestRange = camera.activeFormat.videoSupportedFrameRateRanges.max(by: { $0.maxFrameRate < $1.maxFrameRate }) {
            do {
                try camera.lockForConfiguration()
                camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: Int32(fastestRange.maxFrameRate))
                camera.unlockForConfiguration()
            } catch {
                // Non-fatal — leave AVFoundation's default frame-duration
                // negotiation in place rather than failing session setup
                // over a preview-smoothness optimization.
            }
        }

        guard session.canAddOutput(photoOutput) else {
            throw CameraServiceError.cannotAddPhotoOutput
        }
        session.addOutput(photoOutput)

        photoOutput.maxPhotoQualityPrioritization = .quality

        // Runtime-queried, never hard-coded (ADR-010, FIDELITY-06) — the
        // same policy the Phase 2.0 proof already validated on-device.
        guard let maxDimensions = CaptureFormatSelection.largestDimensions(
            among: camera.activeFormat.supportedMaxPhotoDimensions
        ) else {
            throw CameraServiceError.noSupportedPhotoDimensions
        }
        photoOutput.maxPhotoDimensions = maxDimensions

        // MARK: Track K — capture-responsiveness options investigated
        //
        // Both of these must be set here (before startRunning()) since
        // Apple's current documentation states they "require a lengthy
        // reconfiguration of the capture pipeline."
        //
        // Responsive Capture: reduces the delay before the output is
        // ready to accept the *next* capture request after one is already
        // in flight — a capture-cadence property, not a per-photo pixel
        // property (unlike maxPhotoDimensions/codec, it has no documented
        // effect on a single photo's dimensions, codec, color, or
        // metadata). Enabled only where the device reports it supported
        // (`DECISIONS.md` ADR-010: runtime-queried, never assumed).
        // Needs physical re-verification against the Phase 2.0/2.1
        // ImageIO baseline before being trusted as fidelity-neutral in
        // practice, not just by documentation. (No `#if os(iOS)` guard
        // needed here — unlike the zoom/virtual-device APIs elsewhere in
        // this file, `isResponsiveCaptureSupported`/`isResponsiveCaptureEnabled`
        // are documented available on macOS 14+ too, confirmed by this
        // target still building on macOS with this code unguarded.)
        if photoOutput.isResponsiveCaptureSupported {
            photoOutput.isResponsiveCaptureEnabled = true
        }
        //
        // Zero Shutter Lag: NOT explicitly set here. Verified via the
        // Phase 2.0 proof's own recorded sidecar data
        // (`docs/PHASE2_CAPTURE_PROOF.md` §4) that `isZeroShutterLagEnabled`
        // was already `true` on this hardware/iOS combination *without*
        // this code ever setting it — i.e. it is already the system
        // default where supported, not something this file was
        // withholding. Nothing to change.
        //
        // Fast Capture Prioritization: NOT enabled. Its name and design
        // intent (per Apple's "Managing responsive capture" API group)
        // trade capture speed against image quality — the opposite of
        // this product's stated priority (Track K: "maximum practical
        // image quality"). Also `isFastCapturePrioritizationSupported`
        // was `false` on the Phase 2.0 proof's actual test device, so
        // enabling it would be a no-op there regardless.
        //
        // Constant Color (iOS 18+): NOT enabled. Its documented purpose is
        // color consistency across *simultaneous* virtual-device
        // constituent delivery / bracketed capture — a capture pattern
        // this app doesn't use (one photo, one currently-active
        // constituent, per capture). No demonstrated benefit for our
        // actual capture pattern.
        //
        // Auto Deferred Photo Delivery: deliberately NOT enabled, and
        // will not be without a product-level decision to change the
        // fidelity architecture. Apple's current documentation for
        // `photoOutput(_:didFinishCapturingDeferredPhotoProxy:error:)`
        // states the initial result is only "a proxy... approximates the
        // look of the final image," that the *real* high-quality asset is
        // produced later by the **system Photos database itself** (not
        // this app's process) once the proxy is handed to `PhotoKit`, and
        // explicitly: "The intermediate data aren't accessible by the
        // calling process." That is structurally incompatible with this
        // app's fidelity guarantee (`PhotoCaptureProcessor` returning the
        // exact, complete `fileDataRepresentation()` bytes directly to
        // the app) and with the planned Phase 6 in-app drag-to-compare
        // review (`PRODUCT_SPEC.md` §1.6), which needs the real pixels
        // in-process, not deferred into a system database this app
        // doesn't directly read from. Recorded here so this isn't
        // mistakenly "rediscovered" and enabled later without re-deriving
        // this conflict.
        //
        // Post-capture image processing (denoise/sharpen/tone-map/color
        // correction): deliberately NOT introduced anywhere in this file.
        // `PRODUCT_SPEC.md` §1.5 already states captures preserve "Apple
        // Smart HDR / Deep Fusion pipeline" output — i.e. Apple's own
        // multi-frame computational photography has already run by the
        // time `fileDataRepresentation()` returns these bytes. Any
        // additional app-side processing here would necessarily decode
        // and re-encode an already-processed HEIC/HEVC image — exactly
        // the lossy, detail-destroying re-encode ADR-009/FIDELITY-01's
        // pipeline separation and this file's own header exist to
        // prevent, for no demonstrated quality gain over what the OS
        // already produced.

        // MARK: Analysis output (Phase 2 Step 2)
        //
        // Added to the SAME session, but on its own dedicated serial
        // queue/output, so it can never interfere with `photoOutput`'s
        // configuration or delivery (ADR-009's pipeline-independence
        // claim). Re-proven for this production wiring via an on-device
        // FIDELITY-02 A/B capture comparison (analysis output live vs.
        // entirely absent) on physical iPhone 16, 2026-09-05: both
        // captures were characteristic-identical — 4032×3024, HEVC
        // (`hvc1`), Display P3, HDR gain-map auxiliary present in both;
        // only file size differed, the same natural per-exposure variance
        // ADR-013/`PHASE2_CAPTURE_PROOF.md` already established isn't a
        // fidelity difference. Not argued architecturally alone, per
        // ADR-012/ADR-013's precedent.
        guard let analysisPixelFormat = AnalysisPixelFormatSelection.preferredPixelFormat(
            among: videoDataOutput.availableVideoPixelFormatTypes
        ) else {
            throw CameraServiceError.noSupportedAnalysisPixelFormat
        }
        // Native YUV bi-planar, never BGRA (`docs/TECH_STACK.md`) —
        // `videoSettings = nil` would default to BGRA, so this is always
        // set explicitly rather than left at its default.
        videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: analysisPixelFormat]
        // Never buffer stale frames waiting behind a slow consumer — the
        // 10Hz throttle plus the single-frame-in-flight gate in
        // `AnalysisFrameProcessor` are the deliberate backpressure design;
        // this flag is what makes AVFoundation's own delivery honor that
        // instead of queueing (`docs/ARCHITECTURE.md`).
        videoDataOutput.alwaysDiscardsLateVideoFrames = true

        let analysisQueue = DispatchQueue(label: "com.camsthetics.analysisOutput")
        let processor = AnalysisFrameProcessor(
            queue: analysisQueue,
            throttleHz: Self.analysisThrottleHz
        ) { [weak self] frame in
            Task { await self?.publishAnalysisFrame(frame) }
        }
        videoDataOutput.setSampleBufferDelegate(processor, queue: analysisQueue)
        analysisFrameProcessor = processor

        guard session.canAddOutput(videoDataOutput) else {
            throw CameraServiceError.cannotAddAnalysisOutput
        }
        session.addOutput(videoDataOutput)

        // Deliberately absent this phase: Vision, Motion→engine wiring,
        // AVCaptureVideoPreviewLayer session-config (attached separately —
        // see `attachPreviewLayer(_:)`). See file header.
    }

    // MARK: Interruption / runtime-error handling

    /// Registers interruption/runtime-error observers exactly once
    /// (guarded by `isConfigured` in `start()`). Observer tokens are
    /// intentionally not retained for later removal: `CameraService` is a
    /// single, app-lifetime actor (owned by the future coordinator, never
    /// recreated per capture), so these observers live as long as the
    /// process does — matching the session itself, which is likewise never
    /// torn down mid-session.
    private func subscribeToSessionNotifications() {
        let center = NotificationCenter.default

        _ = center.addObserver(
            forName: AVCaptureSession.wasInterruptedNotification,
            object: session,
            queue: nil
        ) { [weak self] notification in
            // AVCaptureSessionInterruptionReasonKey / InterruptionReason are
            // iOS/macCatalyst/tvOS/visionOS-only (explicitly unavailable on
            // plain macOS) — guarded so this target still builds and tests
            // on macOS, matching CamstheticsEngine's fast macOS-test pattern
            // (ARCHITECTURE.md §6.1). Production behavior (iOS) is
            // unaffected.
            #if os(iOS)
            let reasonValue = (notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int)
                .flatMap { AVCaptureSession.InterruptionReason(rawValue: $0) }
            let reasonDescription = reasonValue.map { String(describing: $0) } ?? "unknown"
            #else
            let reasonDescription = "unknown (interruption reason unavailable on this platform)"
            #endif
            Task { await self?.updateHealth(.interrupted(reason: reasonDescription)) }
        }

        _ = center.addObserver(
            forName: AVCaptureSession.interruptionEndedNotification,
            object: session,
            queue: nil
        ) { [weak self] _ in
            Task { await self?.handleInterruptionEnded() }
        }

        _ = center.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification,
            object: session,
            queue: nil
        ) { [weak self] notification in
            let description = (notification.userInfo?[AVCaptureSessionErrorKey] as? Error)?.localizedDescription
                ?? "unknown runtime error"
            Task { await self?.updateHealth(.failed(description: description)) }
        }
    }

    /// Attempts automatic resume once an interruption clears, per Apple's
    /// documented interruption-handling pattern (`.interruptionEndedNotification`).
    /// Emits `.recovering` before calling `startRunning()` so the UI has a
    /// real signal for that state rather than inferring it.
    private func handleInterruptionEnded() {
        guard isConfigured else {
            updateHealth(.idle)
            return
        }
        if !session.isRunning {
            updateHealth(.recovering)
            session.startRunning()
        }
        updateHealth(session.isRunning ? .running : .idle)
    }

    // MARK: Capture

    /// Captures one photo via the native `AVCapturePhotoOutput` path and
    /// returns the exact, unmodified bytes of
    /// `AVCapturePhoto.fileDataRepresentation()`.
    public func capturePhoto() async throws -> CapturedPhotoArtifact {
        guard isConfigured, session.isRunning else {
            throw CameraServiceError.sessionNotRunning
        }

        let codecs = photoOutput.availablePhotoCodecTypes
        let codec = CaptureFormatSelection.preferredCodec(among: codecs)

        let settings: AVCapturePhotoSettings
        if let codec {
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: codec])
        } else {
            // Documented fallback — let AVCapturePhotoOutput resolve its own
            // device-appropriate default. Never assume JPEG.
            settings = AVCapturePhotoSettings()
        }
        settings.photoQualityPrioritization = .quality
        settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions

        let uniqueID = settings.uniqueID
        do {
            let artifact = try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<CapturedPhotoArtifact, Error>) in
                let processor = PhotoCaptureProcessor(continuation: continuation)
                activeCaptureProcessors[uniqueID] = processor
                photoOutput.capturePhoto(with: settings, delegate: processor)
            }
            activeCaptureProcessors.removeValue(forKey: uniqueID)
            return artifact
        } catch {
            activeCaptureProcessors.removeValue(forKey: uniqueID)
            throw error
        }
    }

    // MARK: Lens / zoom selection
    //
    // Selecting a lens/zoom level changes ONLY `AVCaptureDevice
    // .videoZoomFactor` on the SAME device/input this session already
    // has — it never swaps `AVCaptureDeviceInput`, never touches
    // `photoOutput`, and never brackets a
    // `beginConfiguration()/commitConfiguration()` session reconfiguration.
    // Per Apple's current documentation, zoom is a lightweight device
    // property (guarded only by `lockForConfiguration()`/
    // `unlockForConfiguration()`), entirely orthogonal to session-topology
    // changes — so there is no session disruption, no black frame, and no
    // effect whatsoever on `photoOutput`'s configuration (`maxPhotoDimensions`,
    // codec) when the zoom factor changes. Because `capturePhoto()` always
    // captures through this same `photoOutput`/`device` pair, whichever
    // lens is currently selected via zoom is exactly what the next photo
    // capture uses too — preview and capture stay coherent by construction,
    // not by any explicit synchronization code.

    /// A stream of lens-option list updates. Immediately yields the
    /// current `availableLensOptions()`, then yields again whenever
    /// `device.minAvailableVideoZoomFactor` changes (KVO — see
    /// `minZoomObservation`'s doc comment for why a reactive stream is
    /// used rather than only a one-shot read).
    public func lensOptionsUpdates() -> AsyncStream<[LensOption]> {
        let id = UUID()
        // Same reasoning as `healthUpdates()`: only the latest option
        // list matters.
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            lensOptionsContinuations[id] = continuation
            continuation.yield(availableLensOptions())
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeLensOptionsContinuation(id: id) }
            }
        }
    }

    private func removeLensOptionsContinuation(id: UUID) {
        lensOptionsContinuations.removeValue(forKey: id)
    }

    /// Observes `device.minAvailableVideoZoomFactor` (confirmed
    /// KVO-observable by Apple's current documentation) and re-broadcasts
    /// freshly-derived lens options to every `lensOptionsUpdates()`
    /// subscriber whenever it changes, plus logs a fresh
    /// `debugCameraTopologyDescription()` snapshot so a before/after
    /// comparison is visible on the console if the range does change
    /// after `start()` returns.
    private func subscribeToZoomRangeChanges() {
        #if os(iOS)
        guard let device else { return }
        minZoomObservation = device.observe(\.minAvailableVideoZoomFactor, options: [.new]) { [weak self] _, change in
            guard let self else { return }
            Task {
                await self.handleMinZoomChanged(change.newValue)
            }
        }
        #endif
    }

    #if os(iOS)
    private func handleMinZoomChanged(_ newValue: CGFloat?) {
        print("[CameraTopology] minAvailableVideoZoomFactor changed to \(newValue.map(String.init) ?? "nil") — re-deriving lens options.")
        print(debugCameraTopologyDescription())
        let options = availableLensOptions()
        for continuation in lensOptionsContinuations.values {
            continuation.yield(options)
        }
    }
    #endif

    /// Runtime-discovered lens/zoom options for the currently configured
    /// back camera. Empty until `start()` has configured the session at
    /// least once. Never hard-codes which lenses exist — derived fresh
    /// from `AVCaptureDevice.constituentDevices`,
    /// `minAvailableVideoZoomFactor`, and
    /// `virtualDeviceSwitchOverVideoZoomFactors` on whichever physical
    /// iPhone this runs on (`DECISIONS.md` ADR-011, `PRODUCT_SPEC.md`
    /// FIDELITY-08).
    public func availableLensOptions() -> [LensOption] {
        // `constituentDevices`/`minAvailableVideoZoomFactor`/
        // `virtualDeviceSwitchOverVideoZoomFactors` are all
        // iOS/iPadOS/Mac-Catalyst/tvOS only — explicitly unavailable on
        // plain macOS. Guarded so this target still builds and tests on
        // macOS; on macOS there is exactly one selectable level (matching
        // `LensSelection.options`'s non-virtual-device fallback), since
        // this method's job on that platform is only "compiles and
        // returns something sane," never real camera use.
        #if os(iOS)
        guard let device else { return [] }
        return LensSelection.options(
            constituentDeviceTypes: device.constituentDevices.map(\.deviceType),
            minAvailableVideoZoomFactor: device.minAvailableVideoZoomFactor,
            switchOverVideoZoomFactors: device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat(truncating: $0) }
        )
        #else
        return LensSelection.options(constituentDeviceTypes: [], minAvailableVideoZoomFactor: 1.0, switchOverVideoZoomFactors: [])
        #endif
    }

    /// The zoom factor currently in effect — for UI state (e.g.
    /// highlighting the active lens option). `1.0` before the session is
    /// configured, and always `1.0` on macOS (see `availableLensOptions()`).
    public var currentVideoZoomFactor: CGFloat {
        #if os(iOS)
        device?.videoZoomFactor ?? 1.0
        #else
        1.0
        #endif
    }

    /// Formats an arbitrary RAW `videoZoomFactor` value (e.g. one produced
    /// mid-gesture by a continuous pinch-to-zoom, via `setZoomFactor(_:)`)
    /// using the SAME Wide-lens-relative convention `availableLensOptions()`
    /// labels its `LensOption`s with — so a live pinch readout and a
    /// snapped-to lens button never disagree about what to call the same
    /// raw factor.
    public func displayLabel(forRawZoomFactor factor: CGFloat) -> String {
        #if os(iOS)
        guard let device else { return LensSelection.label(for: factor) }
        let wideEntryFactor: CGFloat? = {
            let types = device.constituentDevices.map(\.deviceType)
            guard let wideIndex = types.firstIndex(of: .builtInWideAngleCamera) else { return nil }
            var entryFactors: [CGFloat] = [device.minAvailableVideoZoomFactor]
            entryFactors.append(contentsOf: device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat(truncating: $0) })
            guard wideIndex < entryFactors.count else { return nil }
            return entryFactors[wideIndex]
        }()
        return LensSelection.label(for: LensSelection.displayFactor(rawZoomFactor: factor, wideEntryFactor: wideEntryFactor))
        #else
        return LensSelection.label(for: factor)
        #endif
    }

    /// The active format's RAW `secondaryNativeResolutionZoomFactors` —
    /// same coordinate space as `videoZoomFactor`/`LensOption.zoomFactor`.
    /// Runtime-queried from whatever device/format is actually active;
    /// never hard-coded to a specific value. Empty on any device/format
    /// that doesn't report one (most devices, most formats) — callers
    /// (e.g. `LensSelection.snapToNativeResolution`) must treat empty as
    /// "no snap points," never assume a value exists.
    public var secondaryNativeResolutionZoomFactors: [CGFloat] {
        #if os(iOS)
        device?.activeFormat.secondaryNativeResolutionZoomFactors ?? []
        #else
        []
        #endif
    }

    /// Target wall-clock duration for a lens/zoom transition, independent
    /// of how large the jump is. Chosen to read as a deliberate, visible
    /// lens change (matching the native Camera app's pace) rather than
    /// either an instant snap or a sluggish crawl.
    ///
    /// Raised from 0.35 to 0.5 after physical-device validation (Phase 2
    /// hardware checkpoint): the previously-logged zoom-out trajectory
    /// (2×→1×) showed ~190ms of near-zero visible zoom change immediately
    /// after `ramp(toVideoZoomFactor:withRate:)` starts (constituent
    /// crossfade engagement latency inherent to this virtual device, not
    /// something a rate parameter eliminates), followed by the rest of the
    /// 1-stop change compressed into the remaining ~450ms — confirmed on
    /// hardware to read as "abrupt and fast" at the start even though the
    /// tail eases in smoothly. A slower target rate (longer duration)
    /// spreads that post-latency motion over more time so the rush after
    /// the onset delay is less pronounced, without changing
    /// `LensSelection.rampRate`'s (already-correct, unit-tested) formula.
    private static let lensTransitionDuration: Float = 0.5

    /// Selects a lens/zoom level. Ramped, not instantly jumped, per
    /// Apple's documented recommendation ("for a smooth transition, use
    /// `ramp(toVideoZoomFactor:withRate:)`") — this is what makes the
    /// transition feel like a native camera/lens change rather than an
    /// abrupt digital crop. On a virtual multi-camera device, the device
    /// itself crossfades to the appropriate physical constituent as the
    /// zoom factor crosses that constituent's switch-over threshold —
    /// no code here needs to know or care which physical lens is active
    /// at any moment — the same `photoOutput`/`device` pair keeps serving
    /// both preview and capture throughout. The rate itself is derived by
    /// `LensSelection.rampRate(from:to:duration:)` — see that function's
    /// doc comment for why a fixed rate was the concrete, non-speculative
    /// cause of the "less smooth than native Camera app" transition.
    ///
    /// `ramp(toVideoZoomFactor:withRate:)` starts the transition and
    /// returns immediately — it does not block this actor for the
    /// transition's duration; the hardware/AVFoundation drives the ramp
    /// asynchronously.
    public func selectLens(_ option: LensOption) throws {
        #if os(iOS)
        guard option.zoomFactor.isFinite, option.zoomFactor > 0 else {
            throw CameraServiceError.lensSelectionFailed("Invalid zoom factor: \(option.zoomFactor).")
        }
        guard let device else {
            throw CameraServiceError.sessionNotRunning
        }
        do {
            try device.lockForConfiguration()
        } catch {
            throw CameraServiceError.lensSelectionFailed(error.localizedDescription)
        }
        defer { device.unlockForConfiguration() }

        let clamped = max(
            device.minAvailableVideoZoomFactor,
            min(option.zoomFactor, device.maxAvailableVideoZoomFactor)
        )
        let rate = LensSelection.rampRate(
            from: device.videoZoomFactor,
            to: clamped,
            duration: Self.lensTransitionDuration
        )
        device.ramp(toVideoZoomFactor: clamped, withRate: rate)
        #else
        throw CameraServiceError.lensSelectionFailed("Lens selection is not available on this platform.")
        #endif
    }

    /// Directly sets `videoZoomFactor` — no ramp. For continuous, real-time
    /// tracking of a pinch/magnification gesture, where the gesture itself
    /// already supplies smooth frame-by-frame interpolation; `ramp` (via
    /// `selectLens(_:)`) remains reserved for discrete, button-triggered
    /// lens snaps, where a synthetic ramp is what makes an instant jump
    /// feel like a deliberate transition. This still only ever moves the
    /// SAME device's `videoZoomFactor` within its already-available range
    /// — same mechanism, same virtual-device constituent crossfade,
    /// nothing digital layered on top; it's the standard AVFoundation
    /// pattern for a live pinch-to-zoom gesture (set the value directly on
    /// every gesture update rather than issuing a new ramp per frame).
    /// Clamped to `minAvailableVideoZoomFactor...maxAvailableVideoZoomFactor`
    /// exactly like `selectLens(_:)`, so a gesture can never request an
    /// unsupported zoom level.
    public func setZoomFactor(_ factor: CGFloat) throws {
        #if os(iOS)
        guard factor.isFinite, factor > 0 else {
            throw CameraServiceError.lensSelectionFailed("Invalid zoom factor: \(factor).")
        }
        guard let device else {
            throw CameraServiceError.sessionNotRunning
        }
        do {
            try device.lockForConfiguration()
        } catch {
            throw CameraServiceError.lensSelectionFailed(error.localizedDescription)
        }
        defer { device.unlockForConfiguration() }
        device.videoZoomFactor = max(
            device.minAvailableVideoZoomFactor,
            min(factor, device.maxAvailableVideoZoomFactor)
        )
        #else
        throw CameraServiceError.lensSelectionFailed("Zoom is not available on this platform.")
        #endif
    }

    // MARK: Tap-to-focus / tap-to-exposure
    //
    // Phase 2 deliverable (`docs/IMPLEMENTATION_PLAN.md` §Phase 2:
    // "…lens selection … and tap-to-focus/exposure").
    //
    // Every capability here is runtime-queried on the ACTIVE device
    // (`isFocusPointOfInterestSupported`, `isExposurePointOfInterestSupported`,
    // `isFocusModeSupported(_:)`, `isExposureModeSupported(_:)`) rather
    // than assumed — a device that doesn't support a given mode simply
    // skips that half instead of throwing, so a partially-capable camera
    // still gets whatever it can do. Nothing here is gated on a device
    // model.
    //
    // Points are in AVFoundation's DEVICE coordinate space (origin
    // top-left {0,0} … bottom-right {1,1} of the *sensor* image, not the
    // view). Callers must convert from view coordinates using
    // `AVCaptureVideoPreviewLayer.captureDevicePointConverted(fromLayerPoint:)`,
    // which correctly accounts for `videoGravity` cropping and rotation —
    // this actor deliberately does not take view points, because it has
    // no knowledge of any layer's geometry.

    /// Focus and expose at a device point, then (unless `locked`) leave
    /// the device in continuous auto mode so it keeps tracking.
    ///
    /// - Parameters:
    ///   - devicePoint: normalized sensor-space point, each axis 0…1.
    ///   - locked: when true, uses the one-shot `.autoFocus`/`.autoExpose`
    ///     modes, which settle once and then hold (the "AE/AF LOCK"
    ///     behaviour) rather than continuously re-evaluating.
    public func focusAndExpose(atDevicePoint devicePoint: CGPoint, locked: Bool = false) throws {
        #if os(iOS)
        guard devicePoint.x.isFinite, devicePoint.y.isFinite,
              (0...1).contains(devicePoint.x), (0...1).contains(devicePoint.y) else {
            throw CameraServiceError.focusExposureFailed(
                "Device point out of range: \(devicePoint) (expected 0…1 on both axes)."
            )
        }
        guard let device else { throw CameraServiceError.sessionNotRunning }

        do {
            try device.lockForConfiguration()
        } catch {
            throw CameraServiceError.focusExposureFailed(error.localizedDescription)
        }
        defer { device.unlockForConfiguration() }

        let focusMode: AVCaptureDevice.FocusMode = locked ? .autoFocus : .continuousAutoFocus
        if device.isFocusPointOfInterestSupported, device.isFocusModeSupported(focusMode) {
            device.focusPointOfInterest = devicePoint
            device.focusMode = focusMode
        }

        let exposureMode: AVCaptureDevice.ExposureMode = locked ? .autoExpose : .continuousAutoExposure
        if device.isExposurePointOfInterestSupported, device.isExposureModeSupported(exposureMode) {
            device.exposurePointOfInterest = devicePoint
            device.exposureMode = exposureMode
        }
        #else
        throw CameraServiceError.focusExposureFailed("Focus/exposure is not available on this platform.")
        #endif
    }

    /// Returns the device to continuous auto focus/exposure at the centre
    /// — the "auto-cancel" behaviour `PRODUCT_SPEC.md` §1.5 requires a
    /// tap-to-focus reticle to fall back to after
    /// `Self.focusExposureAutoCancelSeconds`.
    ///
    /// Caller-driven rather than self-scheduling: the timing belongs to
    /// the UI layer that owns the reticle's lifetime, and burying a
    /// `Task.sleep` in here would make the actor's behaviour depend on
    /// wall-clock time in a way that's awkward to test or cancel.
    public func resumeContinuousFocusAndExposure() throws {
        #if os(iOS)
        guard let device else { throw CameraServiceError.sessionNotRunning }
        do {
            try device.lockForConfiguration()
        } catch {
            throw CameraServiceError.focusExposureFailed(error.localizedDescription)
        }
        defer { device.unlockForConfiguration() }

        let centre = CGPoint(x: 0.5, y: 0.5)
        if device.isFocusPointOfInterestSupported, device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusPointOfInterest = centre
            device.focusMode = .continuousAutoFocus
        }
        if device.isExposurePointOfInterestSupported, device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposurePointOfInterest = centre
            device.exposureMode = .continuousAutoExposure
        }
        #else
        throw CameraServiceError.focusExposureFailed("Focus/exposure is not available on this platform.")
        #endif
    }

    /// Applies an exposure-bias offset in EV, clamped by
    /// `LensSelection.clampedExposureBias` to both the device's reported
    /// range and the product's tighter ±2 EV limit. Returns the value
    /// actually applied, so a caller driving this from a drag gesture can
    /// render the real number without a second round-trip.
    @discardableResult
    public func setExposureTargetBias(_ bias: Float) throws -> Float {
        #if os(iOS)
        guard let device else { throw CameraServiceError.sessionNotRunning }
        let clamped = LensSelection.clampedExposureBias(
            bias,
            deviceMin: device.minExposureTargetBias,
            deviceMax: device.maxExposureTargetBias
        )
        do {
            try device.lockForConfiguration()
        } catch {
            throw CameraServiceError.focusExposureFailed(error.localizedDescription)
        }
        defer { device.unlockForConfiguration() }
        device.setExposureTargetBias(clamped)
        return clamped
        #else
        throw CameraServiceError.focusExposureFailed("Exposure bias is not available on this platform.")
        #endif
    }

    /// How long a tap-driven focus/exposure lock should persist before
    /// reverting to continuous auto — `PRODUCT_SPEC.md` §1.5.
    public static let focusExposureAutoCancelSeconds: Double = 3.0

    // MARK: Preview (Phase 2.2)
    //
    // A preview layer is a pure display surface reading this session's
    // video stream through its own dedicated AVCaptureConnection — it is
    // never a second AVCaptureSession, and nothing here ever reads pixels
    // out of it. Attaching/detaching a preview layer touches only that
    // connection; it never reconfigures `photoOutput` and cannot affect
    // `capturePhoto()` (docs/ARCHITECTURE.md §4.4's pipeline separation).

    /// Binds a preview layer to this actor's SAME `AVCaptureSession` and
    /// keeps its rotation angle in sync with device orientation via
    /// `AVCaptureDevice.RotationCoordinator` (iOS 17+ — the current,
    /// non-deprecated mechanism; `AVCaptureConnection.videoOrientation` is
    /// deprecated). This is entirely independent of the photo-capture
    /// connection's own rotation handling: per Apple's current
    /// documentation, a preview/video-data connection *physically rotates*
    /// the frames it delivers, while a photo-output connection instead
    /// applies rotation via an Exif tag — two separate connection objects,
    /// two separate rotation values, by construction.
    ///
    /// Meant to be called exactly once per preview surface's lifetime (by
    /// its `UIViewRepresentable.makeUIView`, not `updateUIView` — calling
    /// this on every SwiftUI re-render was this file's previously
    /// identified preview-lifecycle issue: it recreated a
    /// `RotationCoordinator` and KVO observation on every re-render
    /// instead of once). Safe to call before `start()` has configured the
    /// session — rotation setup is then finished automatically once
    /// `start()` completes, via `pendingPreviewLayer`, so caller ordering
    /// doesn't matter.
    public func attachPreviewLayer(_ layer: AVCaptureVideoPreviewLayer) {
        layer.session = session
        layer.videoGravity = .resizeAspectFill

        // Mirroring handled explicitly, never left to AVFoundation's
        // automatic default: v1 ships back-camera-only (ADR-011), so the
        // preview must never be mirrored. Front-camera mirroring is
        // deferred to the lens-switching phase, where it will be driven by
        // the same explicit policy rather than an accidental default.
        if let connection = layer.connection {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }

        guard let device else {
            // Not configured yet (start() hasn't run). The layer is still
            // bound to the session above, so frames appear as soon as the
            // session starts running; remember it so start() can finish
            // rotation setup without the caller needing to attach again.
            pendingPreviewLayer = layer
            return
        }

        configureRotation(for: layer, device: device)
    }

    /// Detaches a preview layer from the session (e.g. when its view
    /// disappears) without stopping the session itself — capture must
    /// remain usable independent of whether a preview is currently shown.
    public func detachPreviewLayer(_ layer: AVCaptureVideoPreviewLayer) {
        rotationObservation = nil
        rotationCoordinator = nil
        if pendingPreviewLayer === layer {
            pendingPreviewLayer = nil
        }
        if layer.session === session {
            layer.session = nil
        }
    }

    /// Creates and wires up the `RotationCoordinator`/KVO observation for
    /// one preview layer. Called at most once per attached layer — either
    /// immediately from `attachPreviewLayer(_:)` (device already known) or
    /// once from `start()` (device became known after the layer attached).
    private func configureRotation(for layer: AVCaptureVideoPreviewLayer, device: AVCaptureDevice) {
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: layer)
        rotationCoordinator = coordinator
        Self.applyRotationAngle(coordinator.videoRotationAngleForHorizonLevelPreview, to: layer)

        rotationObservation = coordinator.observe(
            \.videoRotationAngleForHorizonLevelPreview,
            options: [.new]
        ) { [weak layer] _, change in
            guard let layer, let angle = change.newValue else { return }
            Self.applyRotationAngle(angle, to: layer)
        }
    }

    private static func applyRotationAngle(_ angle: CGFloat, to layer: AVCaptureVideoPreviewLayer) {
        guard let connection = layer.connection, connection.isVideoRotationAngleSupported(angle) else { return }
        connection.videoRotationAngle = angle
    }
}
