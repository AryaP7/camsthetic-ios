# Camera Hardware Quality Decision System — Research

**Status:** Research complete for what's measurable in Phase 2. Decision engine
**not implemented** — most decisions require subject/scene understanding
(Vision/Motion), which is explicitly Phase 2.3+ scope.
**Device:** physical iPhone 16 (`iPhone17,3`), `.builtInDualWideCamera`
(Ultra Wide + Wide, no telephoto — base-model topology). No Simulator used
anywhere in this investigation.
**Method:** every number below was read directly off `AVCaptureDevice`/
`AVCaptureDevice.Format` on the physical device via a temporary, read-only
diagnostic (`debugQualityDecisionResearch()`), never assumed or hard-coded,
then the diagnostic was deleted. Where a property is model-specific, that's
called out — nothing here is hard-coded against "iPhone 16" in production
code; the underlying `LensSelection`/`CameraService` derivation already
reads these values at runtime for whatever device it's on.

---

## 1. Preview investigation — closed

`contentsScale` bug (1.0 → 3.0) is the confirmed, fixed, human-validated
result. No further preview work in this pass — see the prior checkpoint's
report for full detail. Not revisited here.

---

## 2. Lens/zoom quality model (Part 3)

### 2.1 Topology (this device)

| Constituent | Device type | Raw entry factor | Display label |
|---|---|---|---|
| [0] | `builtInUltraWideCamera` | 1.0 | **0.5×** |
| [1] | `builtInWideAngleCamera` | 2.0 (switch-over) | **1×** |

No telephoto constituent exists on this specific unit (confirmed via
`constituentDevices` — base iPhone 16, not Pro). `maxAvailableVideoZoomFactor`
= 189.0 raw = **94.5× display** (relative to the Wide entry factor, 2.0) —
this is entirely digital zoom on the Wide constituent past display-1×; there
is no optical constituent above it on this hardware.

### 2.2 The actual crossover data (not assumed)

| Property | Measured value | Meaning |
|---|---|---|
| `secondaryNativeResolutionZoomFactors` | **[4.0] raw = 2.0× display** | At exactly display-2×, this device's Wide sensor switches to a **secondary native pixel-sampling mode** — genuine sensor-level detail, not digital upscaling. This is Apple's public-API surface for the "Fusion 2×" capability iPhone 16 (base) ships with a 48MP main sensor specifically to provide. |
| `videoZoomFactorUpscaleThreshold` | 1.0 raw (the format's own minimum) | Read literally, this format begins upscaling immediately above its floor. This is a genuinely surprising value for a max-resolution photo format and needs cross-validation against a second device/format before being trusted as a general rule — flagged as **low-confidence**, not used to drive any decision below. |
| `systemRecommendedVideoZoomRange` | **1.0...20.0 raw = 0.5×...10× display** | Apple's own, quality-informed, per-format recommended UI zoom range (iOS 18+ API). Notably **narrower** than the hardware ceiling (94.5×) — Apple itself does not recommend the top ~90× of range this device technically allows. |

### 2.3 What this answers, concretely, for THIS device

The "optical vs. digital crop" question the brief poses (1× native crop vs.
2×/telephoto constituent vs. digital zoom) has a **device-specific answer**
here because there is no telephoto constituent to compare against. The real
crossover on this hardware is:

- **display 0.5× → 1×**: a genuine optical constituent switch (Ultra Wide →
  Wide), confirmed twice now — once via the entry-factor math, once via
  EXIF `LensModel` on an actual capture. Not a crop of any kind.
- **display 1× → 2×**: digital zoom on the Wide constituent, but landing
  exactly on a **secondary-native-resolution boundary** at 2× — meaning 2×
  is measurably better than what pure interpolation would produce at that
  same factor, without being a second physical lens.
- **display 2× → ~10×**: continued digital zoom, within Apple's own
  recommended range.
- **display >10× (up to 94.5×)**: digital zoom outside Apple's own
  recommended range — the hardware allows it (confirmed working, and you
  found it genuinely useful up to ~95×), but Apple's own API is telling us
  it's past the point Apple considers quality-justified.

This directly falsifies the naive "more optical/nominal zoom = better"
framing the brief warns against, and replaces it with device-reported,
measurable boundaries: **0.5×, 1×, 2×, and ~10× are the four quality-relevant
breakpoints on this specific unit** — not "0.5×/1×/2× lens buttons" as a flat
list.

### 2.4 What a future decision engine needs beyond this

`secondaryNativeResolutionZoomFactors` and `systemRecommendedVideoZoomRange`
are per-**format**, and this device only has one relevant photo-capable
format at max resolution — so today's answer is complete for this hardware.
On a **telephoto-equipped** iPhone, the same properties would need to be read
per-constituent's *own* format (each constituent has its own `formats` list)
to find that lens's secondary-native and upscale-threshold points too — the
code path (`device.formats`, filtered/matched by dimensions) already
generalizes to this without modification; it just wasn't exercised on
hardware that has a third lens.

---

## 3. Subject-distance / lens decision inputs (Part 4)

**What's actually available via public API, investigated (not implemented):**

| Signal | API | Availability here |
|---|---|---|
| Focus distance (proxy for subject distance) | `AVCaptureDevice.lensPosition` (0=near, 1=infinity, relative not metric) | ✅ readable, not calibrated to real-world distance |
| Focus confidence | `AVCaptureDevice.Format.autoFocusSystem`, `isFocusPointOfInterestSupported` | ✅ available; no direct "confidence score" API — only discrete `AVCaptureDevice.FocusMode`/point-of-interest |
| Subject size/position in frame | **Not from AVFoundation at all** — requires Vision (`VNDetectFaceRectanglesRequest`/`VNGeneratePersonSegmentationRequest`) or Core ML | ❌ Phase 2.3+ |
| True metric subject distance | **No public API on iPhone without LiDAR** (LiDAR models expose `AVDepthData` via `builtInLiDARDepthCamera`) — this iPhone 16 has no LiDAR | ❌ not available on this hardware at all |
| Lighting level | `AVCaptureDevice.iso`, `exposureTargetOffset`, `exposureDuration` (proxies) | ✅ readable in real time |
| Motion | **Not from AVFoundation** — needs Core Motion (`CMMotionManager`) for device motion, or Vision optical-flow for subject motion | ❌ Phase 2.3+ |

**Conclusion:** `lensPosition` + exposure signals are available *today*
without Vision/Motion, but neither gives real subject distance or motion —
only device-focus-state and lighting proxies. A real "should I switch lens
for this framing" decision needs Vision (subject detection/size) at minimum,
which is explicitly out of scope for this phase. **Not implementable now** —
correctly gated behind Phase 2.3.

---

## 4. Exposure decision investigation (Part 5)

**Measured, this device, current lighting:**

| Property | Value |
|---|---|
| ISO | 3072 (range 33–7392) |
| Exposure duration | 66ms ≈ 1/15s (range 15µs–1s) |
| `activeMaxExposureDuration` | **capped at 1/15s** by the system itself |
| `exposureTargetBias` | 0.0 (range ±8 EV) |
| `exposureTargetOffset` | −2.19 EV (transient, mid-adjustment at read time) |
| `isExposurePointOfInterestSupported` | true |

**Finding:** Apple's own auto-exposure already caps handheld exposure
duration at 1/15s on this device/format — i.e., it already refuses to go
slower than what's likely to hand-shake-blur, trading it for higher ISO
instead. This is exactly the "low light + moving subject → prioritize
shutter" behavior the brief hypothesizes we might need to add — **it's
already Apple's default behavior**, not a gap. The controls to do
differently (custom ISO/duration via `AVCaptureDevice.setExposureModeCustom`)
exist and are public, but a context-aware override (e.g. "stationary subject,
tolerate a slower shutter than Apple's default cap") would need to *detect*
"stationary" — which is a motion signal, Phase 2.3+.

**Controlled experiment design (not run — needs Phase 2.3 motion input):**
hold ISO/shutter fixed via `setExposureModeCustom`, compare a
tripod-stationary low-light shot at 1/15s-forced-ISO vs. Apple's auto choice
at the same scene, inspect noise/detail. Cannot be executed meaningfully
without a controlled rig and is deferred, not because it's hard to code, but
because there's no product signal yet ("is the subject stationary") to
condition on.

---

## 5. Focus decision investigation (Part 6)

| Property | Value | Relevance |
|---|---|---|
| `lensPosition` | 0.706 | Readable continuously |
| `isSmoothAutoFocusSupported` | **true** | Supported on this device |
| `isSmoothAutoFocusEnabled` | **false** (our current default — we never set it) | We're leaving it off |
| `isAutoFocusRangeRestrictionSupported` | true | Can restrict AF to near/far |
| `isFocusModeSupported(.locked)` | true | Focus lock available |

**Real finding:** `isSmoothAutoFocusEnabled` is `false` by default in our
current (photo-only) configuration. Smooth AF trades AF *speed* for less
visible focus-hunting/racking — the right trade for **video**, the wrong
trade for **stills** (where you want the fastest possible lock before
shutter). Since Camsthetics is still photo-only right now, leaving it off is
correct — **this becomes a real, concrete recommendation for the future
video/MotionShoot pipeline**: enable `isSmoothAutoFocusEnabled = true` only
on the video-capture configuration, never on the photo path. Not implemented
now (no video path exists yet) — recorded for Part 11/13.

---

## 6. White balance decision investigation (Part 7)

| Property | Value |
|---|---|
| `deviceWhiteBalanceGains` | r=1.46 g=1.0 b=2.70 |
| `isLockingWhiteBalanceWithCustomDeviceGainsSupported` | **false** |
| `isWhiteBalanceModeSupported(.locked)` | true |

**Real finding, negative result:** this device does **not** support locking
white balance to custom device gains — only the standard
`.locked`/`.autoWhiteBalance`/`.continuousAutoWhiteBalance` modes are
available; there is no fine-grained gain control here. Any future "consistent
skin tones across a portrait session" feature is limited to **lock current
WB** (call `.locked` once AWB has converged) — not custom gain tuning.
**This is a genuine public-API ceiling, not a gap in our implementation** —
documented here so it isn't "rediscovered" and chased later.

---

## 7. Stabilization decision investigation (Part 8)

**Measured at the CURRENT (max-resolution photo) active format:**

| Mode | Supported at 4032×3024 |
|---|---|
| `.off` | ✅ |
| `.standard` | ❌ |
| `.cinematic` | ❌ |
| `.cinematicExtended` | ❌ |
| `.auto` | ✅ |

**Real, concrete, actionable finding:** the higher-quality stabilization
modes (`.standard`/`.cinematic`/`.cinematicExtended`) are **not available at
all at this device's maximum photo resolution** — only `.off`/`.auto`.
Stabilization is a *connection*-level property (`AVCaptureConnection`, not
`AVCaptureDevice`) and matters primarily for **video**, not for
`AVCapturePhotoOutput` stills (Apple's still-image pipeline does its own
computational stabilization internally as part of Smart HDR/Deep Fusion,
already confirmed present via the gain-map data in every capture fidelity
check this session). **Implication for the future video pipeline:** a
high-quality video mode wanting real cinematic stabilization will need to
select a **lower-resolution video-oriented format** (e.g. one of the
1920×1440/3840×2160 formats already enumerated), not the max-res photo
format — this is a real, hardware-verified constraint to design MotionShoot
around, not an assumption.

---

## 8. Image-quality lab foundation (Part 9) — methodology, not executed

Plan for a controlled Camsthetics-vs-native comparison (not run yet — needs
two apps shooting the same physical scene back-to-back, which is a
deliberate human-in-the-loop test, not something to script):

1. **Fix:** one physical iPhone, one lens (state which), one static test
   scene with fine texture + text/edges + a highlight + a shadow region +
   moderate overall contrast, tripod or braced phone (remove hand-shake as a
   variable), same framing (mark phone position), same time (avoid lighting
   drift between shots).
2. **Shoot:** Camsthetics capture, then immediately native Camera capture,
   same settings where user-controllable (flash off, same zoom level).
3. **Compare** (pulled to Mac, inspected at 100%): fine detail/acutance,
   noise (crop a flat mid-tone region), highlight retention (crop the bright
   region, check for clipping), shadow detail (crop dark region, check
   crush/noise), color (compare a known-color patch if available), skin
   rendering (if a person is in frame), artifacts (banding, haloing, moiré),
   file size/dimensions/HDR gain-map presence (already known-identical from
   Phase 2.0/2.1), EXIF (lens/exposure parameters — confirms same
   constituent/settings were actually used for a fair comparison).
4. **Report** as a table, not a verdict — this project doesn't get to claim
   "beats Apple" without this table showing it, per your explicit rule.

Not executed in this pass — it needs your hands doing the actual paired
shots. I can run it as a dedicated checkpoint whenever you want it.

---

## 9. Computational photography research (Part 10)

**What data do we actually receive?** One `AVCapturePhoto` per capture —
already fully processed by Apple's Smart HDR/Deep Fusion pipeline
(confirmed: HDR gain map present in every capture this session, P3 color,
8bpc). We do **not** receive intermediate/raw frames from that pipeline —
Apple's computational photography is a black box between shutter press and
`fileDataRepresentation()`.

**What's technically feasible with public APIs, if we wanted to build our
own separate pipeline** (via `AVCaptureVideoDataOutput`, *parallel* to, never
replacing, the photo path):
- **Multi-frame capture:** yes — repeated `capturePhoto()` calls or a
  `AVCaptureVideoDataOutput` burst of `CVPixelBuffer`s.
- **Frame alignment:** feasible via Vision (`VNTranslationalImageRegistrationRequest`/`VNHomographicImageRegistrationRequest`) or Core Image, CPU/GPU cost non-trivial.
- **HDR fusion / temporal denoising:** feasible via Core Image (`CIFilter` compositing across aligned frames), significant engineering, and would need to independently prove it beats what Apple's own Smart HDR (already running on every capture) provides — high risk of just re-deriving a worse version of what we already get for free.
- **Motion-aware frame selection:** feasible with Vision-based motion/sharpness scoring across a buffered `AVCaptureVideoDataOutput` stream — this is precisely the **MotionShoot** mechanism (§11).
- **Detail preservation / tone mapping / controlled sharpening:** feasible via Core Image; explicitly **not attempted** anywhere in this pass per the hard rule (no arbitrary sharpening) and because Apple's pipeline already does tone-mapping (Smart HDR) — redoing it without evidence of a gap would be exactly the "manufactured fix" the brief prohibits.

**Distinction from Apple's private stack, made explicit:** anything we build
here operates on `CVPixelBuffer`s from a **separate, parallel**
`AVCaptureVideoDataOutput` — it can never touch, replace, or feed into
`AVCapturePhotoOutput`'s own pipeline (structurally impossible via public
API, confirmed since Phase 2.0). Any future computational feature is
therefore **an additional, clearly-labeled processed output**, never a
substitute for the one authentic `fileDataRepresentation()` capture — which
protects the fidelity invariant permanently, by construction, not by policy.

**Not implemented now** — no proven gap to fix, and the infrastructure
(Vision-based alignment/scoring) is Phase 2.3+ scope.

---

## 10. Video quality foundation (Part 11)

From the full format enumeration (49 formats on this device, captured
earlier this session) plus this pass's stabilization/codec data:

| Capability | Ceiling on this device |
|---|---|
| Max video resolution | 3840×2160 (4K) |
| Max frame rate at 4K | 60fps (HDR-supported variant exists) |
| Max frame rate overall | 60fps (available at up to 1920×1440) |
| HDR video | Supported at most resolutions incl. 4K |
| Color space | P3_D65 confirmed (photo path); video formats also expose `supportedColorSpaces` per-format |
| Codec | **HEVC (`hvc1`) only — no ProRes** (confirmed via `AVCaptureMovieFileOutput.availableVideoCodecTypes`) |
| Stabilization at 4K/high-res | Needs re-verification per-format — confirmed only `.off`/`.auto` at the *photo* format; a video-oriented 4K format was not individually re-tested for `.cinematic` support and should be before MotionShoot design finalizes |
| `AVCaptureMovieFileOutput` | Available, standard path for file-based recording |
| `AVAssetWriter` | Available for custom pixel-buffer-to-file pipelines (needed if MotionShoot wants to write only *selected* frames, not a continuous file) |

**Real, hardware-confirmed finding:** this is a **base iPhone 16, not Pro**
— ProRes is unavailable at the codec level, full stop, regardless of
software configuration. Any future "cinematic video" positioning needs to be
scoped to HEVC/4K/60fps/HDR, not ProRes, **on this specific unit** (a Pro
model would need its own re-verification — the code path already reads this
per-device, nothing hard-coded).

---

## 11. Future Decision Engine — candidate table (Part 12)

| Decision | Inputs required | Public API | This device supports | Measurement method | Expected benefit | Confidence | Difficulty | Recommendation |
|---|---|---|---|---|---|---|---|---|
| Lens/zoom label correctness | `constituentDevices`, entry factors | ✅ | ✅ | Done (EXIF-verified) | High — was a real bug | **Confirmed, done** | Low | **Implemented** |
| Soft-limit zoom UI to `systemRecommendedVideoZoomRange` | Format property | ✅ (iOS 18+) | ✅ (1.0–20.0 raw) | Read once | Medium (quality) vs. user delight tradeoff — you explicitly liked going past it | Medium | Low | **Product decision needed, not unilaterally implemented** |
| Prefer secondary-native-resolution zoom points as "snap targets" in continuous zoom | `secondaryNativeResolutionZoomFactors` | ✅ | ✅ ([4.0] raw = 2× display) | Read once | Real — snapping to a known-non-upscaled point is strictly better than landing 0.1× off it | High | Low-Medium (UI gesture snap logic) | **Good Phase 2.2 candidate** |
| Lens selection by subject distance/framing | `lensPosition` + Vision subject size | ❌ (Vision) | Partial | N/A | High if built well | Low (unbuilt) | High | Phase 2.3+ |
| Context-aware exposure (motion/stationary) | Motion signal | ❌ (Core Motion/Vision) | Partial (exposure controls exist) | N/A | Apple's default already handles the obvious case (1/15s cap confirmed) | Low (unproven gap) | High | Phase 2.3+ |
| Smooth AF for video | `isSmoothAutoFocusEnabled` | ✅ | ✅ | Confirmed off by default | High for video specifically | High | Low | **Video-pipeline candidate (not yet, no video path)** |
| WB custom-gain consistency | Custom gains | ❌ on this device | **Not supported** | Confirmed | N/A | N/A | N/A | **Impossible on this hardware** |
| Cinematic stabilization for video | Format-specific | ✅ | Only at non-photo formats | Confirmed at photo format only | High for MotionShoot | Medium (needs re-test at video format) | Medium | Video-pipeline candidate |
| ProRes video | Codec | ✅ API, ❌ hardware | **Not supported (base model)** | Confirmed | N/A | N/A | N/A | **Impossible on this unit** |
| Multi-frame computational photography | `AVCaptureVideoDataOutput` + Vision alignment | ✅ (build ourselves) | Feasible | Not built | Unproven vs. Apple's existing Smart HDR | Low | High | Phase 2.3+ research, not now |

---

## 12. MotionShoot connection (Part 13)

Results from this investigation that directly feed MotionShoot later:

- **Stabilization ceiling is format-dependent** (§7) — MotionShoot's video
  capture must select a stabilization-capable format, not the current
  photo-only max-resolution format. Today's `CameraService` already
  separates "capture-only" configuration from anything video-shaped
  (documented in the file's own header as future scope) — nothing here
  blocks that; a MotionShoot-specific session configuration is a clean
  addition, not a rework.
- **Smooth AF should be video-path-only** (§5) — confirms the future video
  configuration needs its own device-property setup distinct from the photo
  path's (which correctly wants fast AF, not smooth AF).
- **`AVAssetWriter` + `AVCaptureVideoDataOutput`** (§10) is the right
  mechanism for "buffer frames, score them, keep only the best" — exactly
  MotionShoot's "candidate moments → curated stills" pipeline shape. Nothing
  in today's architecture (preview and capture are already structurally
  independent, per ADR-009) blocks adding this as a third, parallel
  consumer later.
- **No ProRes on this unit** (§10) sets a real ceiling on what "high-quality
  video" can mean for testing on this specific hardware — MotionShoot design
  should not assume ProRes availability without checking the deployment
  device.

Today's camera architecture does not accidentally block any of this — the
session/output separation this project has maintained since Phase 2.0
(ADR-009) is exactly what MotionShoot's "parallel analysis consumer" shape
needs.

### 12.1 Product framing & roadmap position (Future — NOT Implemented)

This subsection records the product concept and its dependency chain per
`DECISIONS.md` ADR-014 and `PRD.md` §5.2. **Nothing here authorizes
implementation** — no `AVFoundation` code, no Vision code, no UI, no
`CameraService` changes, no prototype, no tests. See §12 above for what is
already hardware-verified; this is the product/UX layer on top of it.

**Feature name:** "MotionShoot" / "Intelligent Photoshoot Mode."

**Goal:** the user records a short, high-quality video while a person/model
freely poses or moves. Camsthetics analyzes the temporal sequence and
intelligently selects a set of distinct, aesthetically strong moments,
producing individual still photographs from the best moments — an
intelligent photoshoot, not a video-frame dump.

**Core product idea (intended experience):**

```
User selects MotionShoot
        ↓
User records/poses for ~10–30 seconds
        ↓
Camsthetics continuously analyzes the sequence
        ↓
Detect meaningful pose/expression/composition changes
        ↓
Score candidate moments
        ↓
Select the strongest DISTINCT moments
        ↓
Produce a curated set of photographs
```

**Future decision system should consider:** subject/pose quality, face
visibility, facial expression, eye state, subject sharpness, motion blur,
camera motion, composition, framing, lighting/exposure quality,
highlight/shadow conditions, subject position, pose uniqueness, temporal
diversity, and similarity between candidate frames.

**Deliberate deduplication is a requirement, not an optimization:** the
system must avoid returning many near-identical frames —

```
Pose A            → select
Pose A + 2 frames → reject as redundant
Pose B            → select
Pose C            → select
Pose C + 3 frames → reject as redundant
Pose D            → select
```

— the final result must contain genuinely different photographic moments.

**Future architectural concept** (extends §12's findings into product shape):

```
High-quality video capture
         ↓
Live frame analysis / Vision
         ↓
Subject + pose + face + motion understanding
         ↓
Candidate-frame generation
         ↓
Photographic quality scoring
         ↓
Temporal diversity / deduplication
         ↓
Best-moment selection
         ↓
Still-image extraction
         ↓
Optional Camsthetics image-quality/rendering pipeline
         ↓
Curated photo set
```

**Video quality requirement:** when eventually implemented, investigate and
use the highest-quality practical public-API video pipeline for the target
device — resolution, frame rate, active format, exposure/shutter strategy,
ISO, focus, white balance, stabilization, HDR where supported, codec,
bitrate/quality, color space, ProRes where supported (confirmed **not**
supported on the current lab unit, §10/§13), and `AVCaptureVideoDataOutput`
vs. movie-file workflows. A 4K video frame must not be treated as equivalent
to a native high-resolution still photograph — this distinction must stay
explicit in the eventual detailed spec.

**Image quality principle:** the feature must not simply upscale video
frames and present them as containing more photographic information than
was captured. Any future enhancement/reconstruction pipeline must prioritize
genuine captured detail, natural photographic appearance, controlled
denoising, technically-defensible motion/deblur handling, highlight/shadow
preservation, color fidelity, skin rendering, and detail preservation —
avoiding hallucinated/fake detail unless a future feature explicitly and
transparently opts into an artistic generative mode.

**Product differentiation:** normal photography asks *"is this frame
good?"*; MotionShoot asks *"across this entire sequence, which moments would
make the best photographs?"* — turning time/movement into another dimension
of the photographic decision system. Candidate flagship differentiator;
final UX wording (e.g. "Pose freely" / "Move naturally" prompts, optional
live coaching, review/select/reject of generated photographs) intentionally
not locked yet.

**Relationship to the future Camsthetics Decision Engine** (`PRD.md` §5.2):
MotionShoot shares the same decision-system philosophy as normal-photo
capture, applied over time instead of a single instant:

| Normal Photo | MotionShoot |
|---|---|
| Understand scene | Understand scene over time |
| Choose optimal camera strategy | Understand subject/pose/motion |
| Detect optimal capture moment | Evaluate many candidate moments |
| Capture best photograph | Select the best DISTINCT moments → produce a curated photograph set |

**Dependency chain** (also recorded in `IMPLEMENTATION_PLAN.md` Phase 8):

```
Camera fidelity foundation (Phase 2.0/2, ADR-009/013 — done)
        ↓
Video capture pipeline (future — not started)
        ↓
Analysis/Vision (Phase 3 — first pass built, not device-verified; §12 above)
        ↓
Camsthetics Decision Engine (future — not started, PRD.md §5.2)
        ↓
MotionShoot
        ↓
Intelligent frame selection
        ↓
Image-quality/rendering pipeline
```

**Validation requirement:** implementation requires future controlled
image-quality testing on physical hardware before any claim that this
feature outperforms Apple's Camera — per ADR-012/ADR-013's evidentiary
standard. No such claim is made here.

---

## 13. Assumptions disproven / confirmed impossible

**Disproven:**
- "0.5×/1× is just cosmetically wrong, no deeper issue" — the crossover
  investigation shows display-2× lands exactly on a real sensor-mode
  boundary (`secondaryNativeResolutionZoomFactors`), not an arbitrary
  digital-zoom point — the zoom quality story is richer than "2 lenses,
  everything else is crop."
- "Apple's exposure defaults are a black box we might improve on" — the
  1/15s handheld-shutter cap shows Apple's default is already doing the
  sensible low-light/motion-blur tradeoff the brief hypothesized as a
  potential improvement.

**Confirmed genuinely impossible on this hardware/API surface:**
- Custom white-balance gain locking (`isLockingWhiteBalanceWithCustomDeviceGainsSupported = false`).
- ProRes recording (codec list = `[hvc1]` only, base-model hardware ceiling).
- True metric subject distance without Vision/LiDAR (this unit has no LiDAR).
- Cinematic-grade stabilization at the current max-resolution photo format
  (only at lower-resolution video formats).

---

## 14. Status

- **Tests:** 100/100 passing.
- **Build:** physical-device build succeeds (iPhone 16, `iPhone17,3`, no Simulator).
- **Physical validation:** every number in this document was read from the
  actual device via a temporary diagnostic, then the diagnostic was deleted
  — production code carries no probe/scaffold residue from this pass.
- **Implemented this pass:** nothing beyond what was already confirmed in
  the preview-quality checkpoint (`contentsScale` fix). Every finding above
  that looked implementable turned out to require either a product decision
  (zoom range clamping) or Phase 2.3+ infrastructure (Vision/Motion/video
  pipeline) — implementing any of it now would be scope creep past the
  stated boundary, not a targeted fix.
- **Files changed this pass:** `docs/CAMERA_DECISION_RESEARCH.md` (new,
  this file). `CameraService.swift`/`PreviewValidationScaffold.swift` were
  temporarily modified for measurement and are back to their pre-pass state
  (diagnostic extension added and removed within this session).
- **Nothing committed.**
