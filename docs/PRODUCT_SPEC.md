# Product Specification — Camsthetics (iOS)

**Document Version:** 1.0  
**Status:** Authoritative Foundation  
**Companion Documents:** `PRD.md`, `ARCHITECTURE.md`, `DESIGN_SYSTEM.md`

---

## 1. Feature Specifications

### 1.1 Reference / Target Ingestion (Group INGEST)

#### Feature: Share Sheet & Pasteboard Link Ingestion (INGEST-01)
* **Purpose:** Allows the user to select any reference image from Pinterest, Instagram, Safari, or the web without requiring account credentials.
* **Entry Points:**
  1. iOS Native Share Sheet (`UIActivityViewController` / Share Extension) from Pinterest, Safari, Photos.
  2. In-App Clipboard Banner ("Paste link from clipboard").
  3. Manual Paste input field in the Reference Picker sheet.
* **User Flow:**
  1. User shares or pastes a URL (e.g. `https://pin.it/...`, `https://pinterest.com/pin/...`).
  2. App resolves URL through the ingestion pipeline (URL normalization $\to$ oEmbed API $\to$ OpenGraph `<head>` streaming parse $\to$ direct image fetch).
  3. Image is downscaled to $\le 1024\text{px}$ long edge, converted to sRGB, and aspect-normalized.
  4. Target `CompositionParams` are extracted in background ($<500\text{ms}$).
  5. User is transitioned directly into the Live Coaching viewfinder with this target active.
* **Failure / Degraded States:**
  * Invalid/Unsupported URL $\to$ Inline error alert: *"Unable to resolve image from this link. Please try saving the image to your Photos instead."*
  * Network Unavailable $\to$ *"Internet connection required to load link references."*
  * Private/Deleted Pin $\to$ *"This pin is private or no longer available."*
* **Acceptance Criteria:**
  * Supported URLs resolve and cache within $<2.5\text{s}$ on standard 4G/5G/Wi-Fi.
  * Shared URLs via iOS Share Sheet launch into coaching without user re-auth.

#### Feature: Photos Picker & Curated Library (INGEST-02)
* **Purpose:** Allows instant reference selection from the user's camera roll or pre-bundled aesthetic templates.
* **Entry Points:** Tap "Target" thumbnail pill on viewfinder $\to$ Ingest Sheet $\to$ "Photos" or "Curated Library" tabs.
* **User Flow:**
  1. User selects a photo via native `PHPickerViewController` (read-only, zero privacy prompt required) or picks a template from categories (Portrait, Café, Street, Architecture).
  2. Selected image is ingested and cached under a SHA-256 content hash.
  3. Viewfinder updates with new ghost frame within $<300\text{ms}$.

---

### 1.2 Live Composition Analysis Pipeline (Group COMP)

The composition analysis pipeline executes on both the **Target Image** (one-shot upon ingestion) and the **Live Viewfinder Frame** (sampled continuously at 8–15Hz).

```
[ Input Frame / Image ]
        │
        ├─► Aspect Normalization (Center-crop to narrower common aspect)
        ├─► Subject Detection & Tracking (Vision Saliency / Object Detection)
        ├─► Human Pose Estimation (Vision Human Body Pose for eye-line & pitch)
        ├─► Horizon & Roll Estimation (Sensor Gravity live / Sobel Edge on Target)
        ├─► Camera Angle & Relative Height Estimation (Perspective convergence & eye anchor)
        └─► Subject-to-Frame Size Ratio & CIELAB Palette Extraction
                │
                ▼
      [ CompositionParams ]
```

#### Detailed Dimension Algorithms

1. **Aspect Ratio Normalization:**
   $$\text{aspect}_{\text{common}} = \min(\text{aspect}_{\text{target}}, \text{aspect}_{\text{live}})$$
   The wider image is center-cropped horizontally; the taller image is center-cropped vertically. All subsequent normalized coordinates $(x, y) \in [0.0, 1.0]$ refer to this common aspect space.
2. **Subject Selection (Primary Subject Scoring):**
   When multiple subjects are detected in the frame:
   $$\text{Score}(d) = 0.45 \cdot \text{AreaNorm}(d) + 0.25 \cdot \text{CategoryWeight}(d) + 0.20 \cdot \text{Centrality}(d) + 0.10 \cdot \text{Confidence}(d)$$
   * Person subjects receive category weight $1.0$, Animals $0.9$, Objects $0.4$.
   * **Sticky Lock:** An active tracked subject retains focus unless an alternate candidate scores $\ge 0.15$ higher for 4 consecutive sampled frames.
3. **Roll / Tilt Angle:**
   * **Live Side:** Sourced directly from `CMMotionManager` device gravity vector ($\text{roll} = \operatorname{atan2}(g_x, g_y)$ in degrees). Exact, zero-latency, confidence $= 1.0$.
   * **Target Side:** Computed via Sobel gradient edge orientation histogram across dominant horizontal/vertical line clusters. Confidence capped at $0.70$.
4. **Camera Angle (Pitch) & Relative Height:**
   * Computed using perspective vanishing point convergence, eye-line vertical position relative to horizon, and torso foreshortening ratio.
   * Categorical buckets: `EYE_LEVEL`, `LOW_ANGLE`, `HIGH_ANGLE`, `OVERHEAD`.
5. **Subject-to-Frame Ratio:**
   * For people: Normalized bounding box height ($h_{\text{norm}}$) is used (avoids arm movement skewing area).
   * For objects/scenes: $\sqrt{\text{Area}_{\text{norm}}}$ is used.

---

### 1.3 Coaching Delta Engine & Hysteresis (Group COACH)

#### Delta Calculation & Confidence Gating
For each dimension, the signed delta is computed:
$$\Delta_{\text{tilt}} = \text{Target}_{\text{tilt}} - \text{Live}_{\text{tilt}}$$
$$\Delta_{\text{lateral}} = \text{Target}_{\text{centerX}} - \text{Live}_{\text{centerX}}$$
$$\Delta_{\text{distance}} = \ln\left(\frac{\text{Target}_{\text{ratio}}}{\max(\text{Live}_{\text{ratio}}, \varepsilon)}\right)$$
$$\Delta_{\text{height}} = \text{Target}_{\text{height}} - \text{Live}_{\text{height}}$$

* **Confidence Floor:** Any dimension where $\min(\text{Conf}_{\text{target}}, \text{Conf}_{\text{live}}) < 0.35$ is **suppressed**. No instruction is issued for uncertain dimensions.

#### Movement Instruction Mapping

| Dimension | Tolerance Threshold ($\text{Tol}$) | Direction Rules | Surfaced Copy Template |
|---|---|---|---|
| **Roll / Tilt** | $\pm 2.0^\circ$ | $\Delta\theta > 0 \to \text{Rotate Clockwise}$<br>$\Delta\theta < 0 \to \text{Rotate Counter-Clockwise}$ | "Rotate right {d}°"<br>"Rotate left {d}°" |
| **Lateral** | $\pm 0.04$ ($4\%$ of frame) | $\Delta x > 0 \to \text{Right}$<br>$\Delta x < 0 \to \text{Left}$ | "Pan right" / "Step right"<br>"Pan left" / "Step left" |
| **Distance** | $\pm 0.08$ ratio | $\text{Ratio} > 1.08 \to \text{Closer}$<br>$\text{Ratio} < 0.92 \to \text{Further}$ | "Move closer"<br>"Step back" |
| **Height** | $\pm 0.12$ | $\Delta h > 0 \to \text{Raise}$<br>$\Delta h < 0 \to \text{Lower}$ | "Raise phone"<br>"Lower phone" |
| **Zoom** | Opt-in fallback | Used only if distance delta remains unresolved after 3 seconds of movement failure | "Zoom in a touch"<br>"Zoom out a touch" |

* **Lateral Kind Disambiguation:** If subject size and height match within tolerance, instruct **"Pan"** (rotate camera in place). If size/height also differ, instruct **"Step"** (physically translate position).

#### Anti-Chatter Hysteresis Layer
To guarantee that cues never flicker or jitter:
1. **Dual Thresholds:** Entry at $1.0 \times \text{Tol}$; exit only when error drops below $0.7 \times \text{Tol}$.
2. **Consecutive Frame Gating:** An instruction must be valid for **3 consecutive frames** to appear, and absent for **4 consecutive frames** to disappear.
3. **Minimum Dwell Time:** Once displayed, an instruction is held for at least **700ms** before being replaced.
4. **Surfaced Cap:** At most **2 instructions** are surfaced simultaneously, prioritized strictly in order: $\text{Tilt} \to \text{Lateral} \to \text{Distance} \to \text{Height} \to \text{Zoom}$.

---

### 1.4 Match Scoring & Confidence Tiers (Group SCORE)

#### Match Score Formula
For each active dimension $d$ with normalized error $e_d$:
$$s_d = \exp\left( -e_d^2 \right)$$
$$\text{Score} = \operatorname{round}\left( 100 \cdot \frac{\sum (w_d \cdot c_d \cdot s_d)}{\sum (w_d \cdot c_d)} \right)$$

* **Weights ($w_d$):** Tilt $0.18$, Lateral $0.30$, Distance $0.24$, Height $0.13$, Pitch Angle $0.15$.
* **Confidence ($c_d$):** Per-dimension confidence weight.

#### Confidence Tiers & Degradation Ladder

```
┌───────────┐    Live subject detected + Target subject detected
│   FULL    │ ────────────────────────────────────────────────────────► All 5 dimensions active; Score 0-100; On-Target unlockable (≥85)
└─────┬─────┘
      │ Live subject missing (dark, wall, subject out of frame)
      ▼
┌───────────┐
│  PARTIAL  │ ────────────────────────────────────────────────────────► Tilt active + "Find your subject" prompt; Score capped at 60
└─────┬─────┘
      │ Both target and live are landscapes / scenes without subjects
      ▼
┌───────────┐
│  MINIMAL  │ ────────────────────────────────────────────────────────► Tilt active + Horizon Line Placement (Rule of Thirds); Score capped at 85
└───────────┘
```

* **Tier Transition Hysteresis:** Requires 5 consecutive agreeing frames to change tier, preventing momentary detection dropouts from flickering the UI.

---

### 1.5 Viewfinder Controls & Capture Execution (Group CAMERA)

#### Hardware & Camera Controls
* **Lens Selection:** Floating glass capsule with `.5`, `1x`, `2`, `3x`. Switching lenses rebinds the camera without freezing the UI and resets the coaching session state.
* **Tap-to-Focus & Exposure:**
  * Single tap places a $70\times 70\text{pt}$ animated yellow reticle and sets AF/AE point (auto-cancels after 3s).
  * Sliding the sun icon adjacent to the reticle adjusts exposure compensation ($\pm 2.0\text{ EV}$).
  * Long press locks AE/AF with an on-screen "AE/AF LOCK" yellow indicator.
* **Aspect Ratio Selection:** Toggle between `4:3` (Native sensor, default), `16:9` (Framed crop), and `1:1` (Square). Aspect ratio changes capture output only; analysis continues on full uncropped stream.

#### Shutter & Capture Fidelity
* **Manual Shutter:** Responsive within $<150\text{ms}$ of tap.
* **Auto-Capture (Opt-In):** When Match Score $\ge 85\%$ sustained for $600\text{ms}$, displays a 3-2-1 visual countdown ring and triggers capture automatically. Cooldown is $4.0\text{s}$.
* **Zero Re-Encode Master Quality:**
  * Captured using `AVCapturePhotoOutput` with `isHighResolutionPhotoEnabled = true` and `qualityPrioritization = .quality`.
  * Preserves full native sensor resolution, Apple Smart HDR / Deep Fusion pipeline, and complete EXIF metadata.
  * Direct non-destructive write to Apple Photos (`PhotoKit`).
  * **Normative fidelity requirements — see §1.8 (Group FIDELITY).** §1.8 governs pipeline separation, pixel format, resolution, HDR/color, photo format, metadata, lens selection, and quality validation for everything in this section.

---

### 1.6 Post-Capture Review, Compare & Session History (Group REVIEW)

#### Interactive Drag-to-Compare Review
* Opens automatically after capture ($<300\text{ms}$).
* **Draggable Split Screen:** Full-screen view with a vertical interactive divider. Swiping left/right wipes between the reference target and the captured photo over identical aspect bounds.
* **Residual Delta Summary:** Displays the final match score achieved at the shutter press, plus actionable bullet points of residual error (*"Tilt was 1.5° off"*, *"Held slightly too high"*).
* **Actions:**
  * **"Re-Coach" (Primary):** Drops straight back into live camera with the same target.
  * **"Auto-Straighten" (1-Tap):** Applies non-destructive CoreImage rotation/crop to fix residual roll error.
  * **"Share / Save":** Native iOS Share Sheet and Camera Roll verification.

#### Session History
* Local timeline grid of past capture sessions.
* Displays target thumbnail, captured photo thumbnail, match score badge, and date.
* Selecting any historical session allows instant Re-Coaching against that historical target.
* Automatic storage pruning: limits local cache to 200 sessions, oldest-first, with manual "Clear History" in Settings.

---

### 1.7 Accessibility & Privacy (Group SYSTEM)

#### Accessibility Requirements
* **VoiceOver Live Regions:** All instruction changes are announced politely via accessibility notifications (`UIAccessibility.post(notification: .announcement)`). Text is concise ($\le 4$ words) for immediate speech output.
* **CoreHaptics Guidance:**
  * Tilt level lock: Single crisp `selectionChanged` tick.
  * Directional lateral cues: Distinct localized transient vibrations.
  * On-Target lock: Soft double success pulse.
* **Dynamic Type:** All non-viewfinder text fully supports dynamic type scaling. Viewfinder HUD text scales with bounded limits to prevent viewport occlusion.
* **High Contrast Scrims:** All white HUD text is backed by semi-transparent dark gradient scrims ensuring $\ge 4.5:1$ contrast ratio against bright backgrounds.

#### Privacy Guarantees
* **Zero Live Frame Storage:** Live analysis frames are processed in volatile memory buffers and discarded immediately. No live video is ever written to disk or transmitted over network.
* **100% On-Device Coaching:** All pose, subject, tilt, and score computations run locally on the Apple Neural Engine.
* **No Account Required:** Full core coaching functionality operates completely offline without user tracking.

---

### 1.8 Image Fidelity & Native Capture (Group FIDELITY)

**Hard architectural requirement.** This group is first-class: it constrains every other group, and no feature in §1.1–§1.7 may be implemented in a way that violates it.

> **"Camsthetics must preserve the highest image quality available through Apple's supported third-party camera APIs. The app must not introduce unnecessary degradation to resolution, detail, color fidelity, dynamic range, HDR characteristics, metadata, orientation, stabilization, or other capture characteristics."**

The app's composition/coaching functionality must **not** require compromising the final captured image.

**Governing rule (mandatory):**

> **"Real-time analysis may sacrifice resolution and representation for performance; final image capture may not sacrifice quality merely to simplify analysis."**

---

#### Feature: Three-Pipeline Separation (FIDELITY-01)
* **Purpose:** Guarantee that work done for coaching or UI can never become the source of the saved photograph.
* **Definitions (these three terms are distinct throughout all specifications):**

| Term | Definition | Quality Contract |
|---|---|---|
| **Analysis frame** | A temporary processing input derived from the video data output, delivered to Vision / the coaching engine. | Optimized for latency. Degradation is *expected and permitted*. |
| **Preview frame** | The live viewfinder image presented to the user. | Optimized for responsiveness, latency, stable frame rate, correct orientation and aspect. |
| **Captured photo** | The final photograph written to Apple Photos. | Highest-quality supported native photo path. No degradation permitted. |

* **Requirements:**
  1. The three pipelines may share the same `AVCaptureSession` camera input, but each owns its own output and its own representation.
  2. **The analysis pipeline must never force the capture pipeline to use its degraded representation.** Analysis representations are temporary processing inputs; they are not the photograph.
  3. If a lower-resolution or converted buffer is created for Vision/coaching, the original high-quality capture path remains independent of it.
  4. Preview processing must not dictate the quality of the final captured image. No image conversion may be introduced *merely* to support the preview UI.
  5. **The following must never be saved as the final photograph:** Vision frames, preview frames, downsampled analysis frames, unnecessarily converted RGB buffers, screenshots of the preview, compressed intermediate representations.
  6. The final image must originate from the appropriate high-quality photo capture API (`AVCapturePhotoOutput`). A photograph is never reconstructed from processed video frames.
* **Acceptance Criteria:**
  * The saved asset's pixel dimensions, format, and metadata are traceable to the photo output, not to any video/analysis buffer.
  * Disabling the analysis pipeline entirely produces a byte-comparable capture configuration (same dimensions, format, colour space, metadata fields).

---

#### Feature: Analysis Pipeline Latitude (FIDELITY-02)
* **Purpose:** Give real-time coaching full freedom to optimize, inside a boundary that cannot leak into capture.
* **The analysis pipeline may:** downsample frames; use lower-resolution representations; convert pixel formats when required; use Vision, Accelerate, or Metal; perform computer-vision processing; discard frames; process asynchronously; and apply frame-rate throttling (per §1.2 and `ARCHITECTURE.md` §4.1, sampled at 8–15Hz with latest-only backpressure).
* **The analysis pipeline may not:** alter the capture session's photo configuration, reduce capture resolution, change capture colour space or format, disable a native capture capability, or supply the buffer that becomes the saved photograph.
* **Acceptance Criteria:** Changing analysis resolution, throttle rate, or pixel format produces **zero** change in captured photo dimensions, format, colour space, or metadata.

---

#### Feature: Pixel Format & Conversion Policy (FIDELITY-03)
* **Purpose:** Prevent silent lossy conversion chains.
* **Prohibited when the conversion exists only to serve analysis:**

```
camera YUV → RGB → resized RGB → JPEG → saved photo        ❌ PROHIBITED
```

* **Requirements:**
  1. Use the native camera/output formats wherever practical.
  2. If conversion is required for Vision or another algorithm: create a **separate** processing representation; preserve the original capture path; document why the conversion is necessary; never feed the converted representation back into capture.
  3. **Any lossy conversion must be explicitly justified** in code comments and in `DECISIONS.md`.
* **Acceptance Criteria:** Every format conversion in the codebase is attributable to either (a) the analysis pipeline, or (b) an explicitly documented and justified capture-path decision.

---

#### Feature: Resolution Policy (FIDELITY-04)
* **Purpose:** Keep analysis resolution and capture resolution independent concerns.
* **Requirement:** **Never reduce capture resolution merely because analysis operates at a lower resolution.**

```
HIGH-QUALITY CAMERA CAPTURE          CAMERA FRAME
        │                                  │
        ▼                             downsample
     capture                               │
                                           ▼
                                   Vision / analysis
                                           │
                                           ▼
                                   coaching decision
```

* The analysis resolution may be aggressively optimized for performance without affecting capture resolution.
* Session preset / format selection must be chosen so that the photo output retains the device's maximum supported photo dimensions; the video data output is configured independently for analysis.
* **Acceptance Criteria:** Captured photo dimensions equal the maximum supported photo dimensions for the selected device, format, and product aspect ratio setting (§1.5).

---

#### Feature: HDR, Wide Colour & Dynamic Range (FIDELITY-05)
* **Purpose:** Prevent an SDR/RGB analysis assumption from flattening a high-dynamic-range capture.
* **The architecture must explicitly account for:** HDR; wide colour; colour space; extended dynamic range where supported; HEIF/HEVC where appropriate; device-specific capture capabilities.
* **Requirements:**
  1. Do not tone-map, flatten, or convert a high-dynamic-range capture into a lower-quality representation merely because the analysis pipeline uses SDR/RGB imagery.
  2. **Analysis colour representation and final capture representation are separate concerns.** The analysis pipeline may work in SDR sRGB/greyscale indefinitely; this has no bearing on capture.
  3. **Do not make assumptions about device capabilities.** Query and configure capabilities at runtime (device/format support, supported photo dimensions, supported codecs, HDR/EDR support, colour space availability).
* **Acceptance Criteria:** On a device supporting HDR photo capture, the saved asset retains its HDR/wide-colour characteristics; the analysis path's colour handling is not observable in the saved asset.

---

#### Feature: Photo Format Selection (FIDELITY-06)
* **Purpose:** Select an appropriate *native* photo representation rather than a convenient one.
* **Selection inputs:** device capabilities; iOS version; product requirements; quality requirements; storage considerations.
* **Requirements:**
  1. **Do not default to JPEG simply because it is convenient.** HEIF and other Apple-supported high-quality formats are evaluated on merit (see `TECH_STACK.md` §2.9).
  2. Format availability is queried at runtime; there is no hard-coded format assumption.
  3. **RAW / ProRAW, if ever introduced, is a separate explicit product capability** — it is *not* assumed equivalent to, or a drop-in replacement for, the normal native photo pipeline. It carries its own capture configuration, storage footprint, review behaviour, and validation matrix. (v1.0 scope remains the native processed-photo path; see `PRD.md` §6 roadmap.)
* **Acceptance Criteria:** The chosen container/codec is logged per capture and matches the documented policy for that device and iOS version.

---

#### Feature: Metadata Preservation (FIDELITY-07)
* **Purpose:** Deliver a photograph that behaves like a native one inside Apple Photos.
* **Requirement:** Do not unnecessarily strip or alter photo metadata. Preserve, where available and appropriate: orientation; capture information (exposure, ISO, shutter, timestamps); colour information (ICC/colour space); location metadata **when the user has authorized it**; camera/lens information; other supported photographic metadata.
* **Privacy constraint:** Metadata handling must respect Apple's privacy/security APIs and user permissions. Location is embedded only under an existing, granted authorization — never inferred, cached, or re-attached to bypass a permission state. This is consistent with §1.7 Privacy Guarantees.
* **Acceptance Criteria:** EXIF/TIFF/Exif-Aux fields present on a native Camera.app capture of the same scene are present on the Camsthetics capture, except fields Apple does not expose to third-party capture.

---

#### Feature: Camera & Lens Selection Policy (FIDELITY-08)
* **Purpose:** Make device/lens choice deliberate, documented, and free of surprise quality changes.
* **Requirements:**
  1. Do not hard-code assumptions about a single camera. Account for the multiple camera configurations across iPhone generations (single, dual, dual-wide, triple, and future arrangements).
  2. Camera/lens selection must be deliberate and documented (see `DECISIONS.md` ADR-011).
  3. **Do not silently switch lenses or camera devices in a way that produces unexpected image-quality changes.** Constituent-device switching inside a virtual multi-camera device is acceptable only where it matches user-visible zoom intent and is documented.
  4. Automatic selection behaviour must consider: requested zoom; available camera devices; focal length; stabilization; low-light behaviour; device capabilities; continuity of the preview/capture experience.
* **Interaction with §1.5:** The lens capsule (`.5`, `1x`, `2`, `3x`) is the user-visible expression of this policy; the mapping from each pill to a physical device/zoom factor is device-dependent and resolved at runtime.
* **Acceptance Criteria:** For each supported device generation, the pill → device/zoom mapping is documented, and a lens switch never changes capture format, colour space, or maximum photo dimensions without the user-visible zoom having changed.

---

#### Feature: Native Capability Preservation (FIDELITY-09)
* **Purpose:** Keep Apple's capture intelligence switched on.
* **Requirement:** Do not unnecessarily disable Apple's supported capture features. Preserve appropriate native capabilities for: stabilization; autofocus; exposure; HDR; low-light capture; computational photography.
* **Disable-with-justification rule:** If any native capability is intentionally disabled, the following must be documented in `DECISIONS.md`:
  1. **why** it is disabled;
  2. **what quality tradeoff** it introduces;
  3. **why the product requires** that tradeoff.
* **No quality-affecting camera configuration may be introduced casually.** Configuration that touches capture quality requires a decision record, not a commit message.
* **Acceptance Criteria:** A reviewer can enumerate every non-default capture setting and find a matching justification.

---

#### Feature: Preview / Capture Consistency (FIDELITY-10)
* **Purpose:** The user must receive composition guidance based on what they are actually framing.
* **Prohibited outcome:**
  > *"The coaching system says the composition is correct, but the saved photograph has a materially different crop or framing."*
* **Phase 2/3 must explicitly validate:** preview aspect ratio; sensor/capture aspect ratio; crop behaviour; orientation; front/back camera differences (including mirroring); field-of-view differences; stabilization crop where applicable.
* **Coordinate-system requirement:** The composition engine's normalized coordinate system must remain consistent with the **actual captured image**. The engine (Phase 1) is geometry-pure and unchanged by this requirement; the services layer is responsible for supplying `CompositionParams` already referenced to capture geometry, and for reconciling any preview-vs-capture crop or FOV difference before normalization (§1.2).
* **Acceptance Criteria:**
  * A capture taken at $\ge 85\%$ match score has the coached subject anchor within the same normalized tolerance band in the *saved photograph* as reported in the live HUD.
  * Front-camera captures maintain the same relationship (mirroring handled explicitly, not incidentally).

---

#### Feature: Image-Quality Regression Validation (FIDELITY-11)
* **Purpose:** Establish a repeatable image-quality validation strategy before the camera implementation is declared complete.
* **Device-first requirement:** Testing must be performed on **physical iPhones**. **The Simulator must not be used for camera-quality validation**, and no Simulator-based camera testing is to be introduced into the implementation plan.
* **Minimum validation matrix (where available):** **iPhone 14**, **iPhone 16**.
* **Method:** Compare Camsthetics captures against the highest-quality appropriate capture path available through Apple's native APIs, same scene, same lighting, same lens/zoom, back-to-back.
* **Evaluate:** resolution; detail; sharpness; noise; dynamic range; highlight retention; shadow detail; colour; HDR behaviour; field of view; crop; orientation; stabilization; metadata; file format; file size; capture latency.
* **Honesty requirement:** **Do not claim "native-quality" merely because the image looks acceptable.** Document measurable differences where practical (dimensions, format, byte size, metadata diff, and measured latency at minimum).
* **Acceptance Criteria:** A written comparison record exists per device and per evaluated dimension, with any deviation either fixed or explicitly accepted with rationale.

---

#### Known Platform Limitations (Honest Claims)

Apple's first-party Camera app uses proprietary capture and processing behaviour that is not fully exposed to third-party applications. Camsthetics therefore makes the following **precise** claim, and no stronger one:

> **"Use Apple's highest-quality supported third-party capture APIs and avoid introducing additional quality loss in Camsthetics."**

Areas where public API cannot guarantee equivalence with Apple's Camera.app (to be re-verified on device during Phase 2.0, not assumed):

| Area | Nature of the limitation |
|---|---|
| **Computational photography stages** | Smart HDR / Deep Fusion-class processing is applied by the system according to its own conditions and quality-prioritization hints. Third-party apps request quality prioritization; they do not drive the pipeline directly, and cannot force a specific stage to run. |
| **Night mode / long multi-frame low-light capture** | Not exposed as a directly controllable third-party capability equivalent to Camera.app's user-facing Night mode control. |
| **Photographic Styles and first-party tuning** | Apple's Camera.app rendering intent and per-device tuning are not guaranteed to be available or reproducible through public capture APIs. |
| **Zero-shutter-lag / responsive-capture behaviour** | Availability and effect are device-, format-, and iOS-version-dependent; these are opt-in properties whose support must be queried at runtime. |
| **Maximum photo dimensions (e.g. 48MP-class sensors)** | Availability depends on device, active format, selected codec, and iOS version; must be queried and configured at runtime rather than assumed. |
| **Stabilization crop and preview/capture FOV** | The relationship between preview FOV and final capture FOV varies by mode and stabilization state; it must be measured per device rather than assumed to be identity (see FIDELITY-10). |

**Camsthetics does not claim to reproduce Apple's proprietary Camera.app computational photography pipeline bit-for-bit.** Where a gap is measured, it is documented (FIDELITY-11), not marketed away.
