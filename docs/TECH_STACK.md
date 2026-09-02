# Technology Stack & Evaluation — Camsthetics (iOS)

**Document Version:** 1.0  
**Status:** Authoritative Foundation  
**Companion Documents:** `PRD.md`, `ARCHITECTURE.md`, `PRODUCT_SPEC.md`

---

## 1. Technology Evaluation Framework

Every technical decision in Camsthetics is evaluated using the following decision template:
$$\text{Choice} \longrightarrow \text{Why} \longrightarrow \text{Alternatives Considered} \longrightarrow \text{Why Rejected} \longrightarrow \text{Consequences}$$

---

## 2. Core Technology Decisions

### 2.1 UI Framework & View Hierarchy
* **Choice:** **SwiftUI (Primary) with targeted UIKit / CALayer hosting for AVPreview**
* **Why:** SwiftUI delivers first-class declarative state-driven rendering, spring animations, native Apple materials (`.ultraThinMaterial`), Dynamic Type, and accessibility out of the box with minimal boilerplate. The camera preview itself is hosted via `UIViewRepresentable` wrapping `AVCaptureVideoPreviewLayer`.
* **Alternatives Considered:** 100% UIKit with AutoLayout; 100% Metal custom rendering engine.
* **Why Rejected:** 100% UIKit requires 3× more layout boilerplate and complex manual state binding. A 100% Metal custom UI engine introduces massive engineering complexity without noticeable benefits over SwiftUI's Metal-backed rendering pipeline.
* **Consequences:** Viewfinder HUD and controls remain declarative and maintainable; low-level camera feed rendering is kept in performant CoreAnimation layers.

---

### 2.2 Camera & Hardware Capture Engine
* **Choice:** **AVFoundation (`AVCaptureSession`, `AVCaptureVideoDataOutput`, `AVCapturePhotoOutput`)**
* **Why:** AVFoundation is Apple's native media framework. It provides direct, zero-overhead access to multi-camera optical switches (`.builtInTripleCamera` / `.builtInDualWideCamera`), manual exposure/focus control, 60fps video data streams, and hardware-accelerated computational capture (Smart HDR, Deep Fusion, Apple ProRAW).
* **Alternatives Considered:** GPUImage3; CameraKit; custom AVFoundation wrappers.
* **Why Rejected:** 3rd-party camera libraries add unwanted abstraction layers, lag behind new iOS camera hardware capabilities, and introduce binary bloat.
* **Consequences:** We write clean, direct AVFoundation actor code with zero external dependencies.

---

### 2.3 On-Device Vision & Machine Learning
* **Choice:** **Apple Vision Framework (`VNDetectHumanBodyPoseRequest`, `VNGenerateAttentionBasedSaliencyImageRequest`)**
* **Why:** Vision is pre-installed on all iOS devices, hardware-accelerated by the Apple Neural Engine (ANE), thermally optimized, and requires zero model download steps on first run. It delivers human body pose keypoints in $< 15\text{ms}$ on iPhone 12 and newer.
* **Alternatives Considered:** Google ML Kit for iOS; MediaPipe iOS Tasks; Custom YOLO/TFLite models via CoreML.
* **Why Rejected:** ML Kit adds large binary bloat and requires Google Play-style model syncing. MediaPipe adds heavy C++ dependencies. Apple Vision is native, zero-weight, and deeply integrated into Apple hardware.
* **Consequences:** Zero runtime model download state; instant offline readiness on first app launch; ultra-low battery drain.

---

### 2.4 Device Motion & Spatial Orientation
* **Choice:** **CoreMotion (`CMMotionManager` with Device Motion & Gravity Vector)**
* **Why:** CoreMotion provides calibrated device attitude (quaternions and roll/pitch angles) derived from the hardware gyro and accelerometer at up to $100\text{Hz}$ with zero-lag low-pass hardware filtering.
* **Alternatives Considered:** Raw accelerometer polling; visual horizon line detection alone.
* **Why Rejected:** Raw accelerometer lacks gyroscope sensor fusion. Visual horizon estimation is unreliable in indoor environments with textured walls or complex backgrounds.
* **Consequences:** Live spirit level and roll coaching have $100\%$ confidence and zero latency.

---

### 2.5 Haptic Feedback Engine
* **Choice:** **CoreHaptics (`CHHapticEngine`) paired with `UIFeedbackGenerator`**
* **Why:** CoreHaptics provides granular control over transient sharpness and continuous vibration intensity, enabling distinct tactile patterns (e.g. subtle left/right lateral direction pulses, sharp horizon snap ticks). `UISelectionFeedbackGenerator` handles simple detents.
* **Alternatives Considered:** `AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)`.
* **Why Rejected:** System sound vibration is a crude, jarring buzz that ruins the premium feel of the camera.
* **Consequences:** Delivers a refined, Apple-grade tactile soundtrack that lets users feel framing alignment without staring at numbers.

---

### 2.6 Persistence & Local Data
* **Choice:** **SwiftData (with SQLite/GRDB encapsulation boundary)**
* **Why:** SwiftData is Apple's modern persistence framework for Swift, integrating seamlessly with `@Model` macro annotations, Swift concurrency, and SwiftUI `@Query`.
* **Alternatives Considered:** Core Data; Realm; Raw SQLite via GRDB.
* **Why Rejected:** Core Data requires verbose `NSManagedObjectContext` boilerplate. Realm adds third-party binary size and licensing.
* **Flexible Decision Note:** If the iOS Share Extension requires lightweight cross-process App Group database access without SwiftData cold-start overhead, the storage interface is isolated behind a protocol so a lightweight SQLite/GRDB implementation can be swapped in without touching domain code.
* **Consequences:** Clean, modern, declarative data persistence for reference pins, targets, and session history.

---

### 2.7 Image Ingestion & Networking
* **Choice:** **Native `URLSession` + Lightweight Streaming HTML / JSON Parser**
* **Why:** Resolving Pinterest oEmbed JSON and OpenGraph meta tags requires simple HTTP requests and a $\le 256\text{KB}$ streaming `<head>` parser. Native `URLSession` handles TLS, background tasks, and caching natively with zero dependencies.
* **Alternatives Considered:** Alamofire; SwiftSoup (full HTML DOM parser).
* **Why Rejected:** Adding Alamofire or SwiftSoup adds unnecessary dependencies for parsing simple `<meta property="og:image" content="...">` tags from the head of a web page.
* **Consequences:** Clean, lightweight networking with zero supply-chain risk.

---

### 2.8 Photo Library & Review
* **Choice:** **PhotoKit (`PHPhotoLibrary`, `PHAssetChangeRequest`) + PhotosUI (`PHPickerViewController`)**
* **Why:** PhotoKit is the standard Apple framework for writing full-resolution master captures directly to the system Photos library with complete EXIF metadata and receiving user-selected reference photos with zero invasive permission dialogs.
* **Consequences:** Pristine master photo preservation and standard iOS photo picker UX.

---

### 2.9 Capture Output Format, Colour & Dynamic Range
* **Choice:** **Runtime-queried native photo capture configuration — HEIF/HEVC preferred where supported, with capability discovery at session configuration time (`AVCapturePhotoOutput.availablePhotoCodecTypes`, `supportedPhotoPixelFormatTypes`, `maxPhotoDimensions`, active-format colour space / HDR support).**
* **Why:** The image-fidelity requirement (`PRODUCT_SPEC.md` §1.8) demands the highest-quality *supported* representation for the device actually in the user's hand, not a lowest-common-denominator guess. HEIF/HEVC preserves more detail per byte than JPEG at equivalent size, carries wide-colour and depth/aux data, and is the native container of the modern iOS photo pipeline. Capability differences across iPhone generations and iOS versions are resolved by querying, never by assuming.
* **Alternatives Considered:** Always-JPEG for maximum interoperability; always-RAW/ProRAW for maximum latitude; hard-coded per-device format tables.
* **Why Rejected:** Always-JPEG defaults to a lossy 8-bit SDR container for convenience and discards wide-colour/HDR characteristics — explicitly prohibited by FIDELITY-06. Always-RAW is a **separate product capability** with its own storage, review, and validation implications (FIDELITY-06), not a default. Hard-coded device tables rot with each new iPhone and silently mis-configure unknown hardware.
* **Consequences:** Capture format is a runtime decision with a documented policy and a per-capture log; adding RAW/ProRAW later is an explicit product feature with its own ADR rather than a flag flip. Analysis colour handling (SDR/greyscale) is entirely decoupled from this decision.

---

### 2.10 Analysis Buffer Format & Downsampling Strategy
* **Choice:** **Native camera YUV (`420f`/`420v`) sample buffers delivered to `AVCaptureVideoDataOutput`, downsampled for Vision, with conversions performed only where an algorithm requires them — and never propagated back into the capture path.**
* **Why:** Vision accepts `CVPixelBuffer` directly and performs its own internal preparation; requesting full-resolution BGRA purely for convenience burns bandwidth, memory, and thermal budget for no coaching benefit. Analysis is a *temporary processing input* (FIDELITY-02) and is free to be as small as the algorithms tolerate.
* **Alternatives Considered:** Full-resolution BGRA video output shared by preview, analysis, and capture; a single converted RGB buffer reused as both analysis input and capture source.
* **Why Rejected:** A shared converted buffer is precisely the failure mode the fidelity requirement exists to prevent — it makes the degraded analysis representation the source of the photograph (`camera YUV → RGB → resized RGB → JPEG → saved photo`). It also couples analysis tuning to capture quality, so a performance optimization would silently become an image-quality regression.
* **Consequences:** Analysis resolution, pixel format, and frame rate can be tuned aggressively (including under thermal pressure, §5) with **zero** effect on captured photo dimensions, format, colour space, or metadata — a property that is directly testable (FIDELITY-02 acceptance criteria).

---

## 3. Technology Matrix Summary

| Architectural Subsystem | Chosen iOS Technology | Third-Party Dependencies |
|---|---|---|
| **Viewfinder & HUD UI** | SwiftUI + `AVCaptureVideoPreviewLayer` | None |
| **Camera & Capture** | AVFoundation (`AVCaptureSession`) | None |
| **Photo Capture Path** | `AVCapturePhotoOutput` — runtime-queried HEIF/HEVC, max photo dimensions, native colour/HDR | None |
| **Analysis Frame Path** | `AVCaptureVideoDataOutput` — native YUV, downsampled, throttled (never a capture source) | None |
| **Vision & AI Inference** | Apple Vision (`VNDetectHumanBodyPoseRequest`) | None |
| **Motion Sensing** | CoreMotion (`CMMotionManager`) | None |
| **Haptics** | CoreHaptics (`CHHapticEngine`) + `UIFeedbackGenerator` | None |
| **Persistence** | SwiftData / CoreData via protocol repository | None |
| **Networking & Ingest** | `URLSession` + streaming OpenGraph head parser | None |
| **Image Processing** | CoreImage (`CIContext`, `CIFilter`) | None |
| **Photo Library** | PhotoKit (`PHPhotoLibrary`) + `PHPickerViewController` | None |
| **Testing** | Swift Testing (`import Testing`) + XCTest | None |

> **Crucial Milestone:** The entire v1.0 product stack requires **zero external third-party CocoaPods or SPM packages**, ensuring maximal stability, instant build times, and zero privacy-tracking scrutiny during App Store review.
