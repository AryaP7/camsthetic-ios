# Device-Agnostic Camera Quality Model + Decision Engine Foundation

**Status:** Architecture design + one real, shipped, device-agnostic
implementation (§0). Full decision engine **not built** — correctly gated
behind Vision/Motion (Phase 2.3+), per this document's own findings.
**Reads alongside:** `docs/CAMERA_DECISION_RESEARCH.md` (the iPhone 16 lab
measurements this design generalizes away from).
**Physical device used throughout:** iPhone 16 (`iPhone17,3`), no Simulator.
**Tests:** 106/106 passing. **Build:** PASS. **Nothing committed.**

---

## 0. What's actually implemented this pass (not just designed)

Everything else in this document is architecture/research. This section is
real, shipped, physically-validated code — proof the "query → model →
measure → decide" principle works in practice, not just on paper.

**Intelligent zoom snap** (`LensSelection.snapToNativeResolution` in
`CameraService.swift`, wired into the pinch-zoom gesture in
`PreviewValidationScaffold.swift`):

- Reads `CameraService.secondaryNativeResolutionZoomFactors` — the RAW
  `AVCaptureDevice.Format.secondaryNativeResolutionZoomFactors` array for
  **whichever device/format is actually active at runtime**. Nothing here
  is `[4.0]`, `"iPhone 16"`, or `"2.0"` — it's `device.activeFormat
  .secondaryNativeResolutionZoomFactors`, read fresh every session.
- On a device/format reporting **no** secondary-native points (empty array
  — the common case, including every non-Fusion iPhone and most formats on
  Fusion-capable ones), `snapToNativeResolution` is a **provable no-op** —
  covered by `testSnapToNativeResolutionIsNoOpForEmptyFactors`.
- On a device/format that **does** report points, a live pinch gesture
  landing near one snaps to it and gives haptic feedback.
- **Physically verified on-device**, not assumed: live console telemetry
  during an actual pinch gesture showed it snapping to `target=4.0` (this
  unit's one reported point) and holding there for the whole dwell window,
  symmetrically in both zoom directions, then releasing cleanly outside the
  tolerance band. Haptic (`UIImpactFeedbackGenerator`) confirmed invoked at
  exactly the two snap-entry transitions.
- One real bug found and fixed in the process: the haptic generator was
  first stored as a plain `let` on the SwiftUI View struct, which SwiftUI
  reconstructs on nearly every gesture-driven state change — producing a
  fresh, never-`prepare()`d generator almost every frame, which reliably
  produces no physical tap. Fixed by moving it to `@State` (persists across
  reconstructions). Documented in the code as a reusable lesson.

This is the concrete instance of Parts 1–3's "query → model → decide"
principle: **capability discovered** (the array) → **candidate quality
signal** (a point on it means non-upscaled detail) → **decision** (snap the
live gesture there) — with zero hard-coded device values anywhere in the
path.

---

## A. Device-agnostic capability model

### Design

A `CameraCapabilities` snapshot, built once per session-configuration by
querying `AVCaptureDevice`/`AVCaptureDevice.Format` — never asserted, never
keyed by device model string. Every field distinguishes **supported /
unsupported / unavailable-for-current-format** rather than collapsing
"false" and "don't know" into the same case, per the explicit requirement.

```swift
/// A tri-state capability read, because "not supported" and "not
/// applicable to the currently active format" are different facts a
/// decision needs to tell apart — collapsing them loses information a
/// future format switch could recover.
public enum CapabilityState<Value: Sendable>: Sendable {
    case supported(Value)
    case unsupported
    case unavailableForCurrentFormat
}

/// One physical or virtual capture device, as actually discovered —
/// never assumed present. `constituents` is empty for a non-virtual
/// device; its count/roles are whatever THIS device reports, not a
/// fixed list.
public struct CameraDeviceCapabilities: Sendable {
    public let deviceType: AVCaptureDevice.DeviceType
    public let position: AVCaptureDevice.Position
    public let isVirtualDevice: Bool
    public let constituents: [ConstituentCapabilities]
    public let zoom: ZoomCapabilities
    public let formats: [FormatCapabilities]
    public let activeFormatIndex: Int
}

public struct ConstituentCapabilities: Sendable {
    public let deviceType: AVCaptureDevice.DeviceType
    public let localizedName: String
    /// Entry zoom factor (raw, same space as `videoZoomFactor`) — where
    /// this constituent becomes the active one. Derived, not asserted.
    public let entryZoomFactor: CGFloat
}

public struct ZoomCapabilities: Sendable {
    public let minAvailable: CGFloat
    public let maxAvailable: CGFloat
    public let switchOverFactors: [CGFloat]
    public let secondaryNativeResolutionFactors: [CGFloat]
    public let upscaleThreshold: CGFloat?
    public let systemRecommendedRange: ClosedRange<CGFloat>?  // iOS 18+ only — nil, not false, below that
}

public struct FormatCapabilities: Sendable {
    public let dimensions: CMVideoDimensions
    public let frameRateRanges: [ClosedRange<Float64>]
    public let isVideoHDRSupported: Bool
    public let supportedColorSpaces: [AVCaptureColorSpace]
    public let supportedMaxPhotoDimensions: [CMVideoDimensions]
    public let isVideoBinned: Bool
    public let isMultiCamSupported: Bool
    public let stabilizationModes: CapabilityState<[AVCaptureVideoStabilizationMode]>
    public let videoCodecs: [AVVideoCodecType]  // populated via a probe output, see §H
}
```

### How this works across iPhone 16 and newer devices

Every field above is populated by a query, never a switch on model. A
future iPhone with a telephoto constituent produces a `constituents` array
of 3 with that constituent's own `entryZoomFactor`, `formats`, and — if that
future hardware exposes its own secondary-native points — its own non-empty
`secondaryNativeResolutionFactors`. **No code path changes**; the same
struct, same population logic, just different runtime values. A future
iPhone that drops ProRes-unavailability (a Pro model) shows a longer
`videoCodecs` list from the exact same probe. Nothing here needs to know it
exists yet.

---

## B. Camera configuration model

### Design

A `CameraConfigurationCandidate` is a hypothesis: "if we select this
raw zoom factor / constituent / format, here's what we'd get." Candidates
are **generated from `CameraCapabilities`**, never hard-coded as a fixed
enum of "Ultra Wide / Wide / Wide-crop / Tele" — a device with 2
constituents generates 2 optical candidates + N digital-crop candidates
between/around them; a device with 3 generates 3 + N; a device with none
(single-lens) generates 1.

```swift
public struct CameraConfigurationCandidate: Sendable {
    /// The RAW zoom factor this candidate would set — always in the same
    /// coordinate space as `videoZoomFactor`, never a display label.
    public let rawZoomFactor: CGFloat
    public let sourceConstituent: ConstituentCapabilities
    /// Which quality regime this factor falls into for the source
    /// constituent's active format — derived from
    /// ZoomCapabilities.upscaleThreshold / secondaryNativeResolutionFactors
    /// / switchOverFactors, never asserted per-device.
    public let regime: ZoomRegime
    public let expected: QualityEstimate  // §D
}

public enum ZoomRegime: Sendable {
    /// Below any upscale threshold for this constituent/format — a true
    /// sensor crop, no interpolation.
    case nativeCrop
    /// Exactly at (within tolerance of) a discovered
    /// secondaryNativeResolutionFactors point.
    case secondaryNativeResolution
    /// Above the upscale threshold — genuine digital interpolation.
    case digitalUpscale
}
```

`CameraConfigurationCandidate` generation, conceptually:

```
for each constituent in capabilities.constituents:
    candidate(rawZoomFactor: constituent.entryZoomFactor, regime: .nativeCrop)
    for each point in constituent's active format's secondaryNativeResolutionFactors:
        candidate(rawZoomFactor: point, regime: .secondaryNativeResolution)
    // .digitalUpscale candidates only synthesized on demand for a
    // requested framing that falls between the above — never
    // enumerated exhaustively; there are infinitely many.
```

This directly satisfies "do not hard-code these exact candidates" — the
candidate LIST's cardinality and content are entirely a function of what
`CameraCapabilities` discovered.

---

## C. Intelligent zoom model

**How the engine chooses**, for an arbitrary supported device:

1. Given a requested framing (a display-relative zoom target, e.g. "≈2×" —
   itself computed from `LensSelection.displayFactor`'s inverse), generate
   every `CameraConfigurationCandidate` within a reasonable band of it.
2. Score each with the Quality Model (§D) using whatever inputs are
   actually available right now (§F — today, that's lighting/exposure and
   `lensPosition`; after Vision, add subject size/distance/motion).
3. Select the highest-scoring candidate; **only** fall back to
   `.digitalUpscale` when no `.nativeCrop`/`.secondaryNativeResolution`
   candidate exists near the request.

This directly generalizes the three example decisions in the prompt without
hard-coding any of them as rules — they're **outcomes** of the scoring:

- *"1× sensor crop preserves more detail than a 2× digital crop"*: true
  whenever a `.nativeCrop` candidate's `expected.detail` exceeds a farther
  `.digitalUpscale` candidate's — a consequence of the upscale-penalty term
  (§D), not a coded rule.
- *"switch to telephoto for a distant subject"*: true when the telephoto
  constituent's `.nativeCrop` candidate scores higher **once
  `expected.detail`/`focusReliability` for that specific candidate,
  informed by real subject-distance/size data, say so** — impossible today
  without Vision (§F), by design not implemented as a guess.
- *"prefer the brighter primary + crop in low light"*: true when a
  telephoto/secondary constituent's smaller aperture (inferable from its
  own format's exposure range, §D) drives its `expected.noise`/
  `expected.motionBlur` estimate worse than the primary's crop candidate,
  under the *currently measured* lighting (`iso`/`exposureTargetOffset`,
  available today).

No device is special-cased. A device with only one constituent (§0's
iPhone 16 topology) simply never generates a competing-constituent
candidate — the model still runs, it just has fewer candidates to choose
from, which is the correct degenerate case.

---

## D. Quality model

| Term | Definition | How obtained today | Confidence |
|---|---|---|---|
| `expected_detail` | Effective resolved detail at the target framing, accounting for native vs. upscaled sampling | **Runtime-derived**: `ZoomRegime` (native crop > secondary-native ≈ native crop > digital upscale, roughly by upscale factor²) | Medium — directional, not calibrated to a number |
| `expected_noise` | Sensor noise at expected exposure settings | **Inferred**: from `ISO`/`exposureDuration` at the candidate's constituent (a physically smaller sensor/aperture constituent will need higher ISO for equal exposure — derivable from `format.minISO/maxISO` + current lighting) | Low-Medium — needs calibration (§E) |
| `expected_motion_blur` | Blur risk given required shutter speed and subject/camera motion | **Partially available today** (required shutter speed from exposure state), **needs Motion** for subject/camera motion magnitude | Low until Motion lands |
| `expected_focus_reliability` | Likelihood of accurate focus lock | **Runtime-derived, partial**: `AVCaptureDevice.FocusMode`/lensPosition stability over recent frames; real subject-tracking confidence **needs Vision** | Low-Medium |
| `expected_dynamic_range` | Highlight/shadow retention | **Runtime-derived**: `activeFormat.isVideoHDRSupported` + current `exposureTargetOffset` (scene contrast proxy) | Medium |
| `expected_upscaling_penalty` | Quality cost specifically from interpolation | **Directly computable** from `ZoomRegime` + how far past `upscaleThreshold` the candidate sits | High — this is the one term with a clean public-API-derived formula |

**Directly measured** (no estimation needed): `ISO`, `exposureDuration`,
`lensPosition`, `activeFormat` HDR/dimension/rate properties.
**Runtime-derived** (computed from measured values via a documented
formula): `expected_upscaling_penalty`, zoom regime classification.
**Empirically calibrated** (needs the methodology in §E, not yet run at
scale): `expected_detail`/`expected_noise` as actual numbers, not just
directional comparisons.
**Inferred** (a proxy standing in for the real signal): motion, subject
distance, until Vision/Motion land.
**Unavailable** today: true subject distance (no LiDAR on this device
family's non-Pro tier — confirmed in `CAMERA_DECISION_RESEARCH.md` §6),
genuine perceptual detail/noise scores (need actual pixel-level image
analysis of paired captures, §E's lab).

---

## E. Empirical calibration — methodology, not constants

The iPhone 16 measurements in `CAMERA_DECISION_RESEARCH.md` become a
**repeatable procedure**, not stored numbers, by structuring calibration as:

```swift
/// One calibration run's raw inputs — never hand-typed, always captured
/// from a real device via the image-quality lab (docs §8 there).
public struct CalibrationSample: Sendable {
    public let deviceCapabilities: CameraDeviceCapabilities  // what WAS measured, this run
    public let candidate: CameraConfigurationCandidate
    public let measuredDetailScore: Double   // from paired-photo lab analysis
    public let measuredNoiseScore: Double
    public let lightingConditionEV: Double
}

/// A calibration PROFILE is keyed by discovered capability shape
/// (constituent count/roles, format characteristics), NEVER by device
/// model string — two different iPhones with the same discovered
/// topology get the same profile; a future device with a topology never
/// seen before falls back to the directional-only model in §D rather
/// than guessing a number.
public struct CalibrationProfile: Sendable {
    public let capabilityShapeKey: String  // derived from topology, not "iPhone 16"
    public let samples: [CalibrationSample]
}
```

**The methodology** (repeatable on any future device family): run the §9
paired-comparison lab across the framing boundaries `CameraConfigurationCandidate`
generation identifies as interesting (constituent switch-overs, secondary-native
points, and a few pure-digital-zoom points in between) for THAT device, store
results keyed by its discovered `capabilityShapeKey`, never by model name. A
brand-new topology (e.g. a future 4-lens device) simply gets its own key and
starts with zero calibration samples — the directional Quality Model (§D)
still functions with lower confidence until samples accumulate.

**Not done this pass**: no calibration samples were actually collected (§9's
lab wasn't run) — this section is the methodology, ready to execute.

---

## F. Vision / Motion input map

| Input | Available now | After Vision | After Motion | Not available via public API |
|---|---|---|---|---|
| Lighting / exposure state | ✅ | | | |
| Focus lens position / stability | ✅ (proxy) | ✅ (real confidence via tracked subject) | | |
| Subject presence | ❌ | ✅ | | |
| Subject size in frame | ❌ | ✅ | | |
| Subject distance (metric) | ❌ | partial (relative, from size + focal length) | | ✅ true metric, this hardware (no LiDAR) |
| Subject motion | ❌ | ✅ (optical flow / tracked bbox delta) | | |
| Camera motion | ❌ | | ✅ (`CMMotionManager`) | |
| Requested framing / composition | ✅ (user/product-driven input, not a sensor read) | | | |
| Scene type (portrait/landscape/macro/etc.) | ❌ | ✅ (classification) | | |

Nothing in this row set is faked. Every "❌ available after X" cell reflects
a genuine capability gap this document does not paper over.

---

## G. Implementation plan

**IMPLEMENT NOW** (done, §0):
- Intelligent zoom snap to `secondaryNativeResolutionZoomFactors`.

**IMPLEMENT LATER (Phase 2.3+, needs Vision/Motion):**
- Subject-distance/size-informed lens selection.
- Motion-aware exposure/shutter prioritization.
- Focus-confidence-driven lock/continuous-AF switching.
- Full `CameraConfigurationCandidate` scoring engine (the design in §B–D
  is ready; wiring it to real scene inputs isn't).

**CONTROLLED A/B REQUIRED:**
- Any exposure override vs. Apple's default (already shown sensible in
  `CAMERA_DECISION_RESEARCH.md` §4 — needs a proven gap, not a hunch).
- Multi-frame computational photography (needs to beat Apple's existing
  Smart HDR on the same scene, side-by-side, before it's worth the
  complexity).
- `expected_detail`/`expected_noise` as real numbers (needs §E's lab run
  at scale, several devices/lighting conditions).

**NOT POSSIBLE THROUGH PUBLIC APIs:**
- True metric subject distance without LiDAR (confirmed, this device
  family's non-Pro tier).
- Custom white-balance gain locking on this specific hardware (confirmed;
  may differ on other devices — re-check per-device, never assume).
- ProRes on non-Pro hardware (confirmed, this unit).

**ALREADY OPTIMAL (don't touch):**
- Apple's default auto-exposure handheld-shutter behavior (§4 there).
- `AVCaptureVideoPreviewLayer` as the preview mechanism (prior checkpoint).
- Current photo capture pipeline / fidelity guarantees.

---

## H. Current architecture risks

Checked against iPhone 16 / 16 Plus / 16 Pro / 16 Pro Max / future models:

1. **`LensSelection.options` assumes exactly one `.builtInWideAngleCamera`
   constituent exists** when computing `wideEntryFactor` (used for display
   labels). True on every currently-shipping iPhone (Wide is always
   present), but if a hypothetical future device omitted it, labels would
   silently fall back to raw-factor display rather than crash — this is
   the correct degrade-gracefully behavior already, not a risk needing a
   fix.
2. **`CameraService.backCameraDeviceTypePriority`'s discovery order**
   (`.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera,
   .builtInWideAngleCamera`) covers every current back-camera virtual-device
   type Apple has shipped. A hypothetical future type not in this list
   would fall through to `.builtInWideAngleCamera` (single-lens fallback)
   rather than fail outright — degrades safely, but **should be
   revisited if Apple introduces a new virtual device type name** (e.g. a
   future quad-camera constant) — flagged here so it isn't missed.
3. **§0's snap tolerance (0.25 raw)** is a single global constant, not
   derived from the device's own `switchOverFactors` spacing. On a device
   whose secondary-native points sit very close to a constituent
   switch-over (unlikely but not provably impossible), the snap and the
   optical switch could interact in an untested way. Not observed on this
   unit (its one point, 4.0, is 2.0 away from the nearest switch-over) —
   noted as a real edge case for a future device, not fixed speculatively
   here.
4. **No architectural blocker for MotionShoot** was found: preview/capture
   separation (ADR-009) already isolates any future
   `AVCaptureVideoDataOutput` consumer from both, and `CameraCapabilities`/
   `CameraConfigurationCandidate` (§A–B) are designed to extend to video
   formats without rework — video-specific fields already exist
   (`FormatCapabilities.frameRateRanges`, `videoCodecs`, `stabilizationModes`).
5. **The pure `CamstheticsEngine` package remains uncontaminated** —
   verified: no file under `Sources/CamstheticsEngine/` imports
   `AVFoundation`, `UIKit`, or references `CMSampleBuffer`/`AVCaptureDevice`.
   Everything in §A–D above lives in `CamstheticsServices` (AVFoundation
   layer) by design; only normalized structs (`CameraCapabilities`,
   `QualityEstimate`, etc.) would ever cross into the engine, per Part 13's
   boundary — confirmed correct as of this pass, not yet exercised since
   the engine doesn't consume camera data yet.

---

## Status

- **Tests:** 106/106 passing (100 prior + 6 new `snapToNativeResolution` tests).
- **Build:** physical-device build succeeds (iPhone 16, no Simulator).
- **Physical validation:** intelligent zoom snap verified via live
  telemetry during an actual pinch gesture (two clean snap/release cycles,
  haptic confirmed invoked at both transitions).
- **Files changed:** `Sources/CamstheticsServices/Camera/CameraService.swift`
  (`LensSelection.snapToNativeResolution`, `CameraService
  .secondaryNativeResolutionZoomFactors`), `App/Camsthetics/
  PreviewValidationScaffold.swift` (pinch-gesture wiring + haptic),
  `Tests/CamstheticsServicesTests/LensSelectionTests.swift` (+6 tests),
  `docs/DEVICE_AGNOSTIC_CAMERA_ARCHITECTURE.md` (this file, new).
- **Nothing committed.**
