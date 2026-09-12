# FIDELITY-10 — Preview/Capture Consistency Measurement

**Status:** Complete — measured, not estimated.
**Requirement:** `docs/IMPLEMENTATION_PLAN.md` §Phase 2 Validation —
*"Preview/capture consistency: measured preview aspect/FOV/crop/orientation vs.
captured image, front and back cameras (FIDELITY-10)."*
**Device:** physical iPhone 16 (`iPhone17,3`), back camera
(`.builtInDualWideCamera`), at the 1× (Wide constituent) lens level. No
Simulator.
**Method:** `AVCaptureVideoPreviewLayer.metadataOutputRectConverted(fromLayerRect:)`
and its inverse `layerRectConverted(fromMetadataOutputRect:)` — the authoritative
public mapping between layer space and sensor space. Geometry was *not* derived
by hand; the hand derivation below exists only as an independent cross-check.

---

## 1. Raw measurement (read off the device)

```
layerBounds                = (0, 0, 393, 852) pt
contentsScale              = 3.0            → 1179 × 2556 physical px
videoGravity               = AVLayerVideoGravityResizeAspectFill
connection.rotationAngle   = 90°
connection.isVideoMirrored = false
visibleSensorRect          = (x≈0, y=0.19222722, w=1.0, h=0.61554557)
fullSensorImageInLayerCoords = (-122.729, 0, 638.458, 852)
```

Captured still, same session/lens: **4032 × 3024**, HEIC/HEVC, Display P3
(unchanged from the Phase 2.0 baseline).

## 2. Cross-check (hand-derived, agrees with the device)

| Quantity | Hand-derived | Device-reported |
|---|---|---|
| Full sensor image width in layer pts | 639.000 | 638.458 |
| Crop per side (pt) | 123.000 | 122.729 |
| Visible fraction of short axis | 0.615023 | 0.615546 |
| Centred-origin offset | 0.192227 | 0.192227 |

Agreement to ~0.1%, so the mapping is understood correctly rather than
coincidentally.

## 3. Result

| Property | Preview | Captured still |
|---|---|---|
| Aspect ratio | 393:852 = **0.4613** | 4032:3024 = **1.3333** (0.75 in portrait) |
| Long axis (portrait vertical) | **100%** of sensor | 100% |
| Short axis (portrait horizontal) | **61.55%** of sensor, centred | 100% |
| Orientation | 90° rotation, not mirrored | matches (back camera) |

**The captured photo contains 1.625× the horizontal extent the preview shows.**

- Hidden from the preview: **38.45%** of the short axis — **19.22% off each side**.
- In captured pixels: of the sensor's 3024-px axis, **1861 px are visible** in the
  preview and **1163 px are not** (**581 px per side**).

This is expected, correct `.resizeAspectFill` behaviour, not a defect: a 4:3
sensor cannot fill a ~19.5:9 screen without cropping. It has simply never been
measured or written down before.

## 4. Why this matters downstream

Any composition logic that reasons about "what the user is framing" is reasoning
about **61.55% of what actually gets captured**. Concretely, for Phase 3+ work:

- Subject bounding boxes from Vision run on analysis buffers in **sensor**
  coordinates, but the user composes against the **preview** crop. The two spaces
  differ by this factor and must be converted explicitly, never assumed equal.
- A subject that is comfortably inside the frame *as captured* can sit outside
  the preview entirely — and vice versa, a subject the user has framed at the
  preview edge sits well inside the final photo.
- Rule-of-thirds / headroom guidance computed in preview space will not land on
  the same points in the saved image unless converted.

`captureDevicePointConverted(fromLayerPoint:)` / `metadataOutputRectConverted(fromLayerRect:)`
are the correct conversion path in both directions and should be used rather than
re-deriving the crop — the tap-to-focus implementation added in this same pass
already does exactly this.

## 5. Not covered

- **Front camera:** FIDELITY-10 names both cameras. v1 is back-camera-only
  (ADR-011), so the front camera is untestable until that scope changes. Flagged,
  not silently dropped.
- **Non-1× lens levels:** measured at the Wide constituent. The mapping is
  computed by AVFoundation per current zoom/format, so the *method* holds at any
  zoom, but the specific fractions above apply to this format at 1×.
