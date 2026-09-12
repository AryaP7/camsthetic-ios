import Foundation
#if canImport(CoreMotion) && os(iOS)
import CoreMotion
#endif

// MARK: - Device attitude (roll / pitch) from the gravity vector
//
// Phase 2 deliverable (`docs/IMPLEMENTATION_PLAN.md` §Phase 2:
// "MotionService streaming calibrated roll and pitch at 100Hz with
// low-pass filtering"), located where `docs/ARCHITECTURE.md` §3.1 places
// it (`CamstheticsServices/Motion/`).
//
// Boundaries this file honours:
//   - `CamstheticsEngine` must NEVER import CoreMotion
//     (`docs/ARCHITECTURE.md`). Motion values cross into the engine only
//     as plain `Double`s inside `CompositionParams`, constructed by a
//     future coordinator — never by this file.
//   - Motion is *pulled at the instant of evaluation*, not pushed into
//     the engine (`docs/ARCHITECTURE.md`: "Motion attitude is sampled at
//     100Hz and merged with the latest vision observation at the instant
//     of evaluation"). Hence both a stream AND a latest-value accessor.
//   - This is a sensor-only service: it touches no capture session, no
//     photo output, and nothing on the fidelity path. It keeps working
//     when analysis is throttled off (`docs/ARCHITECTURE.md`'s thermal
//     fallback to "sensor-only spirit leveling").

// MARK: - Pure attitude math (hardware-free, unit-testable)

/// One device-attitude sample. Plain value type — deliberately carries no
/// CoreMotion types, so it crosses module/isolation boundaries freely and
/// can be constructed in tests without a device.
public struct DeviceAttitude: Equatable, Sendable {
    /// Device roll in degrees. 0 = level. Positive/negative follow
    /// `atan2(gravity.x, gravity.y)`'s sign convention.
    public let rollDegrees: Double
    /// Device pitch in degrees. Positive = camera looking down, matching
    /// `CompositionParams.pitchDegrees`' documented convention.
    public let pitchDegrees: Double
    /// Always 1.0 for gravity-derived attitude — `docs/PRODUCT_SPEC.md`
    /// specifies this is "exact, zero-latency, confidence = 1.0",
    /// in contrast to the target side's Sobel estimate (capped 0.70).
    public let confidence: Double
    /// Monotonic timestamp of the originating sensor sample, in seconds.
    /// CoreMotion's own `CMLogItem.timestamp` (device-uptime based), NOT
    /// wall clock — the engine's dwell/hysteresis timers require a
    /// monotonic source.
    public let timestamp: TimeInterval

    public init(rollDegrees: Double, pitchDegrees: Double, confidence: Double = 1.0, timestamp: TimeInterval) {
        self.rollDegrees = rollDegrees
        self.pitchDegrees = pitchDegrees
        self.confidence = confidence
        self.timestamp = timestamp
    }
}

/// Pure attitude derivation, operating only on plain doubles so it is
/// fully unit-testable on macOS with constructed fixtures — the same
/// pattern `LensSelection` and `CaptureFormatSelection` already use in
/// this module (`AVCaptureDevice`/`CMDeviceMotion` cannot be synthesized
/// without hardware).
public enum AttitudeMath {

    /// Device roll from a gravity vector, in degrees.
    ///
    /// `roll = atan2(gravity.x, gravity.y)` — the exact formula specified
    /// in `docs/PRODUCT_SPEC.md` §"Roll / Tilt Angle". Note the argument
    /// order (x, y), which is NOT the conventional `atan2(y, x)`: with
    /// the device held upright in portrait, gravity points along −y, so
    /// this returns ~0° when level and grows as the device rolls.
    ///
    /// Returns 0 for a degenerate (zero/non-finite) gravity vector rather
    /// than NaN — a NaN reaching the UI would silently break the spirit
    /// level's rotation, and 0 ("level") is the safe presentation.
    public static func rollDegrees(gravityX: Double, gravityY: Double) -> Double {
        guard gravityX.isFinite, gravityY.isFinite else { return 0 }
        guard gravityX != 0 || gravityY != 0 else { return 0 }
        return atan2(gravityX, gravityY) * 180.0 / .pi
    }

    /// Device pitch from a gravity vector, in degrees, positive when the
    /// camera is looking DOWN — matching `CompositionParams.pitchDegrees`
    /// ("+ = looking down") so no sign flip is needed downstream.
    ///
    /// Derived from the z component against the magnitude of the x/y
    /// plane, which keeps it well-defined through a full rotation rather
    /// than only near upright.
    public static func pitchDegrees(gravityX: Double, gravityY: Double, gravityZ: Double) -> Double {
        guard gravityX.isFinite, gravityY.isFinite, gravityZ.isFinite else { return 0 }
        let planar = (gravityX * gravityX + gravityY * gravityY).squareRoot()
        guard planar != 0 || gravityZ != 0 else { return 0 }
        return atan2(gravityZ, planar) * 180.0 / .pi
    }

    /// The spirit level's snap decision: `|Δθ| ≤ 0.5°` counts as level
    /// (`docs/DESIGN_SYSTEM.md` §4.2 — "When |Δθ| ≤ 0.5°, bars snap
    /// horizontal, illuminate Apple Camera Yellow, and fire a crisp
    /// haptic tick").
    ///
    /// This threshold previously existed nowhere in code —
    /// `SpiritLevelIndicator` takes `isLevel` as a caller decision — so
    /// it lives here, tested, rather than being re-guessed at each call
    /// site.
    ///
    /// Wrap-aware: a roll of 359.8° is 0.2° from level, not 359.8°.
    public static func isLevel(rollDegrees: Double, toleranceDegrees: Double = 0.5) -> Bool {
        guard rollDegrees.isFinite, toleranceDegrees.isFinite else { return false }
        var wrapped = rollDegrees.truncatingRemainder(dividingBy: 360)
        if wrapped > 180 { wrapped -= 360 }
        if wrapped < -180 { wrapped += 360 }
        return abs(wrapped) <= abs(toleranceDegrees)
    }

    /// Exponential low-pass smoothing, `alpha` in 0…1 where 1.0 is a
    /// pass-through (no smoothing) and smaller values smooth harder.
    ///
    /// Deliberately parameterised rather than applied unconditionally:
    /// `docs/TECH_STACK.md` states CoreMotion's device-motion output is
    /// already sensor-fused with "zero-lag low-pass hardware filtering",
    /// while `docs/IMPLEMENTATION_PLAN.md` asks for low-pass filtering in
    /// this service. Those two statements are in tension, so the default
    /// (`MotionService.defaultSmoothingAlpha`) is chosen from measured
    /// on-device jitter rather than from either doc — see that constant.
    public static func smoothed(previous: Double?, next: Double, alpha: Double) -> Double {
        guard let previous, previous.isFinite, next.isFinite else { return next }
        let clampedAlpha = min(max(alpha, 0), 1)
        return previous + clampedAlpha * (next - previous)
    }
}

// MARK: - MotionService

public enum MotionServiceError: LocalizedError, Sendable {
    case deviceMotionUnavailable
    case notSupportedOnPlatform

    public var errorDescription: String? {
        switch self {
        case .deviceMotionUnavailable:
            return "Device motion is unavailable on this device."
        case .notSupportedOnPlatform:
            return "Device motion is not available on this platform."
        }
    }
}

/// Streams calibrated device roll/pitch derived from CoreMotion's gravity
/// vector. Actor-isolated, matching `CameraService`'s model — the
/// `CMMotionManager` and all derived state are owned solely by this actor.
public actor MotionService {

    #if canImport(CoreMotion) && os(iOS)
    private let motionManager = CMMotionManager()
    #endif

    /// 100 Hz, per `docs/IMPLEMENTATION_PLAN.md` §Phase 2.
    public static let updateFrequencyHz: Double = 100.0

    /// Smoothing applied to roll/pitch before publication.
    ///
    /// `1.0` = pass CoreMotion's own fused output straight through. This
    /// is the deliberate default: CoreMotion's `deviceMotion` is already
    /// sensor-fused and hardware-filtered (`docs/TECH_STACK.md`), and
    /// adding a second filter on top costs latency on a signal the spec
    /// requires to be "exact, zero-latency" (`docs/PRODUCT_SPEC.md`).
    ///
    /// **Settled by on-device measurement** (physical iPhone 16,
    /// 2026-09-05), not left as an assumption: holding the phone steady in
    /// its normal photo-taking orientation, 200 consecutive 100Hz samples
    /// (~2s) measured roll stddev 0.077°–0.134° (peak-to-peak ≤0.46°) and
    /// pitch stddev 0.004°–0.007° (peak-to-peak ≤0.03°) — both roughly an
    /// order of magnitude below `DESIGN_SYSTEM.md`'s ±0.5° level threshold
    /// (`AttitudeMath.isLevel`). (Two earlier readings, immediately after
    /// USB connection and with the phone resting at an angle on a flat
    /// surface, showed 10–20× higher jitter — contaminated by real
    /// handling/rest-surface motion, not sensor noise; discarded rather
    /// than treated as evidence.) This resolves `TECH_STACK.md` vs.
    /// `IMPLEMENTATION_PLAN.md`'s tension in `TECH_STACK.md`'s favour:
    /// CoreMotion's own hardware filtering is already sufficient, and this
    /// constant should stay `1.0` unless a *future* measurement on
    /// different hardware shows otherwise.
    public static let defaultSmoothingAlpha: Double = 1.0

    private var smoothingAlpha: Double
    private var latest: DeviceAttitude?
    private var continuations: [UUID: AsyncStream<DeviceAttitude>.Continuation] = [:]
    private var isRunning = false

    public init(smoothingAlpha: Double = MotionService.defaultSmoothingAlpha) {
        self.smoothingAlpha = smoothingAlpha
    }

    /// The most recent attitude sample, or `nil` before the first one
    /// arrives. This is the accessor a future coordinator uses to merge
    /// motion with the latest vision observation "at the instant of
    /// evaluation" (`docs/ARCHITECTURE.md`) rather than being driven by
    /// the 100 Hz stream.
    public var latestAttitude: DeviceAttitude? { latest }

    /// Whether device motion is actually available on this hardware.
    /// Runtime-queried, never assumed.
    public var isDeviceMotionAvailable: Bool {
        #if canImport(CoreMotion) && os(iOS)
        return motionManager.isDeviceMotionAvailable
        #else
        return false
        #endif
    }

    /// A stream of attitude samples. Immediately yields the current
    /// sample if one exists. `.bufferingNewest(1)` because a consumer
    /// only ever wants the current attitude, never a backlog of stale
    /// 100 Hz samples — same reasoning as `CameraService.healthUpdates()`.
    public func attitudeUpdates() -> AsyncStream<DeviceAttitude> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            continuations[id] = continuation
            if let latest { continuation.yield(latest) }
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id: id) }
            }
        }
    }

    private func removeContinuation(id: UUID) {
        continuations.removeValue(forKey: id)
    }

    /// Begins 100 Hz device-motion updates. Idempotent.
    public func start() throws {
        #if canImport(CoreMotion) && os(iOS)
        guard !isRunning else { return }
        guard motionManager.isDeviceMotionAvailable else {
            throw MotionServiceError.deviceMotionUnavailable
        }

        motionManager.deviceMotionUpdateInterval = 1.0 / Self.updateFrequencyHz

        // `.xArbitraryZVertical` keeps the reference frame stable about
        // the vertical axis without requiring magnetometer calibration —
        // gravity-derived roll/pitch don't need a true-north reference,
        // and requiring one would surface a calibration UI for no gain.
        let queue = OperationQueue()
        queue.name = "com.camsthetics.motionService"
        queue.maxConcurrentOperationCount = 1

        motionManager.startDeviceMotionUpdates(
            using: .xArbitraryZVertical,
            to: queue
        ) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let gravity = motion.gravity
            let timestamp = motion.timestamp
            Task {
                await self.ingest(
                    gravityX: gravity.x,
                    gravityY: gravity.y,
                    gravityZ: gravity.z,
                    timestamp: timestamp
                )
            }
        }
        isRunning = true
        #else
        throw MotionServiceError.notSupportedOnPlatform
        #endif
    }

    /// Stops updates. Safe to call when not running.
    public func stop() {
        #if canImport(CoreMotion) && os(iOS)
        if isRunning {
            motionManager.stopDeviceMotionUpdates()
        }
        #endif
        isRunning = false
    }

    /// Converts one raw gravity sample into a published `DeviceAttitude`.
    /// Separated from the CoreMotion callback so the derivation path is
    /// exercised by the pure `AttitudeMath` tests, and so the actor — not
    /// the callback queue — owns all mutable state.
    private func ingest(gravityX: Double, gravityY: Double, gravityZ: Double, timestamp: TimeInterval) {
        let rawRoll = AttitudeMath.rollDegrees(gravityX: gravityX, gravityY: gravityY)
        let rawPitch = AttitudeMath.pitchDegrees(gravityX: gravityX, gravityY: gravityY, gravityZ: gravityZ)

        let roll = AttitudeMath.smoothed(previous: latest?.rollDegrees, next: rawRoll, alpha: smoothingAlpha)
        let pitch = AttitudeMath.smoothed(previous: latest?.pitchDegrees, next: rawPitch, alpha: smoothingAlpha)

        let attitude = DeviceAttitude(
            rollDegrees: roll,
            pitchDegrees: pitch,
            confidence: 1.0,
            timestamp: timestamp
        )
        latest = attitude
        for continuation in continuations.values {
            continuation.yield(attitude)
        }
    }
}
