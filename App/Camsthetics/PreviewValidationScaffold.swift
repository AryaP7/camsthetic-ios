import SwiftUI
import UIKit
import CamstheticsServices
import ImageIO
import CryptoKit

// MARK: - TEMPORARY — Phase 2.2 physical-device preview + lens validation scaffold
//
// This entire file is validation scaffolding, NOT production architecture.
// It exists solely to make the already-implemented, already-reviewed
// `CameraPreviewView` (CameraPreviewView.swift) and the new lens/zoom
// selection API on `CameraService` (`availableLensOptions()`,
// `selectLens(_:)`, `currentVideoZoomFactor`) reachable on a physical
// device so their behavior — framing, rotation, mirroring, session
// start/stop, interruption health overlay, and now optical lens
// switching — can be manually verified. It must be deleted, and its one
// wiring line in CamstheticsApp.swift reverted, once that manual
// validation is done.
//
// It adds nothing of its own to the capture, preview, or lens-selection
// pipelines: it owns exactly one `CameraService` (the existing concrete
// actor — no new session, no protocol abstraction), starts it, hosts the
// existing `CameraPreviewView` unmodified, and adds a row of lens buttons
// that call `CameraService.selectLens(_:)` directly. No Vision, Motion,
// analysis-frame delivery, or Photo Library code appears here.

struct PreviewValidationScaffold: View {
    @Environment(\.dismiss) private var dismiss

    // The one AVCaptureSession for this validation run — owned by
    // CameraService exactly as in production; nothing here creates a
    // second session.
    private let cameraService = CameraService()

    @State private var statusMessage = "Not started"
    @State private var isBusy = false
    @State private var lensOptions: [LensOption] = []
    @State private var currentZoomFactor: CGFloat = 1.0

    // TEMPORARY — manual capture-and-inspect, for Part 5 of the Phase 2
    // hardware checkpoint (a deliberately-framed human quality check, as
    // opposed to the unattended auto-battery's captures above). Decodes
    // the SAME unmodified bytes CameraService.capturePhoto() returns —
    // this view never re-encodes or re-derives them — purely so they can
    // be inspected on-screen (with pinch-zoom for fine detail) without
    // needing a file pull to a Mac.
    @State private var capturedImage: UIImage?
    @State private var capturedImageLabel: String = ""
    @State private var showCapturedImage = false

    // MARK: - TEMPORARY — Phase 2 hardware-validation checkpoint auto-battery
    //
    // Gated entirely behind an environment variable set only by the explicit
    // `devicectl device process launch -e '{"CAMSTHETICS_AUTO_VALIDATE":"1"}'`
    // hardware-validation invocation — a normal manual launch of this
    // scaffold is completely unaffected. Exists because this environment
    // has no configured UI-automation tool for a physical device (no tap,
    // no simulator-style snapshot), so the lens sweep / stop-start cycle /
    // production-path capture this checkpoint requires are driven
    // programmatically instead, with every step logged via `print()` so it
    // is visible in `devicectl device console` / `log stream` output.
    private var isAutoValidating: Bool {
        ProcessInfo.processInfo.environment["CAMSTHETICS_AUTO_VALIDATE"] == "1"
    }
    @State private var autoValidationStarted = false

    // TEMPORARY — continuous pinch-to-zoom, added in response to physical
    // testing (Phase 2 hardware checkpoint): the discrete lens buttons
    // above snap to specific optical levels via `selectLens(_:)` (ramped);
    // this gesture instead drives `CameraService.setZoomFactor(_:)`
    // directly, frame-by-frame, exactly like the native Camera app's
    // pinch gesture — same device, same already-available zoom range, no
    // digital level fabricated. `zoomGestureBaseFactor` is the RAW
    // zoomFactor the gesture started from, so `MagnificationGesture`'s
    // multiplicative `value` composes correctly.
    @State private var zoomGestureBaseFactor: CGFloat = 1.0
    /// ROOT-CAUSE FIX (confirmed via on-device sequence-tagged telemetry):
    /// `.onEnded` used to read `currentZoomFactor` for the next gesture's
    /// baseline — but `currentZoomFactor` was only written INSIDE the
    /// async `Task` each `.onChanged` spawns. `MagnificationGesture`'s
    /// `.onEnded` fires the instant fingers lift, on the same main actor,
    /// with no guarantee the last in-flight Task has resumed and written
    /// yet (it's suspended on an `await` into the `CameraService` actor).
    /// A quick lift-and-repinch could read a STALE value, corrupting the
    /// next gesture's baseline — confirmed on-device: telemetry showed a
    /// non-continuous jump (4.17 mid-snap → 2.69 on the very next gesture
    /// frame) exactly at a gesture boundary. `lastRequestedZoomFactor` is
    /// written SYNCHRONOUSLY inside `.onChanged` itself (no `await`
    /// involved), so `.onEnded` — which can only run after the same
    /// gesture's last `.onChanged` on the same actor — always sees the
    /// correct, up-to-date value.
    @State private var lastRequestedZoomFactor: CGFloat = 1.0
    /// Cancelled and replaced on every `.onChanged`, so a fast pinch never
    /// piles up multiple in-flight actor calls behind the latest one —
    /// each gesture frame supersedes the last rather than queuing.
    @State private var zoomTask: Task<Void, Never>?
    /// Cached once per session-start (not re-read every gesture frame) —
    /// see `CameraService.secondaryNativeResolutionZoomFactors`'s doc
    /// comment. Device-agnostic: empty on hardware/format that doesn't
    /// report any, which makes the snap below a pure no-op there.
    @State private var snapZoomFactors: [CGFloat] = []
    /// Tracks whether the gesture is currently sitting on a snap point,
    /// so haptic feedback fires once on entry rather than continuously
    /// while held there. A value-only snap (changing what's SENT to
    /// `setZoomFactor`) gives the finger no physical resistance — nothing
    /// slows the gesture down as it crosses the snap window, so without a
    /// discrete cue like this it's essentially imperceptible at normal
    /// pinch speed (confirmed on physical device: the snap was measured
    /// working — `secondaryNativeResolutionZoomFactors` correctly read as
    /// [4.0] on this unit — but wasn't felt until this was added).
    @State private var isSnappedToNativeResolution = false
    // MUST be @State, not a plain `let` — SwiftUI reconstructs this View
    // struct on every @State change (including every gesture-driven
    // `currentZoomFactor` update, i.e. continuously during the pinch
    // itself), so a plain stored property would be re-initialized nearly
    // every frame. A freshly-created, never-`prepare()`d
    // `UIImpactFeedbackGenerator` reliably produces NO physical tap —
    // confirmed on physical device (this was tried first and felt like
    // nothing). `@State`'s storage lives outside the struct's value
    // semantics, so this one instance survives across re-renders.
    @State private var snapHaptic = UIImpactFeedbackGenerator(style: .medium)

    // MARK: Tap-to-focus / tap-to-exposure state
    /// Where the reticle is drawn, in view coordinates. `nil` hides it.
    @State private var focusReticleViewPoint: CGPoint?
    /// Cancelled and replaced on each new tap so a rapid second tap
    /// doesn't get its reticle cleared early by the FIRST tap's pending
    /// auto-cancel — the same supersede-don't-queue discipline the zoom
    /// gesture uses.
    @State private var focusAutoCancelTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .bottom) {
            // The actual Phase 2.2 preview surface under test — unmodified.
            CameraPreviewView(cameraService: cameraService) { devicePoint, viewPoint in
                handleTapToFocus(devicePoint: devicePoint, viewPoint: viewPoint)
            }
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            let raw = zoomGestureBaseFactor * value
                            // Intelligent zoom snap (device-agnostic): if
                            // the gesture is already near a discovered
                            // secondary-native-resolution point for THIS
                            // device/format, land exactly on it rather
                            // than stopping just short — a no-op on
                            // hardware/format reporting none.
                            //
                            // tolerance=0.25 (not the default 0.15) —
                            // physical-device telemetry showed 0.15 was
                            // narrow enough to pass through unnoticed at
                            // normal pinch speed, while 0.5 (tried as a
                            // diagnostic) created an overly "sticky" ~1.0
                            // raw dwell zone. 0.25 is the settled
                            // production value; still a plain tuning
                            // constant, never a hard-coded per-device
                            // zoom value.
                            let target = LensSelection.snapToNativeResolution(
                                target: raw,
                                secondaryNativeResolutionZoomFactors: snapZoomFactors,
                                tolerance: 0.25
                            )
                            let didSnap = (target != raw)
                            if didSnap, !isSnappedToNativeResolution {
                                log("zoom snap engaged: raw=\(raw) -> target=\(target)")
                                snapHaptic.impactOccurred()
                            } else if !didSnap, isSnappedToNativeResolution {
                                // Re-arm the Taptic Engine as we leave the
                                // snap zone so the NEXT entry (e.g. the
                                // gesture wanders back over it) is
                                // low-latency and reliable, per Apple's
                                // documented prepare()/impactOccurred()
                                // pattern.
                                snapHaptic.prepare()
                            }
                            isSnappedToNativeResolution = didSnap
                            // Written SYNCHRONOUSLY, no `await` involved —
                            // this is what makes `.onEnded` below race-free.
                            // See `lastRequestedZoomFactor`'s doc comment.
                            lastRequestedZoomFactor = target
                            currentZoomFactor = target
                            // Cancel any still-in-flight request from an
                            // earlier gesture frame before issuing the
                            // latest one — under fast pinch input this
                            // stops requests piling up behind each other
                            // (each frame supersedes the last instead of
                            // queuing), matching "must not fight the
                            // user's pinch gesture."
                            zoomTask?.cancel()
                            zoomTask = Task {
                                try? await cameraService.setZoomFactor(target)
                            }
                        }
                        .onEnded { _ in
                            isSnappedToNativeResolution = false
                            zoomGestureBaseFactor = lastRequestedZoomFactor
                            Task {
                                statusMessage = "Zoom: \(await cameraService.displayLabel(forRawZoomFactor: currentZoomFactor))"
                            }
                        }
                )

            // Tap-to-focus reticle. Validation-only chrome (the polished
            // one is CamstheticsUI's FocusExposureReticle) — its job here
            // is to make the focus point visible on screen, including in
            // automated screenshots.
            if let point = focusReticleViewPoint {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.yellow, lineWidth: 1.5)
                    .frame(width: 70, height: 70)
                    .position(point)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("focusReticle")
                    .transition(.opacity)
            }

            VStack(spacing: 12) {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.6), in: Capsule())

                if !lensOptions.isEmpty {
                    // TEMPORARY validation-only lens row — runtime-derived
                    // from CameraService.availableLensOptions(), never
                    // hard-coded. Not the polished lens-selection UI.
                    HStack(spacing: 10) {
                        ForEach(lensOptions) { option in
                            Button(option.label) { Task { await selectLens(option) } }
                                .buttonStyle(.bordered)
                                .tint(isCurrent(option) ? .yellow : .white)
                                .disabled(isBusy)
                        }
                    }
                }

                HStack(spacing: 16) {
                    Button("Start") { Task { await startSession() } }
                        .disabled(isBusy)
                    Button("Stop") { Task { await stopSession() } }
                        .disabled(isBusy)
                    Button("📸 Capture") { Task { await captureForInspection() } }
                        .disabled(isBusy)
                    Button("Close") { dismiss() }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.bottom, 32)
        }
        .fullScreenCover(isPresented: $showCapturedImage) {
            if let capturedImage {
                CapturedPhotoInspectorView(image: capturedImage, label: capturedImageLabel) {
                    showCapturedImage = false
                }
            }
        }
        .task {
            // Auto-start on appear, purely for validation convenience —
            // Start/Stop above re-exercise the same start()/stop() path for
            // manual session-restart testing (checklist item D).
            await startSession()
        }
        .task {
            // Reactive, not one-shot: CameraService.lensOptionsUpdates()
            // re-derives lens options whenever the device's usable zoom
            // range (KVO-observable per Apple's docs) changes, which may
            // happen after start() returns rather than only at that
            // instant. If 0.5x is a timing/settling issue rather than a
            // discovery bug, this is where it would show up.
            for await options in await cameraService.lensOptionsUpdates() {
                lensOptions = options
                if isAutoValidating, !autoValidationStarted, !options.isEmpty {
                    autoValidationStarted = true
                    Task { await runAutoValidationBattery() }
                }
            }
        }
        .task {
            // Diagnostic-only: log every session-health transition so
            // start/stop/interruption/recovery behavior is visible in the
            // device console even when no one is watching the screen live.
            for await health in await cameraService.healthUpdates() {
                log("health -> \(health)")
            }
        }
    }

    /// Tap-to-focus/expose. The device point arrives already converted by
    /// `CameraPreviewSurface` (which owns the layer geometry); this only
    /// forwards it and drives the reticle + `PRODUCT_SPEC.md` §1.5's
    /// 3-second auto-cancel back to continuous AF/AE.
    private func handleTapToFocus(devicePoint: CGPoint, viewPoint: CGPoint) {
        focusReticleViewPoint = viewPoint
        focusAutoCancelTask?.cancel()

        focusAutoCancelTask = Task {
            do {
                try await cameraService.focusAndExpose(atDevicePoint: devicePoint)
                statusMessage = String(
                    format: "Focus @ %.2f,%.2f", devicePoint.x, devicePoint.y
                )
            } catch {
                statusMessage = "Focus failed: \(error.localizedDescription)"
                return
            }

            let nanoseconds = UInt64(CameraService.focusExposureAutoCancelSeconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            // A newer tap supersedes this one — bail without clearing its
            // reticle or resetting the focus it just set.
            guard !Task.isCancelled else { return }

            try? await cameraService.resumeContinuousFocusAndExposure()
            focusReticleViewPoint = nil
            statusMessage = "Focus: continuous"
        }
    }

    private func isCurrent(_ option: LensOption) -> Bool {
        abs(option.zoomFactor - currentZoomFactor) < 0.05
    }

    private func startSession() async {
        guard !isBusy else { return }
        isBusy = true
        do {
            try await cameraService.start()
            statusMessage = "Running"
            currentZoomFactor = await cameraService.currentVideoZoomFactor
            zoomGestureBaseFactor = currentZoomFactor
            lastRequestedZoomFactor = currentZoomFactor
            snapZoomFactors = await cameraService.secondaryNativeResolutionZoomFactors
            log("intelligent zoom snap points (raw): \(snapZoomFactors)")
            // Prime the Taptic Engine ahead of any gesture so the first
            // snap of the session is low-latency and reliable, not just
            // subsequent ones.
            snapHaptic.prepare()
        } catch {
            statusMessage = "Start failed: \(error.localizedDescription)"
        }
        isBusy = false
    }

    private func stopSession() async {
        guard !isBusy else { return }
        isBusy = true
        await cameraService.stop()
        statusMessage = "Stopped"
        isBusy = false
    }

    private func selectLens(_ option: LensOption) async {
        do {
            try await cameraService.selectLens(option)
            statusMessage = "Lens: \(option.label)"
            currentZoomFactor = option.zoomFactor
            zoomGestureBaseFactor = option.zoomFactor
            lastRequestedZoomFactor = option.zoomFactor
        } catch {
            statusMessage = "Lens select failed: \(error.localizedDescription)"
        }
    }

    /// Captures one photo through the exact production
    /// `CameraService.capturePhoto()` path (same as the real app will use)
    /// and decodes the returned bytes — unmodified, no resize/re-encode —
    /// straight into a `UIImage` for on-screen inspection at the currently
    /// selected lens. This is the human-in-the-loop counterpart to
    /// `captureValidationPhoto(index:)` above: deliberate framing +
    /// subjective judgment, not an unattended battery.
    private func captureForInspection() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let artifact = try await cameraService.capturePhoto()
            guard let image = UIImage(data: artifact.data) else {
                statusMessage = "Capture decode failed"
                return
            }
            let displayLabel = await cameraService.displayLabel(forRawZoomFactor: currentZoomFactor)
            // Cross-check against EXIF LensModel — independent confirmation
            // (not just inference from topology data) of which physical
            // lens this capture actually came through, using the exact
            // same bytes fileDataRepresentation() returned.
            let lensModel = Self.exifLensModel(from: artifact.data) ?? "unknown"
            // Persisted (unlike the auto-battery's captures, these are
            // deliberately human-framed) so a specific reported issue —
            // e.g. the TV/flare comparison — can be pulled and inspected
            // afterward, not just eyeballed once on-device and discarded.
            var savedName = "unsaved"
            do {
                let introspection = ImageArtifactIntrospection(data: artifact.data)
                let dir = try captureDirectory()
                let stamp = Self.stampFormatter.string(from: Date())
                let url = dir.appendingPathComponent("manual-\(stamp).\(introspection.preferredFileExtension)")
                try artifact.data.write(to: url, options: .atomic)
                savedName = url.lastPathComponent
            } catch {
                log("capture-for-inspection: save failed: \(error.localizedDescription)")
            }
            log("capture-for-inspection: displayLabel=\(displayLabel) rawZoomFactor=\(currentZoomFactor) EXIF LensModel=\(lensModel) saved=\(savedName)")
            capturedImage = image
            capturedImageLabel = "\(displayLabel) (\(lensModel)) — \(Int(image.size.width))×\(Int(image.size.height))"
            showCapturedImage = true
            statusMessage = "Captured at \(displayLabel) → \(savedName)"
        } catch {
            statusMessage = "Capture failed: \(error.localizedDescription)"
        }
    }

    // MARK: - TEMPORARY — auto-validation battery (see isAutoValidating above)

    private func log(_ message: String) {
        // Console-visible marker so every line from this battery is easy to
        // grep out of `devicectl device console` output.
        print("[HardwareValidation] \(message)")
    }

    private func runAutoValidationBattery() async {
        log("BEGIN — \(lensOptions.count) lens option(s): \(lensOptions.map(\.label).joined(separator: ", "))")

        // Diagnostic-only: test whether the lens-option range is merely
        // slow to "settle" after startRunning() (CameraService's own KVO
        // subscription comment theorizes this) rather than a stable
        // characteristic — re-derive after a real multi-second wait and log
        // whether it changed. Does not affect behavior either way.
        try? await Task.sleep(nanoseconds: 4_000_000_000)
        let settledOptions = await cameraService.availableLensOptions()
        log("settle-check after 4s: \(settledOptions.map(\.label).joined(separator: ", ")) (was: \(lensOptions.map(\.label).joined(separator: ", ")))")

        // Step 3/4 — sweep every exposed lens forward then backward,
        // timing each ramp so smoothness/duration is measurable from logs
        // rather than only felt.
        for option in lensOptions {
            await timedSelectLens(option)
            try? await Task.sleep(nanoseconds: 900_000_000)
        }
        for option in lensOptions.reversed() {
            await timedSelectLens(option)
            try? await Task.sleep(nanoseconds: 900_000_000)
        }

        // Step 6 — stop/start cycle (repeat once for a bit more signal).
        for cycle in 1...2 {
            log("stop/start cycle \(cycle) — stopping")
            await stopSession()
            try? await Task.sleep(nanoseconds: 500_000_000)
            log("stop/start cycle \(cycle) — starting")
            await startSession()
            try? await Task.sleep(nanoseconds: 500_000_000)
            log("stop/start cycle \(cycle) done — status=\(statusMessage)")
        }

        // Step 7 — capture representative photos through the SAME
        // production CameraService.capturePhoto() path
        // (AVCapturePhotoOutput.fileDataRepresentation(), unmodified) with
        // isResponsiveCaptureEnabled now on, at 1x where available (closest
        // match to the Phase 2.0 baseline's single-wide-camera framing).
        if let oneX = lensOptions.min(by: { abs($0.zoomFactor - 1.0) < abs($1.zoomFactor - 1.0) }) {
            await selectLens(oneX)
            try? await Task.sleep(nanoseconds: 600_000_000)
        }
        for index in 1...3 {
            await captureValidationPhoto(index: index)
            try? await Task.sleep(nanoseconds: 700_000_000)
        }

        log("COMPLETE")
    }

    /// Selects one lens option and samples `currentVideoZoomFactor` every
    /// ~60ms until it settles near the target (or a 2s cap), logging the
    /// full trajectory — this is what turns "does the ramp feel smooth"
    /// into inspectable, timestamped numbers.
    private func timedSelectLens(_ option: LensOption) async {
        let before = await cameraService.currentVideoZoomFactor
        let start = Date()
        do {
            try await cameraService.selectLens(option)
        } catch {
            log("lens -> \(option.label) FAILED: \(error.localizedDescription)")
            return
        }
        var trajectory: [String] = []
        for _ in 0..<34 { // ~2s cap at 60ms polling
            try? await Task.sleep(nanoseconds: 60_000_000)
            let z = await cameraService.currentVideoZoomFactor
            let elapsedMs = Date().timeIntervalSince(start) * 1000
            trajectory.append(String(format: "%.0fms:%.3f", elapsedMs, z))
            if abs(z - option.zoomFactor) < 0.02 { break }
        }
        let totalMs = Date().timeIntervalSince(start) * 1000
        currentZoomFactor = option.zoomFactor
        statusMessage = "Lens: \(option.label)"
        log("lens -> \(option.label) (target \(option.zoomFactor)) before=\(before) totalMs=\(String(format: "%.0f", totalMs)) trajectory=[\(trajectory.joined(separator: ", "))]")
    }

    /// Captures one photo through the real production path and writes the
    /// exact, unmodified bytes to Documents/HardwareValidationCapture/,
    /// alongside a same-methodology ImageIO introspection line in the
    /// console log (dimensions/UTI/SHA-256) — pulled off-device afterward
    /// for full comparison against the Phase 2.0 baseline
    /// (docs/PHASE2_CAPTURE_PROOF.md).
    private func captureValidationPhoto(index: Int) async {
        do {
            let artifact = try await cameraService.capturePhoto()
            let introspection = ImageArtifactIntrospection(data: artifact.data)
            let dir = try captureDirectory()
            let stamp = Self.stampFormatter.string(from: Date())
            let base = "hwval-\(stamp)-\(index)"
            let url = dir.appendingPathComponent("\(base).\(introspection.preferredFileExtension)")
            try artifact.data.write(to: url, options: .atomic)
            let sha = SHA256.hash(data: artifact.data).map { String(format: "%02x", $0) }.joined()
            log("capture[\(index)] bytes=\(artifact.data.count) dims=\(introspection.pixelWidth ?? -1)x\(introspection.pixelHeight ?? -1) uti=\(introspection.containerUTI ?? "?") bitDepth=\(introspection.bitDepth ?? -1) colorModel=\(introspection.colorModel ?? "?") icc=\(introspection.iccProfileName ?? "?") gainMap=\(introspection.hasHDRGainMapAuxiliary) sha256=\(sha) file=\(url.lastPathComponent)")
        } catch {
            log("capture[\(index)] FAILED: \(error.localizedDescription)")
        }
    }

    /// Read-only EXIF inspection of the exact bytes just captured — never
    /// modifies/re-encodes anything. Used only to independently confirm
    /// which physical constituent lens a capture actually came through
    /// (cross-checking the topology-derived inference the label fix in
    /// `LensSelection.options` relies on), same spirit as
    /// `CaptureFidelityProof`'s `ImageArtifactIntrospection`.
    private static func exifLensModel(from data: Data) -> String? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        else { return nil }
        return exif[kCGImagePropertyExifLensModel] as? String
    }

    private func captureDirectory() throws -> URL {
        let docs = try FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let dir = docs.appendingPathComponent("HardwareValidationCapture", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
}

// `CapturedPhotoInspectorView` moved to
// `App/Camsthetics/CameraScreen/CapturedPhotoInspectorView.swift` — shared
// with `CameraScreen` rather than duplicated (same App target, so no
// import needed).
