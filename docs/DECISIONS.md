# Architecture & Product Decision Record (ADR) — Camsthetics (iOS)

**Document Version:** 1.0  
**Status:** Authoritative Foundation  
**Companion Documents:** `PRD.md`, `PRODUCT_SPEC.md`, `ARCHITECTURE.md`, `TECH_STACK.md`, `DESIGN_SYSTEM.md`, `IMPLEMENTATION_PLAN.md`

---

## Decision Index

| ID | Title | Status | Scope |
|---|---|---|---|
| **ADR-001** | Pure Swift Domain Engine Isolation | **Accepted** | Architecture |
| **ADR-002** | Zero Third-Party Dependencies for v1.0 | **Accepted** | Technology |
| **ADR-003** | Share Sheet & No-Auth URL Ingest for v1.0 | **Accepted** | Product / Scope |
| **ADR-004** | Apple Vision Framework for ML & Saliency | **Accepted** | Technology |
| **ADR-005** | Native AVFoundation over 3rd-Party Camera Wrappers | **Accepted** | Technology |
| **ADR-006** | Decoupled ML Inference (8–15Hz) from Viewfinder HUD (60/120Hz) | **Accepted** | Architecture / UX |
| **ADR-007** | Strict One-Handed Ergonomics (Bottom 30% Thumb Deck) | **Accepted** | Design |
| **ADR-008** | Non-Destructive Master Capture via PhotoKit | **Accepted** | Technology |
| **ADR-009** | Image Fidelity & Analysis/Preview/Capture Pipeline Separation | **Accepted** | Architecture / Product |
| **ADR-010** | Runtime-Queried Native Photo Format, Colour & Dynamic Range | **Accepted** | Technology |
| **ADR-011** | Deliberate Camera & Lens Selection (No Silent Switching) | **Accepted** | Architecture / UX |
| **ADR-012** | Device-First Image-Quality Validation (No Simulator) | **Accepted** | Process / Quality |
| **ADR-013** | Phase 2.0 Capture Fidelity Proof — VideoDataOutput State Has No Effect on Captured Photo | **Accepted** | Empirical Finding / Architecture |
| **ADR-014** | Camera Quality Philosophy — Apple's Pipeline as Baseline, Not Ceiling | **Accepted** | Product / Future Scope |

---

## Detailed Records

### ADR-001: Pure Swift Domain Engine Isolation
* **Status:** Accepted
* **Context:** The core coaching algorithms (aspect normalization, delta calculation, hysteresis, instruction mapping, and match scoring) are the heart of the product. Blurring them with UI (SwiftUI) or camera frameworks (AVFoundation) prevents fast automated testing.
* **Options:**
  1. Embed math directly within SwiftUI ViewModels / ViewControllers.
  2. Isolate core coaching into a pure Swift module with zero Apple platform framework imports.
* **Chosen Approach:** **Option 2 (Pure Swift Module).**
* **Reason:** Allows 100% of the mathematical algorithms to be verified via instant, deterministic unit tests running on macOS/Linux in $<100\text{ms}$ without booting an iOS simulator or camera device.
* **Consequences:** Geometric types (`NormRect`, `NormPoint`) must be defined using standard Swift floating-point primitives rather than `CGRect`/`CGPoint`.

---

### ADR-002: Zero Third-Party Dependencies for v1.0
* **Status:** Accepted
* **Context:** Modern iOS provides world-class first-party frameworks (SwiftUI, AVFoundation, Vision, CoreMotion, CoreHaptics, SwiftData, PhotoKit). 3rd-party dependencies often introduce supply-chain risks, privacy disclosure requirements, build overhead, and maintenance friction.
* **Options:**
  1. Use popular 3rd-party libraries (Alamofire, SwiftSoup, GPUImage, Lottie, MLKit).
  2. Build v1.0 using 100% first-party Apple SDKs.
* **Chosen Approach:** **Option 2 (100% Native Apple SDKs).**
* **Reason:** Ensures rapid compilation, long-term iOS version compatibility, zero tracking disclosures for App Store privacy nutrition labels, and full exploitation of Apple Neural Engine hardware acceleration.
* **Consequences:** We write lightweight, custom streaming parsers for OpenGraph metadata and clean direct AVFoundation actors.

---

### ADR-003: Share Sheet & No-Auth URL Ingest for v1.0
* **Status:** Accepted
* **Context:** The Android codebase had heavy dependencies on Pinterest OAuth token brokers and faced strict 1,000 req/day Trial rate limits. On iOS, users typically save inspiration from Pinterest, Instagram, and Safari into photos or share sheets.
* **Options:**
  1. Require a Pinterest OAuth serverless token broker for launch.
  2. Launch v1.0 with the native iOS Share Sheet Extension + Clipboard Link Resolver + PhotosPicker + Curated Starter Library, deferring direct OAuth to v1.1.
* **Chosen Approach:** **Option 2 (Frictionless Ingestion).**
* **Reason:** Eliminates backend hosting requirements, allows users to start using the app in $<3\text{ seconds}$ without creating an account, and bypasses third-party API rate limits completely.
* **Consequences:** Mode B (Pick & Match) functions instantly for any public web pin or photo; Mode A (Scan & Recommend) in v1.1 will operate over locally indexed reference libraries.

---

### ADR-004: Apple Vision Framework for ML & Saliency
* **Status:** Accepted
* **Context:** Real-time human body pose estimation and subject detection are required for live composition analysis.
* **Options:**
  1. Google ML Kit iOS SDK / MediaPipe iOS Tasks.
  2. Apple Vision Framework (`VNDetectHumanBodyPoseRequest`, `VNGenerateAttentionBasedSaliencyImageRequest`).
* **Chosen Approach:** **Option 2 (Apple Vision Framework).**
* **Reason:** Vision is built into iOS, optimized for Apple Silicon (ANE), produces zero battery drain compared to CPU/GPU fallback, and requires no runtime model downloads on first launch.
* **Consequences:** Simplifies model lifecycle management to zero initialization states.

---

### ADR-005: Decoupled ML Inference from Viewfinder Rendering
* **Status:** Accepted
* **Context:** Running heavy machine learning inference on every camera frame at 60fps causes severe device thermal throttling and battery drain.
* **Options:**
  1. Run Vision inference synchronously on every video frame at 60fps.
  2. Throttle Vision inference to 8–15Hz while rendering the SwiftUI HUD and spirit level smoothly at 60/120Hz via motion interpolation.
* **Chosen Approach:** **Option 2 (Decoupled Asynchronous Loop).**
* **Reason:** Guarantees ProMotion 120Hz visual fluidity on modern iPhones while keeping device temperatures low during prolonged coaching sessions.
* **Consequences:** The UI layer must smoothly interpolate between discrete inference state outputs.

---

### ADR-006: Strict One-Handed Ergonomics (Bottom 30% Thumb Deck)
* **Status:** Accepted
* **Context:** Users hold phones in one hand while composing photos in the field. Reaching the top of large screens (iPhone Pro Max / Plus) causes grip instability.
* **Options:**
  1. Spread controls evenly across top, middle, and bottom.
  2. Anchor all primary interactive controls (shutter, lens switcher, mode carousel, target picker) in the bottom 30% thumb deck.
* **Chosen Approach:** **Option 2 (Bottom 30% Thumb Deck).**
* **Reason:** Complies with Apple Human Interface Guidelines and allows effortless one-handed shooting.
* **Consequences:** The top HUD is reserved strictly for passive status icons and non-frequent toggles.

---

### ADR-009: Image Fidelity & Analysis/Preview/Capture Pipeline Separation
* **Status:** Accepted
* **Context:** Camsthetics is a coaching app that must also be a *camera*. The coaching loop needs cheap, small, converted frames at 8–15Hz; the product promise (`PRD.md` §5.1, Principle 4 "Pristine Capture Fidelity") needs the best photograph the device can produce. The natural engineering shortcut — convert the camera stream once into a convenient RGB buffer and use it for analysis, preview, *and* the saved photo — silently destroys resolution, colour, dynamic range, and metadata. This failure is invisible in code review and only shows up as "the photos look worse than the Camera app".
* **Options:**
  1. One shared processed frame pipeline serving analysis, preview, and capture (simplest to build).
  2. Two paths: shared analysis/preview, separate capture.
  3. **Three architecturally distinct pipelines** — analysis, preview, capture — sharing only the camera input, each owning its own output and representation.
* **Chosen Approach:** **Option 3 (Three-Pipeline Separation).**
* **Reason:** It is the only option where a performance optimization *cannot* become an image-quality regression. It makes the rule enforceable rather than aspirational: the analysis pipeline may aggressively degrade its representation, because that representation structurally cannot reach `PhotoLibraryService`. The governing rule is: *"Real-time analysis may sacrifice resolution and representation for performance; final image capture may not sacrifice quality merely to simplify analysis."*
* **Consequences:**
  * Three outputs are configured on one `AVCaptureSession`: `AVCaptureVideoDataOutput` (analysis), `AVCaptureVideoPreviewLayer` (preview), `AVCapturePhotoOutput` (capture) — see `ARCHITECTURE.md` §4.4.
  * More configuration surface and more memory pressure than a single shared pipeline; accepted deliberately.
  * The terms **analysis frame**, **preview frame**, and **captured photo** are distinct throughout all specifications and must not be used interchangeably.
  * A directly testable invariant exists: changing analysis resolution, throttle rate, or pixel format must produce **zero** change in captured photo dimensions, format, colour space, or metadata.
  * `CamstheticsEngine` is unaffected — it consumes normalized geometry regardless of frame origin (ADR-001 preserved).

---

### ADR-010: Runtime-Queried Native Photo Format, Colour & Dynamic Range
* **Status:** Accepted
* **Context:** Defaulting to JPEG is the convenient choice and the one most sample code takes. It is also an 8-bit SDR container that discards wide colour and HDR characteristics the sensor actually captured. Meanwhile device capabilities (maximum photo dimensions, available codecs, HDR/EDR support, supported colour spaces) differ across iPhone generations and iOS versions, so any hard-coded assumption is wrong on some device in the validation matrix.
* **Options:**
  1. Always JPEG (maximum interoperability, minimum thought).
  2. Always RAW/ProRAW (maximum latitude).
  3. Hard-coded per-device format tables.
  4. **Runtime capability query, HEIF/HEVC preferred where supported, with a documented selection policy.**
* **Chosen Approach:** **Option 4 (Runtime-Queried Native Format).**
* **Reason:** It satisfies FIDELITY-05/FIDELITY-06 without assuming device capabilities, and it keeps the analysis pipeline's SDR/RGB working representation from ever influencing the capture representation. Format selection inputs are device capabilities, iOS version, product requirements, quality requirements, and storage considerations — not convenience.
* **Consequences:**
  * Capture format is a runtime decision with a per-capture log rather than a compile-time constant.
  * **RAW/ProRAW is explicitly a separate product capability**, not an assumed equivalent of the native processed-photo path; introducing it requires its own ADR covering storage, review behaviour, and its own validation matrix. v1.0 remains on the native processed-photo path.
  * Capture-configuration intent is specified in the docs; the exact API surface is version-dependent and pinned on device during Phase 2.0 (this is where `PRODUCT_SPEC.md` §1.5's `isHighResolutionPhotoEnabled` shorthand is reconciled with the iOS 17+ photo-dimensions API — the *intent*, full native sensor resolution with no re-encode, is unchanged).

---

### ADR-011: Deliberate Camera & Lens Selection (No Silent Switching)
* **Status:** Accepted
* **Context:** iPhone camera configurations vary widely across generations (single, dual, dual-wide, triple, and future arrangements). Virtual devices such as `.builtInTripleCamera` switch constituent lenses automatically based on zoom and light level. A lens switch the user did not ask for changes focal length, stabilization behaviour, low-light characteristics, and effective image quality — and, critically for this product, it changes the field of view the coaching engine is reasoning about.
* **Options:**
  1. Hard-code a single `.builtInWideAngleCamera` everywhere (simple, ignores hardware).
  2. Use a virtual multi-camera device and let the system switch freely without documenting the mapping.
  3. **Deliberate, documented device/zoom selection driven by user-visible zoom intent, with runtime discovery of available devices.**
* **Chosen Approach:** **Option 3 (Deliberate & Documented).**
* **Reason:** The lens capsule (`.5`, `1x`, `2`, `3x` — `PRODUCT_SPEC.md` §1.5) is a user-visible promise about framing. Automatic selection must consider requested zoom, available devices, focal length, stabilization, low-light behaviour, device capabilities, and continuity of the preview/capture experience — and must never produce an unexpected image-quality change that the user did not initiate.
* **Consequences:**
  * The pill → device/zoom mapping is documented per supported device generation and resolved at runtime.
  * A lens switch may not change capture format, colour space, or maximum photo dimensions unless the user-visible zoom changed.
  * Constituent-device switching inside a virtual device is permitted only where it matches user-visible zoom intent and is documented.
  * FOV differences between devices feed directly into the preview/capture consistency work (FIDELITY-10).

---

### ADR-012: Device-First Image-Quality Validation (No Simulator)
* **Status:** Accepted
* **Context:** The iOS Simulator has no camera hardware, no computational photography pipeline, and no representative capture characteristics. Any camera "test" that passes there proves nothing about image quality, and its presence in a test plan creates false confidence. Image fidelity is a first-class requirement (`PRD.md` §5.1), so it needs first-class evidence.
* **Options:**
  1. Validate camera behaviour in the Simulator with synthetic inputs.
  2. Validate on whatever single physical device is nearest.
  3. **Validate on a defined physical-device matrix, comparing against Apple's native capture path, with documented measurements.**
* **Chosen Approach:** **Option 3 (Device-First, Documented Comparison).**
* **Reason:** Image quality claims must be evidence-backed. Comparison against the highest-quality appropriate capture path available through Apple's native APIs — same scene, same conditions, back-to-back — is the only way to know whether Camsthetics is adding loss.
* **Consequences:**
  * **No Simulator-based camera testing is introduced into the implementation plan.** Simulator use remains limited to non-camera snapshot/UI tests (`ARCHITECTURE.md` §6.1).
  * Validation devices: **iPhone 14** and **iPhone 16** (where available). Workflow: Windows host → macOS VM → Xcode → physical iPhone over USB passthrough.
  * Evaluated dimensions: resolution, detail, sharpness, noise, dynamic range, highlight retention, shadow detail, colour, HDR behaviour, field of view, crop, orientation, stabilization, metadata, file format, file size, capture latency.
  * **"Native-quality" may not be claimed on the basis that an image looks acceptable.** Measurable differences are documented; deviations are either fixed or explicitly accepted with rationale.
  * Phase 2 is gated behind a minimal physical-device proof of concept before any camera abstraction is built (`IMPLEMENTATION_PLAN.md` Phase 2.0).

---

### ADR-013: Phase 2.0 Capture Fidelity Proof — VideoDataOutput State Has No Effect on Captured Photo
* **Status:** Accepted
* **Context:** ADR-009 asserts that analysis, preview, and capture are architecturally independent pipelines, and ADR-012 gates Phase 2 behind a physical-device proof of that claim before any `CameraService`/`VisionService` camera abstraction is built. The specific, testable risk was: attaching an `AVCaptureVideoDataOutput` to the session for real-time coaching analysis — and actually driving it with a live delegate — could silently alter what `AVCapturePhotoOutput` captures (resolution, format, colour, or metadata), the exact failure mode ADR-009's three-pipeline separation exists to prevent. This needed empirical evidence, not architectural argument, per ADR-012.
* **Options:**
  1. Trust the three-pipeline separation architecture (ADR-009) as sufficient reasoning on its own and proceed straight to building `CameraService`.
  2. Run a minimal, throwaway harness on physical hardware that captures one photo via the native `AVCapturePhotoOutput` path under three `AVCaptureVideoDataOutput` states — attached+active (Trial A), attached+idle (Trial B), absent (Trial C) — and compare the resulting artifacts on measurable characteristics.
* **Chosen Approach:** **Option 2 (Empirical A/B/C Proof on Physical iPhone 16).**
* **Reason:** Architectural intent is not evidence (ADR-012). Only a same-scene, same-conditions, back-to-back comparison of the *actual* `AVCapturePhoto.fileDataRepresentation()` bytes — inspected read-only via ImageIO, independently of the app's own introspection — can establish whether the analysis output silently degrades capture. Running this before writing `CameraService`/`VisionService` means the pipeline-separation invariant is verified before, not after, production code is built on top of it.
* **Result (empirical, not a design choice):** All three trials, run on a physical iPhone 16 with no Simulator involved, produced **characteristic-equivalent** artifacts: identical resolved dimensions (4032×3024), container/UTI (`public.heic`), codec (HEVC `hvc1`), colour space (Display P3) and ICC profile, bit depth (8 bpc), auxiliary-image presence and structure (HDR gain map present and structurally identical; depth/disparity/portrait-matte absent in all three), EXIF/TIFF/MakerApple key structure, `device.activeFormat`, and every queried `AVCapturePhotoOutput` capability flag. Trial A's frame counter (7) confirmed its analysis delegate was genuinely live at capture time, not merely configured. Observed differences (file size, exposure metadata, HDR headroom value, capture latency, SHA-256) are the naturally variable per-exposure characteristics the proof's pass criterion explicitly excludes — this is **characteristic equality**, not byte-for-byte equality, and is not a claim of parity with Apple's Camera.app computational-photography pipeline. Full methodology, trial definitions, and the complete comparison table are recorded in `PHASE2_CAPTURE_PROOF.md`.
* **Consequences:**
  * `PRODUCT_SPEC.md` FIDELITY-01/02 and ADR-009's pipeline-independence claim are now empirically confirmed, not merely architecturally argued, on physical iPhone 16 hardware.
  * The Phase 2.0 hard gate (`IMPLEMENTATION_PLAN.md`) is satisfied; `CameraService`/`VisionService` production camera architecture may proceed on top of this verified invariant.
  * The proof surfaced one unrelated, pre-existing observation — `photoOutput.maxPhotoDimensions` (8064×6048, the largest `supportedMaxPhotoDimensions` entry) resolves to the native 4032×3024 `activeFormat` dimensions rather than the requested 8064×6048 — identically across all three trials, so it is not an A/B/C fidelity difference. It is unresolved by this ADR and remains open under the runtime format-selection work already scoped by ADR-010.
  * The capture-fidelity harness (`App/Camsthetics/CaptureFidelityProof/`) remains a disposable, non-production artifact per its own file header; this ADR records its finding, not a commitment to keep the harness itself.

---

### ADR-014: Camera Quality Philosophy — Apple's Pipeline as Baseline, Not Ceiling
* **Status:** Accepted (product philosophy; **no code, UI, or architecture changed by this ADR alone**)
* **Context:** Every prior ADR in this document (especially ADR-009 through ADR-013) establishes and empirically proves a *floor*: Camsthetics' analysis/coaching layer must never degrade what Apple's native capture path would otherwise produce. That floor is correct and remains in force. But stated on its own, "never degrade Apple's output" is silent on the separate question of whether Camsthetics should ever try to produce a **better** result than Apple's default rendering — through its own scene understanding, capture-decision timing, or specialized rendering — for scenarios where that is legitimately achievable through public APIs. Left unaddressed, this ambiguity risks the project treating "matches Apple" as the finished state for every future camera decision, rather than as the minimum bar.
* **Options:**
  1. Leave the philosophy exactly as "no degradation vs. Apple" and treat parity with the native Camera app as the ceiling of ambition for all future capture-quality and decision-making work.
  2. Explicitly separate the **hard safety floor** (no degradation — unchanged, non-negotiable) from a **product objective layered on top** (Apple's pipeline is the *baseline* to measure against, not the *ceiling* of what Camsthetics is allowed to achieve), and require any claimed improvement to be classified and, where practical, measured against native Camera under matched conditions before being treated as fact.
* **Chosen Approach:** **Option 2.**
* **Reason:** Options are not mutually exclusive in practice — Option 2 is strictly additive to the existing invariant, not a replacement of it. It gives future engineering work (the Camsthetics Decision Engine, MotionShoot — see `CAMERA_DECISION_RESEARCH.md` §12) an explicit mandate to pursue genuine quality/decision improvements, while keeping the ADR-009/ADR-012/ADR-013 pipeline-separation guarantee exactly as strict as before. It also closes a specific reasoning failure mode — "Apple does it this way, therefore this is the highest-quality approach" — which is false as a general claim: Apple's public-API behavior is highly optimized for Apple's own objectives, not necessarily for Camsthetics' specific photographic goals (e.g. a curated aesthetic-coaching capture, or a MotionShoot candidate-frame selection), and Camsthetics is free to make different, better higher-level decisions using the same public APIs.
* **The Rule:**
  * **Hard safety floor (unchanged from ADR-009/PRD.md §5 principle 4):** "No degradation vs. Apple's native capture" remains non-negotiable. Analysis and decision-making may never force the capture pipeline to use a degraded representation.
  * **Product objective (new, additive):** "Use Apple's camera pipeline as the baseline, then actively determine whether Camsthetics can make a better decision for this specific photographic or videographic objective." A candidate improvement is evaluated across the dimensions that actually matter — fine detail/texture, sharpness, motion clarity, noise, dynamic range, highlight/shadow preservation, exposure and focus accuracy, color accuracy, skin rendering, local contrast, artifacting, temporal consistency (video), stabilization, composition, subject quality, capture timing, aesthetic quality, and file/metadata integrity — never by a proxy like file size, resolution number, or bitrate alone.
  * **Never assume Apple is optimal:** the correct reasoning shape is "Apple does it this way; understand why, treat it as the baseline, then determine whether Camsthetics has a legitimate opportunity to do better" — not "Apple does it this way, therefore it is correct."
  * **Public API boundary is absolute:** Camsthetics pursues this only through legitimate public iOS APIs and documented platform capabilities. It must not attempt to reproduce or bypass Apple's private ISP, computational-photography, or system-only functionality.
  * **Measure, don't assert:** an improvement claim requires an objective, same-device/same-conditions comparison against native Camera (subject, framing, lighting, focus and exposure scenario, motion held constant) before being asserted as fact — mirroring the evidentiary standard ADR-012/ADR-013 already established for fidelity claims. Likewise, an optimization is not rejected merely because Apple's own app does not use it.
  * **Classification requirement:** any proposed camera-quality change must be classified as one of: Baseline preservation, Quality improvement, Decision improvement, Processing/rendering improvement, UX improvement, or Experimental/unverified. Experimental changes must be validated (per the measurement rule above) before being treated as confirmed improvements.
* **Consequences:**
  * `PRD.md` §5 gains a new §5.2 stating this objective alongside the existing §5.1 fidelity requirement; principle 4 ("Pristine Capture Fidelity") is explicitly the floor referenced here, not superseded by it.
  * `ARCHITECTURE.md` §1's four non-negotiable architectural commitments are unchanged by this ADR — commitment 4 (pipeline separation) *is* the mechanism that makes the floor enforceable; this ADR adds a product-layer objective on top, not a new architectural commitment.
  * The future Camsthetics Decision Engine and the future **MotionShoot** feature (`CAMERA_DECISION_RESEARCH.md` §12, `IMPLEMENTATION_PLAN.md` Phase 8) are the first concrete places this objective applies — they are explicitly future/not-started, not authorized for implementation by this ADR.
  * This ADR is a philosophy/documentation change only. It does not modify `CameraService`, any Phase 2 production code, or any test.
