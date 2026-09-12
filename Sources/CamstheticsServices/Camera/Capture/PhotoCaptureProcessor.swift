import AVFoundation

// MARK: - Phase 2.1 — AVCapturePhotoCaptureDelegate (production)
//
// One instance handles exactly one capture request, then is discarded —
// `CameraService.capturePhoto()` is responsible for keeping it alive for the
// duration of the request (AVCapturePhotoOutput does not retain its
// delegate).
//
// Photo-capture delegate callbacks are not guaranteed to land on any
// particular queue or thread (verified against Apple's current AVFoundation
// documentation), so this type makes no assumption about where its
// callbacks run — it only ever resumes the `CheckedContinuation` it was
// created with, which is queue-agnostic by design. This mirrors the same
// defensive posture the Phase 2.0 harness's delegate already took
// (`CaptureFidelityProofHarness.swift`'s `didFinishProcessingPhoto`
// comment), expressed here via Swift concurrency instead of a manual
// `harnessQueue.async` hop.
final class PhotoCaptureProcessor: NSObject, AVCapturePhotoCaptureDelegate {

    private let continuation: CheckedContinuation<CapturedPhotoArtifact, Error>
    private var didResume = false

    init(continuation: CheckedContinuation<CapturedPhotoArtifact, Error>) {
        self.continuation = continuation
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard !didResume else { return }
        didResume = true

        if let error {
            continuation.resume(throwing: CameraServiceError.captureFailed(error.localizedDescription))
            return
        }

        // The ONLY source of the returned artifact:
        // AVCapturePhoto.fileDataRepresentation(). Nothing here
        // reconstructs an image from a pixel buffer, the preview layer, or
        // a screenshot — matching the Phase 2.0 proof harness's constraint.
        guard let data = photo.fileDataRepresentation() else {
            continuation.resume(throwing: CameraServiceError.fileDataRepresentationUnavailable)
            return
        }

        continuation.resume(returning: CapturedPhotoArtifact(data: data))
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
        error: Error?
    ) {
        // Only relevant if capture aborted before `didFinishProcessingPhoto`
        // ever fired (e.g. processing never started) — otherwise this is a
        // no-op, since `didResume` is already true.
        guard let error, !didResume else { return }
        didResume = true
        continuation.resume(throwing: CameraServiceError.captureFailed(error.localizedDescription))
    }
}
