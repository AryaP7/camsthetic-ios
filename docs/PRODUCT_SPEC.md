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
