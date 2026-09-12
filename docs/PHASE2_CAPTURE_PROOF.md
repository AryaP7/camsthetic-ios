# Phase 2.0 — Capture Fidelity Proof: Results

**Status:** Complete — **PASS**
**Date:** 2026-09-02
**Gate:** `IMPLEMENTATION_PLAN.md` Phase 2.0 (hard gate, checklist item 8) / `DECISIONS.md` ADR-012, ADR-013
**Harness:** `App/Camsthetics/CaptureFidelityProof/` (throwaway; not production architecture)

---

## 1. Question this proof answers

> Does an `AVCaptureVideoDataOutput` attached to the `AVCaptureSession` — actively
> receiving frames, attached but idle, or entirely absent — change anything about
> what `AVCapturePhotoOutput` captures?

This operationalizes `PRODUCT_SPEC.md` FIDELITY-01/02's claim that analysis and
capture are structurally independent pipelines (`DECISIONS.md` ADR-009), and is a
hard prerequisite gate before any `CameraService` / `VisionService` production
camera architecture is built.

---

## 2. Method

### 2.1 Device

- **Physical iPhone 16** (`iPhone17,3`), connected over USB, identified via
  `xcrun devicectl` (`B6DF6702-E49E-55E0-A4C2-236DEA02403C`) and Xcode's device
  destination (`00008140-001459800A3A801C`).
- **No Simulator was used at any point in this proof.** The iOS Simulator has no
  camera hardware and no representative capture pipeline (`DECISIONS.md` ADR-012);
  a Simulator "pass" would prove nothing.
- Signed and installed with the project's existing Xcode **Personal Team**
  signing configuration (`CODE_SIGN_STYLE=Automatic`, team `P52K54F9U5`). No
  changes were made to project signing settings.

### 2.2 Trial definitions (exact)

Each trial reconfigures the `AVCaptureSession` from a clean state (all outputs
removed and rebuilt) so no configuration state leaks between trials, then takes
exactly one photo via `AVCapturePhotoOutput.capturePhoto(with:delegate:)`.

| Trial | Definition |
|---|---|
| **A** | `AVCaptureVideoDataOutput` attached to the session **and** its sample-buffer delegate set — actively receiving and counting (then discarding) frames at the moment of capture. |
| **B** | `AVCaptureVideoDataOutput` attached to the session, but its sample-buffer delegate is `nil` (detached) — output present, receiving no callbacks. |
| **C** | `AVCaptureVideoDataOutput` **absent** from the session entirely. |

Trial A's delegate does nothing but increment a frame counter and let the sample
buffer be released — no image processing of any kind occurs on the analysis path
(`CaptureFidelityProofHarness.swift`, `captureOutput(_:didOutput:from:)`).

### 2.3 Capture configuration (held constant across A/B/C)

- `session.sessionPreset = .photo`
- Camera: `.builtInWideAngleCamera`, back position (single physical device, no
  virtual/multi-camera switching — consistent with ADR-011)
- `photoOutput.maxPhotoQualityPrioritization = .quality`
- `photoOutput.maxPhotoDimensions` = the largest entry in
  `device.activeFormat.supportedMaxPhotoDimensions` (queried at runtime every
  trial, never hard-coded — consistent with ADR-010)
- Codec: HEVC (`hvc1`) requested via `AVCapturePhotoSettings(format:
  [AVVideoCodecKey: .hevc])` whenever `availablePhotoCodecTypes` offers it
  (queried at runtime, never assumed)
- `settings.photoQualityPrioritization = .quality`
- Explicitly **not** enabled by the harness: RAW/ProRAW, Zero Shutter Lag,
  Responsive Capture, Fast Capture Prioritization, Constant Color, virtual-device
  constituent photo delivery. (Their *supported*/*enabled* state is read back
  read-only for the sidecar; the harness never sets them.)
- Between reconfiguring the session and capturing, the harness sleeps 0.35s to
  let the render pipeline settle (documented `AVCapturePhotoOutput`
  reconfiguration behavior), and for Trial A an additional 0.5s to let real
  frames actually flow before capture — so Trial A is genuinely "actively
  receiving frames" at capture time, not just "configured."

### 2.4 Native capture path — nothing reconstructed

The only source of each saved artifact is
**`AVCapturePhoto.fileDataRepresentation()`**, written to disk with
`Data.write(to:options:.atomic)` **byte-for-byte as returned** — no resize,
re-encode, tone-map, or reconstruction from a pixel buffer, preview layer, or
screenshot. This is enforced structurally: nothing in the harness's capture
completion path touches pixels, only `AVCapturePhoto` and the exact `Data` it
returns.

### 2.5 Inspection methodology

Two independent ImageIO passes were performed on the saved bytes, purely as
read-only inspection — neither modifies, re-encodes, resizes, or tone-maps the
saved file:

1. **In-app sidecar introspection** (`CaptureFidelitySidecar.swift`,
   `ImageArtifactIntrospection`): `CGImageSourceCreateWithData` /
   `CGImageSourceCopyPropertiesAtIndex` / `CGImageSourceCopyAuxiliaryDataInfoAtIndex`
   run on-device immediately after each capture, recorded to a JSON sidecar
   alongside the photo.
2. **Independent macOS re-inspection**: a standalone Swift/ImageIO script
   (not part of the app or harness) was run against the pulled `.heic` files
   after transfer, re-deriving container UTI, pixel dimensions, bit depth,
   color model, ICC profile name, alpha info, auxiliary-image presence/shape,
   and `CGImage`-level color space — independently of and cross-checked against
   the sidecar's own numbers. `file`(1) was additionally used to confirm
   container/codec identification (`ISO Media, HEIF Image HEVC Main or Main
   Still Picture Profile`) from a third, non-ImageIO code path.

### 2.6 Transfer integrity (SHA-256)

Artifacts were pulled from the app's Documents directory
(`Documents/CaptureFidelityProof/`) to the Mac via `xcrun devicectl device copy
from --domain-type appDataContainer` (a copy, not a move — the on-device
originals were left in place). Each sidecar records the SHA-256 of the exact
bytes it wrote (`fileSHA256Hex`, computed on-device via CryptoKit at capture
time). After transfer, `shasum -a 256` was run against the three pulled `.heic`
files on the Mac and matched the sidecar-recorded hashes **exactly**, confirming
the copy operation did not corrupt or alter the artifacts in transit.

---

## 3. Trials run and artifacts produced

Scene and lighting were held stationary across all three trials; camera
position, lens, zoom, and capture settings were not changed between trials.

| Trial | File | Bytes | SHA-256 (prefix) | Timestamp (UTC) |
|---|---|---|---|---|
| A | `trial-A-20260902-170755-284.heic` + `.json` | 1,609,307 | `98a78ff0…` | 2026-09-02T17:07:55Z |
| B | `trial-B-20260902-170807-626.heic` + `.json` | 2,261,988 | `50c067fc…` | 2026-09-02T17:08:07Z |
| C | `trial-C-20260902-170815-871.heic` + `.json` | 1,705,050 | `1391d7a9…` | 2026-09-02T17:08:15Z |

All six files (three photos, three JSON sidecars) were retained after analysis
and are not deleted.

---

## 4. Comparison results (A vs B vs C)

| Characteristic | Trial A | Trial B | Trial C | Equal across A/B/C? |
|---|---|---|---|---|
| Resolved dimensions | 4032×3024 | 4032×3024 | 4032×3024 | ✅ |
| Requested `maxPhotoDimensions` | 8064×6048 | 8064×6048 | 8064×6048 | ✅ (see §5) |
| Container / UTI | `public.heic` | `public.heic` | `public.heic` | ✅ |
| Codec | HEVC, `hvc1` (HEIF Main/Main-Still Picture) | HEVC, `hvc1` | HEVC, `hvc1` | ✅ |
| File size | 1,609,307 B | 2,261,988 B | 1,705,050 B | natural variance (§6) |
| Color space | Display P3 (`P3_D65`) | Display P3 | Display P3 | ✅ |
| ICC profile | "Display P3", 536-byte embedded profile | same | same | ✅ |
| Bit depth | 8 bpc, 32 bpp | 8 bpc, 32 bpp | 8 bpc, 32 bpp | ✅ |
| Alpha info (`CGImageAlphaInfo`) | 5 (`noneSkipLast`) | 5 | 5 | ✅ |
| Depth auxiliary | absent | absent | absent | ✅ |
| Disparity auxiliary | absent | absent | absent | ✅ |
| Portrait-effects-matte auxiliary | absent | absent | absent | ✅ |
| HDR gain map auxiliary | present — 2016×1512, `L008` (1×8-bit/channel), 3,096,576-byte plane, headroom 2.17 | present — same dims/pixel format/plane size, headroom 2.38 | present — same dims/pixel format/plane size, headroom 2.40 | ✅ structure identical; headroom is natural per-exposure variance |
| EXIF/TIFF/MakerApple key structure | full set present | identical key set | identical key set | ✅ (values vary with exposure/timestamp — expected) |
| Lens / FNumber / FocalLength | iPhone 16 back camera, 5.96 mm, f/1.6 | identical | identical | ✅ |
| Capture latency | 0.681 s | 0.781 s | 0.697 s | within normal jitter (§6) |
| `device.activeFormat` | 4032×3024 `420f`, FOV 68.157° geometric-corrected, supports [4032×3024, 8064×6048], colorspaces [sRGB, P3_D65] | identical (same in-process format object) | identical | ✅ |
| `isZeroShutterLagSupported` / `Enabled` | true / true | true / true | true / true | ✅ |
| `isResponsiveCaptureSupported` / `Enabled` | true / false | true / false | true / false | ✅ |
| `isConstantColorSupported` / `Enabled` | true / false | true / false | true / false | ✅ |
| `isFastCapturePrioritizationSupported` | false | false | false | ✅ |
| `isVirtualDeviceConstituentPhotoDeliverySupported` | false | false | false | ✅ |
| `frameCounterAtCaptureTime` | **7** — Trial A's video-data-output delegate had actively received and counted 7 live frames immediately before capture, confirming the analysis pipeline was genuinely live, not merely configured | 0 (delegate detached — expected) | 0 (no output attached — expected) | by design, not a fidelity signal |

---

## 5. Requested (8064×6048) vs resolved (4032×3024) dimensions — not an A/B/C difference

Every trial's sidecar records the same note:

> "Requested `maxPhotoDimensions` (8064×6048) differs from resolved
> `photoDimensions` (4032×3024)."

This appears **identically in A, B, and C** — the mismatch is constant across
all three video-data-output states, so it is **not caused by, and does not
depend on, the video-output configuration under test**. It reflects that
`device.activeFormat.supportedMaxPhotoDimensions` on this device/format offers
an interpolated 8064×6048 option alongside the native 4032×3024 option, but the
photo pipeline resolved to the native 4032×3024 dimensions for this format/
session-preset combination. This is a pre-existing characteristic of format/
dimension selection, orthogonal to this proof's question, and is called out
here so it is not later mistaken for an A/B/C fidelity regression. It is **not
resolved by this proof** and is left for the format-selection work already
scoped under ADR-010.

---

## 6. Expected natural variance (explicitly not fidelity defects)

Per the proof's own pass criterion, the following differences between trials
are expected and were observed, and do **not** constitute a fidelity failure:

- **File size** (1.61 MB / 2.26 MB / 1.70 MB) — HEVC is content-adaptive;
  differing scene detail/motion/noise between shots taken seconds apart changes
  compressed size even with an unchanged scene.
- **Exposure metadata** (`ISOSpeedRatings`, `BrightnessValue`,
  `ExposureBiasValue`, `ShutterSpeedValue`) — the camera's auto-exposure
  re-evaluates every capture; small ambient/thermal drift between shots taken
  ~10–20 seconds apart is normal.
- **Timestamps** (`DateTimeOriginal`, capture UUIDs, etc.) — trivially expected
  to differ per capture.
- **HDR gain-map headroom value** (2.17 / 2.38 / 2.40) — derived from the same
  per-shot exposure analysis above; the gain map's *structure* (dimensions,
  pixel format, plane size) is identical across all three.
- **Capture latency** (0.681 s / 0.781 s / 0.697 s) — normal system scheduling
  jitter; no trend correlating latency with video-output state.

## 7. Explicit non-claims

- **This proof does not establish byte-for-byte equality between trials.**
  File bytes and SHA-256 hashes differ across A/B/C, as expected for three
  separate exposures of a real scene under natural (not studio-locked)
  conditions. The pass criterion is **characteristic equality** — dimensions,
  container/codec, color space, bit depth, auxiliary-image presence/structure,
  and capture-capability values — not identical bytes.
- **This proof does not claim reproduction of Apple's Camera.app computational
  photography pipeline** (Deep Fusion, Smart HDR, Photonic Engine, etc.) or any
  equivalence to Camera.app's output. It establishes only that this app's own
  `AVCapturePhotoOutput` capture path is unaffected by its own
  `AVCaptureVideoDataOutput` analysis path — a statement about internal
  pipeline independence, not about matching a separate first-party app.

---

## 8. Finding

**PASS.** Across all measured characteristics — resolved dimensions, container/
UTI, codec, color space, ICC profile, bit depth, alpha handling, auxiliary-image
presence and structure (depth, disparity, portrait matte, HDR gain map), EXIF/
TIFF/MakerApple key structure, and every queried `AVCapturePhotoOutput`
capability/support flag — Trials A (video output attached, actively receiving
frames), B (attached, delegate detached), and C (video output absent) are
**equivalent**. The only differences observed are the naturally variable
per-exposure characteristics explicitly excluded from the pass criterion (§6).

`AVCaptureVideoDataOutput` attachment and activity state has no measurable
effect on what `AVCapturePhotoOutput` captures, on physical iPhone 16 hardware.
This empirically confirms `PRODUCT_SPEC.md` FIDELITY-01/02 and the three-pipeline
separation architecture of `DECISIONS.md` ADR-009.

See `DECISIONS.md` ADR-013 for the corresponding decision record.

---

## 9. Scope note

This proof gates, but does not itself constitute, production camera
architecture. `CamstheticsEngine` was not modified by this work. No
`CameraService`, `VisionService`, or other production camera abstraction has
been started as of this document. The capture-fidelity harness
(`App/Camsthetics/CaptureFidelityProof/`) remains a throwaway artifact, not
production code, per its own file header.
