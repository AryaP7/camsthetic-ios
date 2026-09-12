import AVFoundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

// MARK: - Phase 2.0 — Capture Fidelity Proof Harness (THROWAWAY)
//
// This file exists to answer, empirically, on a physical iPhone
// (IMPLEMENTATION_PLAN.md Phase 2.0, hard gate; DECISIONS.md ADR-012 — no Simulator):
//
//   "Does an AVCaptureVideoDataOutput attached to the AVCaptureSession — actively
//    receiving frames (Trial A), attached but idle (Trial B), or entirely absent
//    (Trial C) — change anything about what AVCapturePhotoOutput captures?"
//
// This directly operationalizes Phase 2.0 checklist item 8 ("the analysis pipeline
// does not degrade the captured photo") and PRODUCT_SPEC.md FIDELITY-01/02's claim
// that analysis and capture are structurally independent pipelines.
//
// This is NOT production architecture:
//   - No CameraService / VisionService / MotionService abstraction.
//   - No protocols, no dependency injection, no persistence layer.
//   - Disposable: intended to be deleted once the findings are written up.
//
// Concurrency model: deliberately plain GCD, matching Apple's own AVFoundation
// sample-code pattern (e.g. AVCam) rather than a Swift-concurrency actor. All
// AVCaptureSession/output/device state is touched only from `harnessQueue`; the
// frame counter is touched only from `analysisQueue` (the sample-buffer delegate
// callback queue). `@Published` properties are only ever written on the main
// queue. This keeps the throwaway harness simple and matches how AVFoundation
// itself expects to be driven (a dedicated serial session queue), rather than
// forcing session configuration through @MainActor.
//
// Hard constraints this file honors:
//   - The final photo artifact is exactly AVCapturePhoto.fileDataRepresentation()'s
//     bytes, written to disk unmodified. No resize/re-encode/tone-map.
//   - The video sample-buffer delegate (Trial A) does nothing but count and discard
//     frames — no image processing of any kind.
//   - No RAW/ProRAW, Zero Shutter Lag, Responsive Capture, Fast Capture
//     Prioritization, Constant Color, or virtual-device constituent photo delivery
//     is enabled. Those are separate, later investigations.
//   - Every codec/dimension/color-space value is runtime-queried, never hard-coded.
//   - Artifacts go to the app's Documents directory, never to Photos.
//
// Deprecation note (verified against Apple's current documentation, not memory):
// AVCapturePhotoOutput.isHighResolutionCaptureEnabled and
// AVCapturePhotoSettings.isHighResolutionPhotoEnabled are deprecated as of iOS 16.
// This harness uses AVCapturePhotoOutput.maxPhotoDimensions /
// AVCaptureDevice.Format.supportedMaxPhotoDimensions instead, per ARCHITECTURE.md
// §4.4.4 and DECISIONS.md ADR-010.

enum CaptureFidelityTrial: String, CaseIterable, Identifiable, Codable {
    case a = "A"
    case b = "B"
    case c = "C"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .a: return "A — VideoDataOutput attached, delegate active (counts + discards frames)"
        case .b: return "B — VideoDataOutput attached, delegate detached"
        case .c: return "C — VideoDataOutput absent from the session"
        }
    }
}

enum CaptureFidelityError: LocalizedError {
    case cameraAccessDenied
    case noCameraDevice
    case cannotAddInput
    case cannotAddPhotoOutput
    case noSupportedPhotoDimensions

    var errorDescription: String? {
        switch self {
        case .cameraAccessDenied: return "Camera access was denied."
        case .noCameraDevice: return "No built-in wide-angle back camera is available on this device."
        case .cannotAddInput: return "AVCaptureSession refused the camera input."
        case .cannotAddPhotoOutput: return "AVCaptureSession refused the AVCapturePhotoOutput."
        case .noSupportedPhotoDimensions: return "activeFormat.supportedMaxPhotoDimensions was empty."
        }
    }
}

/// One in-flight capture's request-time context, snapshotted before
/// `capturePhoto(with:delegate:)` is called, so the completion delegate can compare
/// "what we asked for" against "what came back" without re-querying mutable state.
private struct CaptureContext {
    let trial: CaptureFidelityTrial
    let requestedSettings: AVCapturePhotoSettings
    let requestedCodec: String
    let requestedDimensions: CMVideoDimensions
    let frameCounterSnapshot: Int
    let requestedAt: CFAbsoluteTime
}

final class CaptureFidelityProofHarness: NSObject, ObservableObject {

    @Published private(set) var statusLines: [String] = []
    @Published private(set) var isBusy = false
    @Published private(set) var lastArtifactURLs: (photo: URL, json: URL)?

    // AVFoundation objects. Touched only from `harnessQueue`. Photo/video outputs
    // are recreated per trial so no configuration state leaks between trials.
    private let session = AVCaptureSession()
    private var device: AVCaptureDevice?
    private var photoOutput = AVCapturePhotoOutput()
    private var videoOutput: AVCaptureVideoDataOutput?
    private var activeCaptureContext: CaptureContext?

    // Serial queue for session configuration + capture orchestration (never main).
    private let harnessQueue = DispatchQueue(label: "com.camsthetics.captureFidelityProof.harness")
    // Serial queue used only as the AVCaptureVideoDataOutput sample-buffer delegate
    // callback queue. `frameCounter` is mutated only here.
    private let analysisQueue = DispatchQueue(label: "com.camsthetics.captureFidelityProof.analysis")
    private var frameCounter = 0

    private static let fileStampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    // MARK: - Public entry point (called from the main/UI thread)

    func runTrial(_ trial: CaptureFidelityTrial) {
        guard !isBusy else { return }
        isBusy = true
        log("— Trial \(trial.rawValue): \(trial.label) —")

        harnessQueue.async { [weak self] in
            guard let self else { return }
            do {
                try self.requestCameraAccessIfNeeded()
                try self.configureSession(for: trial)
                if !self.session.isRunning {
                    self.session.startRunning()
                }
                // Reconfiguring maxPhotoDimensions/outputs disrupts the render
                // pipeline momentarily (documented behavior of AVCapturePhotoOutput
                // configuration changes); let it settle before capturing.
                Thread.sleep(forTimeInterval: 0.35)

                self.analysisQueue.sync { self.frameCounter = 0 }
                if trial == .a {
                    // Let real analysis frames actually flow before capturing, so
                    // Trial A is genuinely "actively receiving frames" at the moment
                    // of capture, not just "configured".
                    Thread.sleep(forTimeInterval: 0.5)
                }

                self.capture(for: trial)
            } catch {
                self.log("Trial \(trial.rawValue) FAILED to configure: \(error.localizedDescription)")
                DispatchQueue.main.async { self.isBusy = false }
            }
        }
    }

    // MARK: - Permission (runs on harnessQueue)

    private func requestCameraAccessIfNeeded() throws {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return
        case .notDetermined:
            let semaphore = DispatchSemaphore(value: 0)
            var granted = false
            AVCaptureDevice.requestAccess(for: .video) { ok in
                granted = ok
                semaphore.signal()
            }
            semaphore.wait()
            if !granted { throw CaptureFidelityError.cameraAccessDenied }
        default:
            throw CaptureFidelityError.cameraAccessDenied
        }
    }

    // MARK: - Session configuration (runs on harnessQueue)

    private func ensureDeviceInputAdded() throws {
        guard session.inputs.isEmpty else { return }
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw CaptureFidelityError.noCameraDevice
        }
        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input) else { throw CaptureFidelityError.cannotAddInput }
        session.addInput(input)
        device = camera
    }

    /// Largest entry in `supportedMaxPhotoDimensions` for the given format, by pixel
    /// area. Never a hard-coded resolution — queried fresh every time this is called.
    private func largestSupportedDimensions(for format: AVCaptureDevice.Format) -> CMVideoDimensions? {
        format.supportedMaxPhotoDimensions.max { lhs, rhs in
            Int64(lhs.width) * Int64(lhs.height) < Int64(rhs.width) * Int64(rhs.height)
        }
    }

    private func configureSession(for trial: CaptureFidelityTrial) throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        if session.canSetSessionPreset(.photo) {
            session.sessionPreset = .photo
        }

        try ensureDeviceInputAdded()
        guard let device else { throw CaptureFidelityError.noCameraDevice }

        // Fresh outputs every trial — no state carried over.
        for output in session.outputs {
            session.removeOutput(output)
        }

        let newPhotoOutput = AVCapturePhotoOutput()
        guard session.canAddOutput(newPhotoOutput) else { throw CaptureFidelityError.cannotAddPhotoOutput }
        session.addOutput(newPhotoOutput)

        newPhotoOutput.maxPhotoQualityPrioritization = .quality
        guard let maxDimensions = largestSupportedDimensions(for: device.activeFormat) else {
            throw CaptureFidelityError.noSupportedPhotoDimensions
        }
        newPhotoOutput.maxPhotoDimensions = maxDimensions

        // Deliberately NOT enabled — see file header. Reading these back into the
        // JSON sidecar (query-only) is fine; setting them is not part of this proof.
        // (isVirtualDeviceConstituentPhotoDeliveryEnabled, isZeroShutterLagEnabled,
        //  isResponsiveCaptureEnabled, isFastCapturePrioritizationEnabled,
        //  isConstantColorEnabled, RAW — all left at their default/off state.)

        var newVideoOutput: AVCaptureVideoDataOutput?
        if trial != .c {
            let vdo = AVCaptureVideoDataOutput()
            vdo.alwaysDiscardsLateVideoFrames = true
            if session.canAddOutput(vdo) {
                session.addOutput(vdo)
            }
            switch trial {
            case .a:
                vdo.setSampleBufferDelegate(self, queue: analysisQueue)
            case .b:
                vdo.setSampleBufferDelegate(nil, queue: nil)
            case .c:
                break
            }
            newVideoOutput = vdo
        }

        photoOutput = newPhotoOutput
        videoOutput = newVideoOutput
    }

    // MARK: - Capture (runs on harnessQueue)

    /// Runtime-queried codec preference: HEVC/HEIF first (TECH_STACK.md §2.9,
    /// DECISIONS.md ADR-010). Never hard-codes JPEG — if HEVC isn't offered, this
    /// returns nil and `capture(for:)` lets AVCapturePhotoOutput resolve its own
    /// device-appropriate default, which is then recorded faithfully in the sidecar.
    private static func preferredCodec(among codecs: [AVVideoCodecType]) -> AVVideoCodecType? {
        codecs.contains(.hevc) ? .hevc : nil
    }

    private func capture(for trial: CaptureFidelityTrial) {
        let codecs = photoOutput.availablePhotoCodecTypes
        let codec = Self.preferredCodec(among: codecs)

        let settings: AVCapturePhotoSettings
        let requestedCodecDescription: String
        if let codec {
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: codec])
            requestedCodecDescription = codec.rawValue
        } else {
            settings = AVCapturePhotoSettings()
            requestedCodecDescription = "(none of the queried availablePhotoCodecTypes matched a preference; letting AVCapturePhotoOutput resolve its own default)"
        }
        settings.photoQualityPrioritization = .quality
        settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions

        let frameSnapshot = analysisQueue.sync { frameCounter }
        activeCaptureContext = CaptureContext(
            trial: trial,
            requestedSettings: settings,
            requestedCodec: requestedCodecDescription,
            requestedDimensions: settings.maxPhotoDimensions,
            frameCounterSnapshot: frameSnapshot,
            requestedAt: CFAbsoluteTimeGetCurrent()
        )

        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    // MARK: - Logging / status (safe to call from any queue)

    private func log(_ message: String) {
        print("[CaptureFidelityProof] \(message)")
        DispatchQueue.main.async { [weak self] in
            self?.statusLines.append(message)
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate (Trial A only)

extension CaptureFidelityProofHarness: AVCaptureVideoDataOutputSampleBufferDelegate {
    /// Absolutely no image processing here, per the proof's constraints: count the
    /// frame and let it be released. The sample buffer is never touched otherwise.
    /// Called on `analysisQueue` (the queue passed to `setSampleBufferDelegate`).
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        frameCounter += 1
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didDrop sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Informational only; not counted. Analysis backpressure (dropped frames)
        // is expected and permitted (PRODUCT_SPEC.md FIDELITY-02) and irrelevant to
        // whether the capture path is affected.
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CaptureFidelityProofHarness: AVCapturePhotoCaptureDelegate {
    /// Photo-capture delegate callbacks are not guaranteed to land on any
    /// particular queue, so the first thing every implementation here does is hop
    /// back onto `harnessQueue` before touching shared state.
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let completedAt = CFAbsoluteTimeGetCurrent()
        harnessQueue.async { [weak self] in
            guard let self, let context = self.activeCaptureContext else { return }
            self.finishCapture(photo: photo, error: error, context: context, completedAt: completedAt, output: output)
        }
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
        error: Error?
    ) {
        if let error {
            log("didFinishCaptureFor reported an error: \(error.localizedDescription)")
        }
    }

    // MARK: Completion (runs on harnessQueue)

    private func finishCapture(
        photo: AVCapturePhoto,
        error: Error?,
        context: CaptureContext,
        completedAt: CFAbsoluteTime,
        output: AVCapturePhotoOutput
    ) {
        defer { DispatchQueue.main.async { self.isBusy = false } }

        if let error {
            log("Trial \(context.trial.rawValue) capture error: \(error.localizedDescription)")
            return
        }

        // The ONLY source of the saved artifact: AVCapturePhoto.fileDataRepresentation().
        // Nothing here reconstructs an image from a pixel buffer, the preview layer,
        // or a screenshot.
        guard let data = photo.fileDataRepresentation() else {
            log("Trial \(context.trial.rawValue): fileDataRepresentation() returned nil — no artifact saved.")
            return
        }

        let latency = completedAt - context.requestedAt
        let resolved = photo.resolvedSettings
        // Read-only inspection of the exact bytes just captured — for the JSON
        // sidecar only. Does not modify, re-encode, resize, or tone-map the saved
        // file in any way.
        let introspection = ImageArtifactIntrospection(data: data)

        var notes: [String] = []
        let requestedDimsText = "\(context.requestedDimensions.width)x\(context.requestedDimensions.height)"
        let resolvedDimsText = "\(resolved.photoDimensions.width)x\(resolved.photoDimensions.height)"
        if requestedDimsText != resolvedDimsText {
            notes.append("Requested maxPhotoDimensions (\(requestedDimsText)) differs from resolved photoDimensions (\(resolvedDimsText)).")
        }
        if context.trial == .a && context.frameCounterSnapshot == 0 {
            notes.append("WARNING: Trial A's frame counter was 0 immediately before capture — the analysis pipeline may not actually have been receiving frames yet.")
        }
        if let uti = introspection.containerUTI {
            notes.append("Saved container UTI: \(uti).")
        }

        let sidecar = CaptureFidelitySidecar(
            trial: context.trial.rawValue,
            trialLabel: context.trial.label,
            timestampISO8601: ISO8601DateFormatter().string(from: Date()),
            captureLatencySeconds: latency,
            sessionPreset: session.sessionPreset.rawValue,
            device: DeviceInfo(device: device),
            activeFormat: FormatInfo(format: device?.activeFormat),
            activeColorSpace: FormatInfo.describe(device?.activeColorSpace),
            photoOutputConfiguration: PhotoOutputConfig(output: output),
            requestedPhotoSettings: RequestedSettingsInfo(
                uniqueID: context.requestedSettings.uniqueID,
                requestedCodec: context.requestedCodec,
                requestedMaxPhotoDimensions: requestedDimsText,
                photoQualityPrioritization: PhotoOutputConfig.describe(context.requestedSettings.photoQualityPrioritization)
            ),
            resolvedPhotoSettings: ResolvedSettingsInfo(resolved: resolved),
            capturedPhotoMetadata: AnyCodable(photo.metadata),
            fileByteCount: data.count,
            fileSHA256Hex: Self.sha256Hex(data),
            imageIntrospection: introspection,
            videoDataOutput: VideoOutputInfo(output: videoOutput, trial: context.trial),
            frameCounterAtCaptureTime: context.frameCounterSnapshot,
            notes: notes
        )

        do {
            let (photoURL, jsonURL) = try writeArtifacts(
                data: data, sidecar: sidecar, trial: context.trial, extension: introspection.preferredFileExtension
            )
            log("Trial \(context.trial.rawValue) saved: \(photoURL.lastPathComponent) (\(data.count) bytes) + \(jsonURL.lastPathComponent)")
            DispatchQueue.main.async { [weak self] in
                self?.lastArtifactURLs = (photoURL, jsonURL)
            }
        } catch {
            log("Trial \(context.trial.rawValue): failed to write artifacts: \(error.localizedDescription)")
        }
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func writeArtifacts(
        data: Data,
        sidecar: CaptureFidelitySidecar,
        trial: CaptureFidelityTrial,
        extension fileExtension: String
    ) throws -> (URL, URL) {
        let dir = try captureFidelityProofDirectory()
        let stamp = Self.fileStampFormatter.string(from: Date())
        let base = "trial-\(trial.rawValue)-\(stamp)"
        let photoURL = dir.appendingPathComponent("\(base).\(fileExtension)")
        let jsonURL = dir.appendingPathComponent("\(base).json")

        // Exact, unmodified bytes from AVCapturePhoto.fileDataRepresentation().
        try data.write(to: photoURL, options: .atomic)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(sidecar)
        try jsonData.write(to: jsonURL, options: .atomic)

        return (photoURL, jsonURL)
    }

    private func captureFidelityProofDirectory() throws -> URL {
        let docs = try FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let dir = docs.appendingPathComponent("CaptureFidelityProof", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
}
