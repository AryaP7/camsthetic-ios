import AVFoundation
import CoreMedia

// MARK: - Phase 2 Step 2 — analysis output (AVCaptureVideoDataOutput)
//
// Feeds Vision (Phase 3 — not wired here yet: this file only produces
// frames, it never interprets them). Structurally separate from the
// AVCapturePhotoOutput capture path — the independence the Phase 2.0
// harness proved on-device (`docs/DECISIONS.md` ADR-009/ADR-013) and this
// production wiring must re-prove (FIDELITY-02).

/// One analysis frame handed to a future Vision consumer. Deliberately NOT
/// the raw `CMSampleBuffer` — `pixelBuffer` plus its timestamp is all a
/// consumer needs.
///
/// `@unchecked Sendable`: `CVPixelBuffer` (`CVBuffer`) has no `Sendable`
/// conformance in this SDK (confirmed by attempting `Sendable` here and
/// getting a compiler error) — a gap in Apple's own Sendable auditing of
/// CoreVideo's CF types, not a real thread-safety hazard: handing a
/// `CVPixelBuffer` from a capture callback to a background-queue consumer
/// (Vision included) is exactly how every AVFoundation analysis pipeline
/// works. The single-frame-in-flight gate this type is part of
/// (`AnalysisFrameProcessor`) additionally guarantees only one consumer
/// ever holds a given buffer at a time.
public struct AnalysisFrame: @unchecked Sendable {
    public let pixelBuffer: CVPixelBuffer
    public let timestamp: CMTime

    /// Releases the single-frame-in-flight backpressure gate
    /// (`docs/ARCHITECTURE.md`: "at most one frame in flight"). The
    /// consumer must call this exactly once when done reading
    /// `pixelBuffer` — until it does, `AnalysisFrameProcessor` forwards no
    /// further frames. Deliberate: a stalled Phase 3 consumer must stop
    /// receiving frames, not silently pile them up behind it.
    public let markProcessed: @Sendable () -> Void
}

/// `AVCaptureVideoDataOutputSampleBufferDelegate` for the analysis path.
///
/// Throttles to a fixed rate and enforces the single-frame-in-flight gate
/// entirely on `queue` — the one dedicated serial queue this processor is
/// constructed with and installed on via
/// `AVCaptureVideoDataOutput.setSampleBufferDelegate(_:queue:)`. Both
/// `captureOutput(_:didOutput:from:)` and `markProcessed`'s gate release
/// are confined to that same queue (the latter via `queue.async`), so
/// `lastForwardedTimestamp`/`isProcessing` never need a lock despite not
/// being actor-isolated — actor isolation would mean an `await` hop on
/// every single frame at up to 30fps just to decide whether to throttle
/// it away, which is the opposite of the point of throttling.
///
/// `@unchecked Sendable`: the invariant above is exactly what makes this
/// safe, not the type system — documented here rather than asserted
/// silently.
final class AnalysisFrameProcessor: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {

    private let queue: DispatchQueue
    private let minFrameInterval: CMTime
    private let onFrame: @Sendable (AnalysisFrame) -> Void

    private var lastForwardedTimestamp: CMTime?
    private var isProcessing = false

    /// - Parameters:
    ///   - queue: the dedicated serial queue this processor will be
    ///     installed on. Must be serial (the default for a plain
    ///     `DispatchQueue()`) — a concurrent queue would break the
    ///     no-lock invariant above.
    ///   - throttleHz: forwarded-frame rate ceiling (10Hz per
    ///     `docs/IMPLEMENTATION_PLAN.md` §Phase 2).
    ///   - onFrame: called on `queue` for every frame that survives both
    ///     the throttle and the backpressure gate.
    init(queue: DispatchQueue, throttleHz: Double, onFrame: @escaping @Sendable (AnalysisFrame) -> Void) {
        self.queue = queue
        self.minFrameInterval = CMTime(seconds: 1.0 / throttleHz, preferredTimescale: 600)
        self.onFrame = onFrame
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard !isProcessing else { return }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if let lastForwardedTimestamp {
            guard CMTimeSubtract(timestamp, lastForwardedTimestamp) >= minFrameInterval else { return }
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        isProcessing = true
        lastForwardedTimestamp = timestamp

        let frame = AnalysisFrame(pixelBuffer: pixelBuffer, timestamp: timestamp) { [weak self] in
            guard let self else { return }
            self.queue.async { self.isProcessing = false }
        }
        onFrame(frame)
    }
}
