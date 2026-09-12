import SwiftUI
import CoreMedia
import CamstheticsServices
import CamstheticsEngine

// MARK: - TEMPORARY — Phase 3 on-device smoke test for VisionService
//
// NOT production architecture — exists purely to answer, on a physical
// device, the two questions `VisionService.swift`/`TargetExtractor.swift`
// flagged as unverified assumptions rather than asserted fact:
//   1. Is `.right` actually the correct `CGImagePropertyOrientation` for
//      `CameraService`'s (unrotated) analysis buffer? A person standing
//      upright should show an upright, right-side-up bounding box overlay
//      here — if it's sideways or upside down, `.right` is wrong.
//   2. What is the real per-frame latency from analysis-frame capture to
//      Vision observation delivery, against the ≤25ms/frame budget
//      (`docs/IMPLEMENTATION_PLAN.md` Phase 3 exit criterion)?
//
// Owns its own `CameraService` + `VisionService` (never the production
// `CameraViewModel`'s instances) — same reasoning
// `PreviewValidationScaffold.swift` documents for itself: an isolated,
// disposable harness, not a second production wiring path. Delete this
// whole folder and its one entry point in `CamstheticsApp.swift` once
// Phase 3's on-device verification is recorded.
struct VisionSmokeTestView: View {
    @State private var cameraService = CameraService()
    @State private var visionService = VisionService()

    @State private var candidateCount = 0
    @State private var topCandidate: SubjectCandidate?
    @State private var latencyMs: Double = 0
    @State private var latencySamples: [Double] = []
    @State private var frameCount = 0

    var body: some View {
        ZStack {
            CameraPreviewView(cameraService: cameraService)

            if let rect = topCandidate?.rect {
                // Visual ground truth for the orientation question above —
                // GeometryReader gives screen bounds to map NormRect
                // (top-left origin, y-down — already flipped from Vision's
                // convention by `VisionCoordinateConversion`) onto.
                GeometryReader { proxy in
                    Rectangle()
                        .stroke(Color.yellow, lineWidth: 2)
                        .frame(width: rect.width * proxy.size.width, height: rect.height * proxy.size.height)
                        .position(
                            x: rect.midX * proxy.size.width,
                            y: rect.midY * proxy.size.height
                        )
                }
            }

            VStack {
                Text(statusLine)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(.black.opacity(0.6))
                    .accessibilityIdentifier("visionSmokeTestStatus")
                Spacer()
            }
        }
        .ignoresSafeArea()
        .task {
            guard await cameraService.requestAuthorizationIfNeeded() else { return }
            try? await cameraService.start()

            let frames = await cameraService.analysisFrameUpdates()
            async let consuming: () = visionService.consume(frames)
            async let observing: () = observeVisionOutput()
            _ = await (consuming, observing)
        }
        .onDisappear {
            Task { await cameraService.stop() }
        }
    }

    private var statusLine: String {
        let avg = latencySamples.isEmpty ? 0 : latencySamples.reduce(0, +) / Double(latencySamples.count)
        let candidateSummary = topCandidate.map {
            "category=\($0.category.rawValue) conf=\(String(format: "%.2f", $0.confidence))"
            + " rect=(\(String(format: "%.2f", $0.rect.x)),\(String(format: "%.2f", $0.rect.y)),"
            + "\(String(format: "%.2f", $0.rect.width))x\(String(format: "%.2f", $0.rect.height)))"
            + " anchor=(\(String(format: "%.2f", $0.anchor?.x ?? -1)),\(String(format: "%.2f", $0.anchor?.y ?? -1)))"
        } ?? "none"
        return "frames=\(frameCount)|candidates=\(candidateCount)|\(candidateSummary)"
            + "|latencyMs=\(String(format: "%.1f", latencyMs))|avgLatencyMs=\(String(format: "%.1f", avg))"
    }

    private func observeVisionOutput() async {
        for await observation in await visionService.observationUpdates() {
            frameCount += 1
            candidateCount = observation.candidates.count
            topCandidate = observation.candidates.max {
                SubjectSelector.scoreCandidate($0) < SubjectSelector.scoreCandidate($1)
            }

            // Latency = wall-clock-now minus this frame's capture
            // timestamp, both in the host time clock domain
            // (`CMSampleBufferGetPresentationTimeStamp`'s documented
            // default domain for camera capture) — includes the 10Hz
            // throttle/backpressure gate's own delay, not purely Vision
            // inference time, but that total is the number that actually
            // matters against the ≤25ms/frame budget end-to-end.
            let now = CMClockGetTime(CMClockGetHostTimeClock())
            latencyMs = CMTimeGetSeconds(CMTimeSubtract(now, observation.timestamp)) * 1000
            latencySamples.append(latencyMs)
            if latencySamples.count > 200 { latencySamples.removeFirst() }

            // TEMPORARY — console-visible readout (this whole harness is
            // throwaway) so results can be read via `devicectl device
            // process launch --console` without needing UI automation.
            if frameCount % 10 == 0 {
                print("[VisionSmokeTest] \(statusLine)")
            }
        }
    }
}
