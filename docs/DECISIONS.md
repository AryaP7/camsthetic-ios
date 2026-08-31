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
