# Open Optimizations & Hardware Ceiling Backlog — Camsthetics (iOS)

**Status:** LIVING DOCUMENT — hold this in every agent's context until it is gone.
**Reason this exists:** A diagnostic deep-review (2026-09-07) of every hot path
(capture session config → analysis YUV → Vision inference → stream → MainActor
sink; motion 100Hz; capture path) found concrete, evidence-backed optimization
opportunities that were *not yet patched*. Several are disguised as
already-done (doc comments claim a saving the code does not deliver).

**Read this if you are any coding agent working in this repo.** When an item is
resolved by patches, update its status, cite the commit/harness that closes it,
then delete this file once **all** items are `HANDLED` (and the plan audit below
is done). Until then it is required reading — an agent that changes any code in
`CamstheticsServices`, `CamstheticsEngine`, or the camera/vision/motion app
screens without consulting this file may re-introduce or silently re-validate
one of these at best, or at worst "rediscover" and enable an already-rejected
fidelity-vs-performance trade.

The project's own discipline (`docs/DECISIONS.md` ADR-012/ADR-013) is the yard
stick for every item below: claims are verified on physical hardware, and
analysis-side changes never touch the capture path (ADR-009, `PRODUCT_SPEC.md`
FIDELITY-01/02). Each item lists its required on-device verification.

---

## 0. How to close an item

1. Patch the code. Where the fix is pure policy, mirror the established
   unit-test pattern (`LensSelection`/`CaptureFormatSelection`/
   `VisionSubjectExtraction` fixtures on macOS — no hardware needed).
2. Re-verify the *behavioral* claim on a physical iPhone 16 (no Simulator,
   ADR-012): for analysis-resolution and Vision-item changes this means the
   FIDELITY-02 A/B re-proof (`Sources/CamstheticsServices/Camera/CameraService.swift`
   header + `docs/PHASE2_CAPTURE_PROOF.md` ADR-013 consequence) and the Phase 3
   latency measurement harness (`App/Camsthetics/VisionSmokeTest/`).
3. Update this file: set the item to `HANDLED`, cite the commit or harness
   output that closed it.
4. When no `OPEN` items remain: fix the plan-audit discrepancy (§6), then
   **delete this file** and remove its pointers from `AGENTS.md` /
   `IMPLEMENTATION_PLAN.md` / `ARCHITECTURE.md`.

---

## 1. Item O-1 — analysis output may deliver full-sensor buffers to Vision

- **Status:** `OPEN`
- **Severity:** High (throughput / thermal / the sustained-10Hz contract).
- **Location:** `Sources/CamstheticsServices/Camera/CameraService.swift:927-951`
  (`videoDataOutput.videoSettings` set at `:935`).
- **Finding:** The analysis output's `videoSettings` requests only the pixel
  format (`kCVPixelBufferPixelFormatTypeKey`) — no
  `kCVPixelBufferWidthKey`/`kCVPixelBufferHeightKey`. With session preset
  `.photo` this risks delivering buffers at the full sensor resolution
  (≈4032×3024 → ~18MB per YUV420 frame) to the 10Hz Vision pipeline, then
  discarding most of it — ~180MB/s of memory bandwidth before inference.
  Apple's current documentation states width/height keys *are* supported for
  uncompressed video output on iOS 16+, but also that
  `automaticallyConfiguresOutputBufferDimensions` (default `true`) may instead
  auto-scale to screen size — so the **actual delivered dimensions are unknown
  and must be probed on-device**, not assumed either way.
- **Why it's safe to fix:** Downsampling is explicitly permitted for the
  analysis representation (`docs/ARCHITECTURE.md` §4.4.1/4.4.2), and ADR-013
  already proved analysis-path video output cannot alter capture bytes.
- **Proposed fix:** After starting the session, read the delivered buffer
  dimensions (probe), then set explicit width/height (e.g. 1280-×-960 @ 420f,
  aspect corrected for the active format per Apple's `videoSettings` contract)
  inside `videoSettings`. Verify on-device that (a) delivered buffers are the
  requested size, (b) FIDELITY-02 A/B capture comparison is unchanged.
- **Verification:** One on-device dimension probe; FIDELITY-02 A/B re-proof;
  Phase 3 latency harness before/after.

---

## 2. Item O-2 — saliency inference runs every frame even when a person is detected

- **Status:** `OPEN` — the code does not match its own documented intent.
- **Severity:** High (doubles per-frame Vision cost in the common coaching case).
- **Location:** `Sources/CamstheticsServices/Vision/VisionSubjectExtraction.swift:79-93`
  (`handler.perform([bodyPoseRequest, saliencyRequest])` at `:82`). Shared by
  live path `Sources/CamstheticsServices/Vision/VisionService.swift:128-145`
  (`:139`) and one-shot stills `Sources/CamstheticsServices/Vision/TargetExtractor.swift:65-66`.
- **Finding:** The doc comment (`:74-78`) says saliency runs only "when no [person
  was] found... skipping saliency when one already exists saves latency rather
  than computing a result nothing would use." The code performs **both** requests
  unconditionally. `VNGenerateAttentionBasedSaliencyImageRequest` runs a full
  attention network; the app's primary subject is a person, so for the frames
  that matter most Vision wastes a full foreground-attention inference at 10Hz.
- **Proposed fix:** Run `VNDetectHumanBodyPoseRequest` alone first; split the
  `perform` so saliency is only added when body-pose yielded zero candidates.
  The observation→candidate path after `perform` is unchanged.
- **Verification:** Unit test that empty body-pose results trigger saliency and
  non-empty results skip it (existing fixture style); on-device latency harness
  (`VisionSmokeTestView`) shows the per-frame reduction.

---

## 3. Item O-3 — Vision handler/request objects reallocated every frame

- **Status:** `OPEN`
- **Severity:** Low-Medium (allocations, secondary to O-1/O-2).
- **Location:** `Sources/CamstheticsServices/Vision/VisionService.swift:139`
  (new `VNImageRequestHandler` per frame) and
  `VisionSubjectExtraction.swift:80-81` (two new `VNRequest` per frame).
- **Finding:** At 10Hz the actor constructs a handler + two request objects per
  frame. `VisionService` is actor-serialized, so request instances can be reused
  safely between frames (results are replaced per `perform`). Allocation churn
  and result-array pressure, not a correctness bug.
- **Proposed fix:** Hoist body-pose (and fallback saliency) request instances to
  stored actor properties; reuse the handler where the buffer's lifetime permits.
  Do this *with* O-2, not before — gating saliency changes what needs reusing.
- **Verification:** Unit tests unchanged; on-device latency/thermal unchanged or
  better; confirm no stale `results` bleed between frames.

---

## 4. Item O-4 — TargetExtractor feeds full-res stills to Vision and CPU-grayscales

- **Status:** `OPEN`
- **Severity:** Medium (one-shot path, but the `<500ms` ingestion budget
  (`PRODUCT_SPEC.md` §1.1) is what's at risk on a 12MP reference image).
- **Location:** `Sources/CamstheticsServices/Vision/TargetExtractor.swift:57-69`
  and `108-149`.
- **Finding:** `extract(from:)` builds `VNImageRequestHandler(cgImage:)` from the
  full-resolution `CGImage` (`:65`), and `grayscaleBuffer` rasterizes the full
  image into the 256px Sobel buffer via a CPU `CGContext` at `.high`
  interpolation quality (`:127-142`). Vision normalizes its output coordinates,
  so pre-downscaling the input is result-equivalent and cheaper in memory and
  inference time. Also inherits O-2's unconditional saliency.
- **Proposed fix:** Downscale to ≤~1280px long edge before the Vision handler;
  consider `vImage` for the Sobel-input downscale. Co-land with O-2 so both
  still-image optimizations land/test together.
- **Verification:** `Tests/CamstheticsServicesTests/TargetExtractorTests.swift`
  fixture parity (same extracted `CompositionParams` from downscaled input);
  timing check well under 500ms on a physical iPhone 16.

---

## 5. Item O-5 — 100Hz motion causes double Observation invalidation per sample

- **Status:** `OPEN`
- **Severity:** Low (free win; UI-only).
- **Location:** `App/Camsthetics/CameraScreen/CameraViewModel.swift:163-168`
  (`observeMotion` writes `state.rollDegrees` then `state.isLevel` per 100Hz
  sample → two tracked-property writes → two invalidation passes).
- **Proposed fix:** Coalesce into a single snapshot value (e.g. a small
  `DeviceAttitude`-shaped struct on `CameraMockupState`) that the spirit level
  reads once; or write `isLevel` as a derived getter of `rollDegrees`.
- **Verification:** `CameraScreenTests`/camera UI unchanged; motion path unit
  tests still pass.

---

## 6. Plan audit — "verify 60fps" exceeds measured hardware (doc-level)

- **Status:** `OPEN` (documentation only — no code change).
- **Location:** `docs/IMPLEMENTATION_PLAN.md` Phase 2 Validation ("Verify 60fps
  video stream delivery"); measured reality recorded in
  `Sources/CamstheticsServices/Camera/CameraService.swift:806-816` (format
  advertises ≤30fps; default negotiation measured at ~15fps on the physical
  iPhone 16 used this cycle).
- **Action:** Reword the plan's 60fps validation target to "verify the session
  sustains the active format's advertised maximum frame rate" (30fps on current
  hardware) and record the per-format measurement instead of chasing an
  unattainable 60fps claim. Do this when the last `OPEN` item above is closed,
  before deleting this file.

---

## 7. What the review cleared (do NOT re-litigate without new evidence)

- No code requests more than hardware advertises: `activeVideoMinFrameDuration`
  is capped at the format's `videoSupportedFrameRateRanges` max; zoom is clamped
  to `min/maxAvailableVideoZoomFactor`; ramp rate and exposure bias are clamped;
  photo dimensions come from `supportedMaxPhotoDimensions`; HEVC is chosen from
  `availablePhotoCodecTypes`; motion samples at CoreMotion's 100Hz ceiling.
- Analysis/backpressure design is sound (`AnalysisFrameProcessor` single-frame
  gate, `alwaysDiscardsLateVideoFrames`); the only throughput ceiling is the
  O-1/O-2 combination above.
- Capture-path options that were investigated and deliberately rejected (zero
  shutter lag is already the system default; fast-capture prioritization,
  constant color, auto-deferred photo delivery, app-side post-processing) are
  recorded with rationale in `CameraService.swift:834-911` — do not re-enable
  without a product-level decision.

---

*Created 2026-09-07 from the on-device-informed diagnostic review. Delete this
file only when §0 is complete.*