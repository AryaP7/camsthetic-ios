import Foundation
import Vision
import CoreVideo
import CoreMedia
import CamstheticsEngine

// MARK: - Phase 3 — VisionService (on-device subject/pose detection)
//
// Runs `VNDetectHumanBodyPoseRequest` + `VNGenerateAttentionBasedSaliencyImageRequest`
// against `CameraService.analysisFrameUpdates()` frames
// (`docs/IMPLEMENTATION_PLAN.md` Phase 3's exact deliverable). No second
// throttle here — that stream is already 10Hz-throttled with a
// single-frame-in-flight backpressure gate (Phase 2 Step 2); this actor's
// job is to keep inference under that gate's own release window, not add
// a second one (`docs/ARCHITECTURE.md` §4.1).
//
// Produces `CamstheticsEngine.SubjectCandidate` values only — never
// arbitrates between them. `SubjectSelector`'s scoring/sticky-lock logic
// already exists, fully tested, from Phase 1; this actor feeds it real
// detections, it doesn't reimplement arbitration.
//
// Image Fidelity Dependency Rule (`docs/ARCHITECTURE.md`): "VisionService
// consumes analysis representations only; it has no reference to the
// photo output and cannot influence its configuration." This actor holds
// no `AVCaptureSession`/`CameraService` reference at all — it's handed an
// `AsyncStream<AnalysisFrame>` to consume, nothing more.

/// One Vision-derived observation of a single analysis frame: the primary
/// subject candidates it yielded (empty if none), ready for
/// `CamstheticsEngine.SubjectSelector.update(candidates:)` to arbitrate.
public struct VisionObservation: Sendable {
    public let candidates: [SubjectCandidate]
    public let timestamp: CMTime

    public init(candidates: [SubjectCandidate], timestamp: CMTime) {
        self.candidates = candidates
        self.timestamp = timestamp
    }
}

public enum VisionServiceError: LocalizedError, Sendable {
    case inferenceFailed(String)

    public var errorDescription: String? {
        switch self {
        case .inferenceFailed(let description):
            return "Vision inference failed: \(description)"
        }
    }
}

public actor VisionService {

    /// Target per-frame inference latency
    /// (`docs/IMPLEMENTATION_PLAN.md` Phase 3 exit criterion: "≤25ms per
    /// frame on A14+ Bionic"). Not enforced in-process — measured
    /// on-device, the same way motion jitter and FIDELITY-02 were measured
    /// this project cycle, not assumed from documentation.
    public static let inferenceLatencyBudgetMs: Double = 25.0

    private var latest: VisionObservation?
    private var continuations: [UUID: AsyncStream<VisionObservation>.Continuation] = [:]

    public init() {}

    /// The most recent observation, or `nil` before the first one arrives.
    /// Mirrors `MotionService.latestAttitude`'s pull-at-evaluation-time
    /// contract (`docs/ARCHITECTURE.md` §4.1: motion/vision are merged
    /// with the coordinator "at the instant of evaluation", not pushed).
    public var latestObservation: VisionObservation? { latest }

    /// A stream of observations. Immediately yields the current one if it
    /// exists — same pattern as `CameraService.healthUpdates()`/
    /// `MotionService.attitudeUpdates()`.
    public func observationUpdates() -> AsyncStream<VisionObservation> {
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

    /// Consumes `frames` until the stream ends (session stop) — one call
    /// per session, driven by whatever owns both `CameraService` and this
    /// actor (a future `CoachingSessionCoordinator`, Phase 5; not wired
    /// here, per this phase's explicit scope boundary).
    public func consume(_ frames: AsyncStream<AnalysisFrame>) async {
        for await frame in frames {
            await ingest(frame)
        }
    }

    private func ingest(_ frame: AnalysisFrame) async {
        // Must run for every frame regardless of outcome — this is what
        // releases `CameraService`'s single-frame-in-flight backpressure
        // gate (`AnalysisFrameProcessor`'s documented contract) for the
        // next throttled frame.
        defer { frame.markProcessed() }
        do {
            let candidates = try Self.detectSubjectCandidates(in: frame.pixelBuffer)
            let observation = VisionObservation(candidates: candidates, timestamp: frame.timestamp)
            latest = observation
            for continuation in continuations.values {
                continuation.yield(observation)
            }
        } catch {
            // Non-fatal: one failed inference just means no update this
            // cycle — the next throttled frame tries again. Matches
            // `CameraViewModel`'s established "no error-surfacing
            // affordance yet" posture for non-fidelity-critical paths.
        }
    }

    // MARK: Vision request execution
    //
    // Delegates all candidate extraction to `VisionSubjectExtraction` —
    // shared with `TargetExtractor` (one-shot still images) so the two
    // paths can never silently diverge. Plain `static func`, implicitly
    // nonisolated (no per-instance actor state touched).

    private static func detectSubjectCandidates(in pixelBuffer: CVPixelBuffer) throws -> [SubjectCandidate] {
        // ASSUMPTION requiring on-device verification, documented rather
        // than silently hard-coded: `.right` is the conventional
        // orientation for an unrotated back-camera buffer with the device
        // held portrait (the standard convention in Apple's own Vision +
        // AVFoundation sample code for exactly this configuration).
        // `CameraService`'s analysis output connection has no rotation
        // applied — only the PREVIEW layer's connection gets one (see
        // `CameraService.configureRotation`) — so this buffer arrives in
        // raw sensor orientation. If on-device pose detection comes back
        // sideways/upside-down, this is the first thing to check and fix.
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
        do {
            return try VisionSubjectExtraction.detectSubjectCandidates(using: handler)
        } catch {
            throw VisionServiceError.inferenceFailed(error.localizedDescription)
        }
    }
}
