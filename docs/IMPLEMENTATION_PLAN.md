# Implementation Roadmap & Milestone Plan — Camsthetics (iOS)

**Document Version:** 1.0  
**Status:** Authoritative Foundation  
**Companion Documents:** `PRD.md`, `PRODUCT_SPEC.md`, `ARCHITECTURE.md`, `TECH_STACK.md`

---

## 1. Implementation Philosophy & Dependency Strategy

The implementation is structured **strictly from foundation to presentation**, ensuring that each layer is fully unit-tested and verified before dependent subsystems are built.

```
Phase 1: Pure Swift Core Engine ──► (Zero platform deps; 100% unit-tested)
           │
           ▼
Phase 2.0: Device Capture Proof of Concept ──► [HARD GATE: physical iPhone only]
           │
           ▼
Phase 2: Camera & Motion Service ──► (AVFoundation 60fps & CoreMotion 100Hz)
           │
           ▼
Phase 3: Apple Vision Service ──► (Pose & Saliency inference)
           │
           ▼
Phase 4: Reference Ingest & Storage ──► (Share Sheet, Link Resolver, SwiftData)
           │
           ▼
Phase 5: Live Coaching Viewfinder ──► (SwiftUI HUD, Ghost Frame, Hysteresis Loop)
           │
           ▼
Phase 6: High-Res Capture & Review ──► (PhotoKit, Drag-to-Compare, History)
           │
           ▼
Phase 7: Haptics, Accessibility & Polish ──► (CoreHaptics, VoiceOver, App Store prep)
```

---

## 2. Milestone Phases

### Phase 1: Core Coaching Engine & Domain Models
* **Objective:** Build the pure Swift domain engine that models composition geometry, aspect normalization, delta math, anti-flicker hysteresis, and match scoring.
* **Dependencies:** None (Pure Swift standard library).
* **Deliverables:**
  * `NormPoint`, `NormRect`, `CompositionParams`, `CompositionDelta`, `CoachingInstruction`.
  * `AspectNormalizer` (center-crop coordinate transformer).
  * `SobelEdgeTiltEstimator` (pure Swift image gradient orientation analyzer).
  * `DeltaEngine` (5D geometric diffing).
  * `HysteresisFilter` (dual-thresholds, sample counting, dwell timers).
  * `GaussianMatchScorer` (monotonic 0–100 scoring with tier caps).
* **Validation & Tests:**
  * Unit test suite for aspect normalization across extreme aspect ratios ($1:3$, $3:1$, $4:5$, $16:9$).
  * 20+ case Sign-Error Regression Suite (hand-verified directional instructions).
  * Property-based tests for score monotonicity (reducing error never lowers score).
* **Exit Criterion:** 100% unit test pass rate executing in $<100\text{ms}$ on macOS.

---

### Phase 2.0: Physical-Device Capture Proof of Concept (Hard Gate)
* **Objective:** Prove the end-to-end camera reality on a physical iPhone **before** any camera abstraction is designed. This phase exists to discover what the hardware and OS actually do, not to produce architecture.
* **Implementation constraint (mandatory):** **Do not immediately build a large camera abstraction.** No `CameraService` / `VisionService` / `MotionService` architecture is written until this proof passes. No placeholder camera abstractions may be added to signal progress.
* **Dependencies:** Phase 1 engine (already complete and unit-tested).
* **Proof Checklist — all ten must demonstrably pass on a physical device:**
  1. `AVCaptureSession` successfully receives camera input.
  2. Live preview works.
  3. Analysis frames can be obtained **independently** of the preview.
  4. Vision can process an analysis representation.
  5. CoreMotion data can be obtained **independently**.
  6. Native photo capture works.
  7. **The saved photo comes from the native photo capture path** (not preview, not analysis, not a converted buffer).
  8. **The analysis pipeline does not degrade the captured photo** — toggling analysis on/off produces no change in captured dimensions, format, colour space, or metadata (`PRODUCT_SPEC.md` FIDELITY-02).
  9. The physical iPhone can build/install/run through the macOS development environment.
  10. The composition engine receives correctly normalized inputs (`CompositionParams` referenced to capture geometry — FIDELITY-10).
* **Device & Toolchain Requirement:** Physical devices only — **iPhone 14** and **iPhone 16** where available. Workflow: **Windows host → macOS VM → Xcode → physical iPhone over USB passthrough**. **No Simulator-based camera testing is introduced at any point in this plan** (`DECISIONS.md` ADR-012).
* **Findings to record (these become the inputs to Phase 2's design):**
  * Supported photo dimensions, codecs, colour spaces, and HDR capabilities per validation device (queried at runtime, not assumed).
  * Measured preview-vs-capture field-of-view, crop, and orientation relationship, including front camera and stabilization crop.
  * Which iOS 17+ capture APIs express the `PRODUCT_SPEC.md` §1.5 maximum-resolution intent on each device (`DECISIONS.md` ADR-010).
* **Exit Criterion:** All ten checks demonstrated on at least one physical device (both where available), with findings written up. **Only after this proof passes** may the full `CameraService` / `VisionService` / `MotionService` architecture be implemented.

---

### Phase 2: Hardware Services — Camera & Motion
* **Objective:** Establish the low-level AVFoundation video capture session and CoreMotion gravity tracking.
* **Dependencies:** **Phase 2.0 proof passed** (hard gate); Phase 1 models.
* **Deliverables:**
  * `CameraService` actor managing `AVCaptureSession`, lens selection (`.ultrawide`, `.wide`, `.telephoto`), and tap-to-focus/exposure.
  * **Three separately configured outputs on the shared session** — `AVCapturePhotoOutput` (capture), `AVCaptureVideoDataOutput` (analysis), `AVCaptureVideoPreviewLayer` (preview) — with the pipeline boundaries of `ARCHITECTURE.md` §4.4 enforced in the module layout.
  * Runtime capability discovery for capture configuration (supported photo dimensions, codecs, colour space, HDR) — no hard-coded device assumptions (`DECISIONS.md` ADR-010).
  * Documented camera/lens selection mapping for supported device generations (`DECISIONS.md` ADR-011).
  * `MotionService` streaming calibrated roll and pitch at $100\text{Hz}$ with low-pass filtering.
  * SwiftUI `CameraPreviewView` hosting `AVCaptureVideoPreviewLayer`.
* **Validation & Tests:**
  * Verify 60fps video stream delivery without memory leaks or dropped frames.
  * Verify gravity roll calculation matches physical phone rotation within $\pm 0.5^\circ$.
  * **Fidelity invariant:** changing analysis resolution, throttle rate, or pixel format produces zero change in captured photo dimensions, format, colour space, or metadata (FIDELITY-02).
  * **Preview/capture consistency:** measured preview aspect/FOV/crop/orientation vs. captured image, front and back cameras (FIDELITY-10).
* **Exit Criterion:** Viewfinder displays smooth 60fps feed with live spirit level line snapping in $<5\text{ms}$, with the fidelity invariant and preview/capture consistency measurements recorded.

---

### Phase 3: On-Device Vision & ML Integration
* **Objective:** Integrate Apple Vision for real-time subject detection, eye-line anchor extraction, and target feature extraction.
* **Dependencies:** Phase 1 & 2.
* **Deliverables:**
  * `VisionService` actor executing `VNDetectHumanBodyPoseRequest` and `VNGenerateAttentionBasedSaliencyImageRequest`.
  * Non-blocking frame throttle ($10\text{Hz}$) with atomic backpressure gate.
  * `TargetExtractor` extracting target `CompositionParams` from still images in $<500\text{ms}$.
* **Validation & Tests:**
  * Measure inference latency on device ($\le 25\text{ms}$ per frame on A14+ Bionic).
  * Verify primary subject selection stability and sticky tracking under passer-by distraction.
* **Exit Criterion:** Live frame features stream into the coordinator at sustained $10\text{Hz}$ with zero UI lag.

---

### Phase 4: Reference Ingestion, Share Extension & Persistence
* **Objective:** Implement all reference input channels and local cache persistence.
* **Dependencies:** Phase 1 & 3.
* **Deliverables:**
  * `LinkResolverService` resolving Pinterest oEmbed URLs and OpenGraph streaming head parser.
  * iOS Share Sheet Extension for Safari and Pinterest.
  * `PhotosPicker` integration and built-in Curated Aesthetic Starter Pack.
  * SwiftData / Local repository for cached targets and session records.
* **Validation & Tests:**
  * MockWebServer tests for URL normalization and parsing error resilience.
  * Ingesting 20 pins in sequence caches images without memory spikes.
* **Exit Criterion:** Pasting a URL or sharing from Pinterest loads the target into the app in $<2.5\text{s}$.

---

### Phase 5: Live Coaching Viewfinder & SwiftUI HUD
* **Objective:** Assemble the complete real-time coaching loop connecting Camera, Vision, Motion, Engine, and the SwiftUI HUD.
* **Dependencies:** Phases 1–4.
* **Deliverables:**
  * `CoachingSessionCoordinator` orchestrating the live state machine.
  * SwiftUI Viewfinder HUD: Floating instruction pill, Ghost bounding frame, Lens switcher, Match score badge.
  * Confidence tier state transitions (`FULL`, `PARTIAL`, `MINIMAL`).
* **Validation & Tests:**
  * End-to-end trace replay tests verifying instruction flip rate $\le 4/\text{min}$ while holding steady.
  * Viewfinder UI maintains ProMotion $60\text{–}120\text{fps}$ rendering while inference runs at $10\text{Hz}$.
* **Exit Criterion:** User can frame a live shot against an ingested target and follow instructions to lock $\ge 85\%$ match score.

---

### Phase 6: High-Res Capture, Interactive Review & History
* **Objective:** Deliver pristine master capture execution, interactive drag-to-compare review, and local session history.
* **Dependencies:** Phase 5.
* **Deliverables:**
  * `AVCapturePhotoOutput` capture controller with Smart HDR / Deep Fusion preservation.
  * Auto-capture countdown gate (fires when $\ge 85\%$ is held for $600\text{ms}$).
  * Interactive Drag-to-Compare review view with split wipe divider.
  * Non-destructive 1-tap Auto-Straighten / Auto-Crop.
  * Direct photo save to Apple Photos (`PhotoKit`) with complete EXIF.
  * Session History grid with 1-tap Re-Coach.
  * **Image-quality validation record** per validation device (`PRODUCT_SPEC.md` FIDELITY-11).
* **Validation & Tests:**
  * Verify captured JPEG/HEIC matches sensor maximum resolution with zero re-encoding.
  * Drag-to-compare wipe divider runs at $60\text{fps}$ interactive gesture speed.
  * **Image-Quality Regression Suite (physical devices only — iPhone 14 / iPhone 16 where available):** back-to-back comparison against the highest-quality appropriate Apple-native capture path, evaluating resolution, detail, sharpness, noise, dynamic range, highlight retention, shadow detail, colour, HDR behaviour, field of view, crop, orientation, stabilization, metadata, file format, file size, and capture latency.
  * Metadata diff vs. a native capture of the same scene (orientation, capture info, colour info, lens info; location only where authorized).
* **Exit Criterion:** Complete end-to-end shoot $\to$ review $\to$ save to Photos workflow functioning flawlessly, **and** the image-quality comparison record exists per device with every deviation either fixed or explicitly accepted with rationale. "Native-quality" is not claimed on the basis that images look acceptable (`DECISIONS.md` ADR-012).

---

### Phase 7: CoreHaptics, Accessibility & App Store Readiness
* **Objective:** Polish tactile feedback, accessibility compliance, thermal protection, and release configuration.
* **Dependencies:** Phases 1–6.
* **Deliverables:**
  * `HapticService` with custom CoreHaptics patterns and selection ticks.
  * VoiceOver live announcements and Dynamic Type layout safety.
  * Thermal state listener with dynamic analysis throttling ($10\text{Hz} \to 5\text{Hz}$).
  * Privacy manifests and App Store asset bundle.
* **Validation & Tests:**
  * Accessibility Audit with VoiceOver navigating end-to-end coaching session.
  * 10-minute continuous coaching thermal and battery test on physical iPhone.
* **Exit Criterion:** 100% criteria met across PRD, Product Spec, and Design System; ready for TestFlight / App Store submission.
