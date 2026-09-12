import Vision
import CamstheticsEngine

// MARK: - Shared Vision → SubjectCandidate bridge
//
// Factored out of `VisionService` so `TargetExtractor` (one-shot, still
// images) can reuse the EXACT same candidate-extraction logic as the live
// analysis path, rather than a second, silently-diverging copy of it.
enum VisionSubjectExtraction {

    /// Confidence floor for INCLUDING a body-pose joint in the
    /// bounding-box computation — chosen conservatively (Vision's
    /// low-confidence points are frequently off-body guesses when a joint
    /// is occluded/out of frame). Not yet validated against real bodies
    /// on-device — flagged as a tuning candidate, not asserted final.
    static let jointConfidenceFloor: VNConfidence = 0.2

    /// One `SubjectCandidate` per detected body, with the eye-line
    /// midpoint as its anchor when both eyes are recognized with
    /// reasonable confidence (`docs/ARCHITECTURE.md` §4.2: "the eye-line
    /// midpoint... serves as the composition anchor point instead of
    /// bounding box center") — falls back to `SubjectCandidate.init`'s own
    /// bounding-box-center default otherwise.
    static func subjectCandidate(fromBodyPose observation: VNHumanBodyPoseObservation) -> SubjectCandidate? {
        guard let allPoints = try? observation.recognizedPoints(.all), !allPoints.isEmpty else { return nil }

        let confidentPoints = allPoints.values.filter { $0.confidence >= jointConfidenceFloor }
        guard !confidentPoints.isEmpty else { return nil }

        let xs = confidentPoints.map(\.location.x)
        let ys = confidentPoints.map(\.location.y)
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return nil }

        let rect = VisionCoordinateConversion.normRect(
            fromVisionBoundingBoxX: minX, y: minY, width: maxX - minX, height: maxY - minY
        )

        var anchor: NormPoint?
        if let leftEye = allPoints[.leftEye], leftEye.confidence >= jointConfidenceFloor,
           let rightEye = allPoints[.rightEye], rightEye.confidence >= jointConfidenceFloor {
            let midX = (leftEye.location.x + rightEye.location.x) / 2.0
            let midY = (leftEye.location.y + rightEye.location.y) / 2.0
            anchor = VisionCoordinateConversion.normPoint(fromVisionPointX: midX, y: midY)
        }

        return SubjectCandidate(
            rect: rect,
            category: .person,
            confidence: Double(observation.confidence),
            anchor: anchor
        )
    }

    /// Saliency-derived candidates — the fallback subject signal
    /// (`docs/ARCHITECTURE.md` §4.2's documented pairing), consulted only
    /// when no person was detected (see call sites).
    static func subjectCandidates(fromSaliency observation: VNSaliencyImageObservation) -> [SubjectCandidate] {
        (observation.salientObjects ?? []).map { rectObservation in
            let box = rectObservation.boundingBox
            let rect = VisionCoordinateConversion.normRect(
                fromVisionBoundingBoxX: box.minX, y: box.minY, width: box.width, height: box.height
            )
            return SubjectCandidate(
                rect: rect,
                category: .object,
                confidence: Double(rectObservation.confidence)
            )
        }
    }

    /// Runs both requests against an already-constructed
    /// `VNImageRequestHandler` and returns the combined candidate list —
    /// person detections first, falling back to saliency only when none
    /// were found (`PRODUCT_SPEC.md` §1.2.2 weights Person 1.0 vs. Object
    /// 0.4, so a person candidate always wins arbitration anyway; skipping
    /// saliency when one already exists saves latency rather than
    /// computing a result nothing would use).
    static func detectSubjectCandidates(using handler: VNImageRequestHandler) throws -> [SubjectCandidate] {
        let bodyPoseRequest = VNDetectHumanBodyPoseRequest()
        let saliencyRequest = VNGenerateAttentionBasedSaliencyImageRequest()
        try handler.perform([bodyPoseRequest, saliencyRequest])

        let bodyObservations = bodyPoseRequest.results ?? []
        var candidates = bodyObservations.compactMap(Self.subjectCandidate(fromBodyPose:))

        if candidates.isEmpty {
            let saliencyObservations = saliencyRequest.results ?? []
            candidates = saliencyObservations.flatMap(Self.subjectCandidates(fromSaliency:))
        }

        return candidates
    }
}
