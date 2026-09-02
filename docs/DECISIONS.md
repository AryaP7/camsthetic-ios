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
