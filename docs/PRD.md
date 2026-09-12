# Product Requirements Document (PRD) — Camsthetics (iOS)

**Document Version:** 1.0  
**Status:** Authoritative Foundation  
**Target Platform:** iOS 17.0+ (Swift / Native iOS)

---

## 1. Product Vision & Overview

### 1.1 Vision
**Camsthetics** is a real-time aesthetic camera coach for iOS that turns photographic inspiration into physical, intuitive spatial movement. It bridges the gap between the photos users want to take (saved on Pinterest, Instagram, or photo galleries) and their ability to position, level, height-match, and frame their camera in real time.

### 1.2 Problem Statement
Most people have strong visual taste—they recognize a well-composed photo instantly—but lack the spatial, geometric, and photographic intuition needed to position a phone camera in the physical world to replicate that framing. They struggle with:
* Incorrect camera height (e.g., shooting portrait from chest height instead of hip/eye level).
* Unwanted horizon roll and perspective pitch distortion.
* Improper subject-to-frame distance and focal framing.
* Communicating desired framing to friends or partners ("make me look like this pin").

### 1.3 Core Value Proposition
> **"Turn inspiration into physical camera movement."**

The app takes any target reference image and computes the real-time geometric delta between the target and the live camera viewfinder, translating discrepancies into simple, human-executable physical cues (*"Rotate right 3°"*, *"Step back"*, *"Lower phone"*) with a live match meter that unlocks capture when framing is locked.

---

## 2. Goals & Non-Goals

### 2.1 Product Goals
* **G1: Real-Time Spatial Coaching:** Deliver continuous live guidance across 5 geometric dimensions (Roll/Tilt, Lateral position, Distance/Framing ratio, Camera height, Camera pitch) with sub-100ms motion-to-feedback latency.
* **G2: Frictionless Inspiration Ingestion:** Allow users to use any reference photo instantly via the iOS Share Sheet, pasteboard URL resolution (Pinterest/web), local photo picker, or a built-in curated aesthetic library without requiring an account.
* **G3: First-Party Apple Camera Experience:** Deliver fluid 60/120fps viewfinder performance, native hardware controls, ProRAW/Smart HDR capture fidelity, and nuanced CoreHaptics feedback.
* **G4: 100% On-Device Privacy:** Live camera frames never touch disk or leave the device. All coaching inference is computed entirely on-device via the Apple Neural Engine.
* **G5: Honest Coaching Promise:** Explicitly coach users to "get close and make the shot significantly better," rather than promising impossible pixel-perfect clones across differing lenses, heights, and physical environments.

### 2.2 Non-Goals (v1.0)
* **NG1: Video Coaching:** Stills only in v1; real-time video recording coaching is out of scope.
* **NG2: Complex Photo Editing / Filters / LUTs:** The app focuses on camera positioning and capture. Post-capture is strictly for review, compare, and non-destructive auto-straighten/crop.
* **NG3: Multi-Person Choreography:** Multi-subject choreography ("move person 2 left") is out of scope; single primary subject or environmental scene composition only.
* **NG4: Custom Cloud Account / Social Network:** No custom login, social feed, or cloud photo sync. Captures save directly to the native iOS Photos library.

---

## 3. Target Users & Personas

| Persona | Motivation | Primary Pain Point | Core User Journey |
|---|---|---|---|
| **The Aesthetic Creator (Chloe, 24)** | Wants her lifestyle/fashion photos to match curated Pinterest moodboards. | Takes 40+ photos to get 1 good shot; hard to judge angle while posing. | Ingests pin via Share Sheet $\to$ Uses tripod / hands-free $\to$ Auto-capture locks framing. |
| **The "Partner Photographer" (Marcus, 28)** | Handed a phone to take a photo of a friend/partner. | Doesn't know how to frame or hold the camera; gets frustrated with vague directions. | Receives phone with target active $\to$ Follows on-screen arrows $\to$ Shoots when green. |
| **The Casual Explorer (Sam, 31)** | Travels and visits scenic locations/cafés. | Sees a great spot but doesn't know what angle or composition works best. | Opens Scan Mode $\to$ Sweeps surroundings $\to$ Picks recommended aesthetic $\to$ Shoots. |

---

## 4. Core User Journeys

### Journey 1: Match an Ingested Pin / Photo (Mode B)
1. User finds an inspiring photo in Pinterest, Instagram, Safari, or Photos.
2. User taps **Share $\to$ Camsthetics** (or copies link and opens app).
3. The app ingests the image, normalizes aspect ratio, and extracts composition features in $<500\text{ms}$.
4. The live camera opens with the target ghost frame and spirit level visible.
5. Real-time directional cues guide user movement (*"Step back"*, *"Rotate right 4°"*).
6. Match score reaches $\ge 85\%$ ("On Target"); shutter glows green; optional auto-capture fires.
7. User reviews interactive drag-to-compare wipe and saves to Camera Roll.

### Journey 2: Environment Scan & Discover (Mode A)
1. User arrives at an interesting location (e.g., architectural space, café).
2. User opens **Scan Mode** and pans phone across the scene for 4–6 seconds.
3. On-device vision extracts scene context (lighting, dominant color palette, spatial geometry).
4. App presents top 3–5 recommended aesthetic reference shots from the local curated/synced library with rationale ("warm golden-hour light, leading lines").
5. User selects a recommendation and transitions seamlessly into Live Coaching.

### Journey 3: Instant Pose / Template Shoot
1. User opens the app directly into camera view.
2. User taps the **Aesthetic Library** bottom sheet to pick a curated pose archetype (e.g., "Standing Profile", "Sitting Café", "Golden Ratio Landscape").
3. Viewfinder displays pose skeleton / alignment guides.
4. User positions subject to align with keypoints and shoots.

---

## 5. Product Principles

1. **Physical, Actionable Guidance:** Coaching copy must always be physical and human ("Step back", "Lower phone", "Rotate right 3°"), never abstract coordinate numbers.
2. **Never Overload the Viewfinder:** Show at most 1–2 high-priority movement cues at any time. The camera must remain a viewfinder, not a cluttered cockpit HUD.
3. **Decoupled Smoothness:** Background ML inference (8–15Hz) must never block or stutter the 60/120fps viewfinder rendering and fluid gesture interactions.
4. **Pristine Capture Fidelity (hard safety floor):** Never re-compress or degrade captured photos. Capture is written at maximum sensor quality directly to Apple Photos (`PhotoKit`). This floor is non-negotiable and is not superseded by §5.2 below — it is the invariant §5.2's product objective is built on top of.
5. **Graceful Degradation:** The coaching engine must always provide value; if a subject cannot be detected, it falls back to sensor-exact horizon leveling and rule-of-thirds scene cues.
6. **Analysis Never Degrades Capture:** Real-time analysis may sacrifice resolution and representation for performance; final image capture may **never** sacrifice quality merely to simplify analysis. Analysis, preview, and capture are separate pipelines (see `ARCHITECTURE.md` §4.4 and `PRODUCT_SPEC.md` §1.8).

### 5.1 Image Fidelity & Native Capture (Hard Product Requirement)

This requirement is first-class and architectural. It ranks alongside the coaching engine itself, not below it.

> **"Camsthetics must preserve the highest image quality available through Apple's supported third-party camera APIs. The app must not introduce unnecessary degradation to resolution, detail, color fidelity, dynamic range, HDR characteristics, metadata, orientation, stabilization, or other capture characteristics."**

* **The composition/coaching functionality must not require compromising the final captured image.** If a coaching capability can only be delivered by degrading the capture, the coaching capability is the part that gets cut.
* **Three separate pipelines:** ANALYSIS (Vision/CV, may be aggressively optimized), PREVIEW (responsiveness and accurate composition representation), and CAPTURE (highest-quality supported native photo path). They may share camera input, but processing performed for analysis or UI must never become the source of the final saved photograph.
* **Never saved as the final photograph:** Vision frames, preview frames, downsampled analysis frames, unnecessarily converted RGB buffers, screenshots of the preview, or compressed intermediate representations.

**Precise goal statement (no overclaiming):**

> **"Use Apple's highest-quality supported third-party capture APIs and avoid introducing additional quality loss in Camsthetics."**

Camsthetics does **not** claim to reproduce Apple's proprietary Camera.app computational photography pipeline bit-for-bit. Portions of Apple's first-party capture behaviour are not exposed to third-party apps through public API; those gaps are documented in `PRODUCT_SPEC.md` §1.8 "Known Platform Limitations" rather than papered over with marketing language.

Full normative specification: `PRODUCT_SPEC.md` §1.8 (Group FIDELITY). Architectural enforcement: `ARCHITECTURE.md` §4.4. Decision records: `DECISIONS.md` ADR-009 through ADR-012.

### 5.2 Baseline, Not Ceiling — The Photographic Outcome Objective (Future Scope)

§5.1 establishes the hard safety floor: Camsthetics must never fall below Apple's native capture quality. This section states the objective layered on top of that floor, decided in `DECISIONS.md` ADR-014.

> **Apple's native Camera behavior is the BASELINE, not the CEILING.** "No degradation" remains a hard safety baseline; "improve upon the baseline" is the product objective.

Camsthetics should eventually optimize not only for capture fidelity, but for **photographic outcome** — using scene understanding, camera decisions, timing, and image selection to produce the best practical photographs and videos available from the device's hardware and public iOS camera APIs. Concretely: Apple-quality computational capture, plus Camsthetics-specific composition intelligence, plus Camsthetics' own image rendering — not a copy of Apple's proprietary pipeline, and not a regression from it either.

* **For every important camera-quality decision, ask:** (1) what does Apple's public camera stack provide, (2) what does the native Camera app appear to optimize for, (3) what can Camsthetics control through public iOS APIs, (4) can Camsthetics make a better decision for this specific photographic/videographic objective, and (5) can the improvement be objectively demonstrated. A change is pursued only when its benefits outweigh its tradeoffs across the real quality dimensions (detail, sharpness, motion clarity, noise, dynamic range, highlight/shadow preservation, exposure/focus accuracy, color accuracy, skin rendering, local contrast, artifacting, temporal consistency, stabilization, composition, subject quality, capture timing, aesthetic quality, file/metadata integrity) — never by file size, resolution number, or bitrate as a proxy for quality.
* **Never assume Apple is optimal.** Apple's implementation may be highly optimized for Apple's objectives; Camsthetics can have different objectives and make different higher-level decisions. Reject the reasoning "Apple does it this way, therefore it is correct" in favor of "Apple does it this way — understand why, treat it as the baseline, then evaluate whether Camsthetics can legitimately do better."
* **Stay within the public API boundary.** No reproducing or bypassing Apple's private ISP, computational-photography, or system-only functionality — only what third-party apps can legitimately do with the same public capabilities, built into superior decision-making, timing, selection, and rendering.
* **Preserve information before improving it.** Distinguish capture quality, decision quality, processing/rendering quality, and user-perceived aesthetic quality. Never sacrifice captured information merely to produce a prettier result unless the tradeoff is intentional, measurable, and justified: capture the highest-quality source available → preserve all useful information → make better capture decisions → apply specialized Camsthetics processing → produce the best final result.
* **Measure against native Camera, don't assert.** Compare under matched conditions (device, lens, subject, framing, lighting, focus scenario, exposure scenario, motion) before claiming Camsthetics is "better than Apple." Don't reject an optimization merely because Apple's own app doesn't use it, either — measure it.
* **The future Camsthetics Decision Engine** (evaluating scene, subject, composition, lighting, motion, focus confidence, exposure, dynamic-range risk, lens suitability, capture timing, video quality, and desired aesthetic) is the mechanism this objective is built toward, rather than manually imitating Apple's camera decisions. The same principle extends to video: Apple's native video mode is not assumed to be the ceiling for a third-party app either — see the future MotionShoot investigation scope in `CAMERA_DECISION_RESEARCH.md` §12 and `IMPLEMENTATION_PLAN.md` Phase 8 for the concrete, currently-unstarted application of this objective.

This section is a statement of product direction and decision-making discipline, not an implementation authorization — see `IMPLEMENTATION_PLAN.md` Phase 8 for what remains explicitly future/not-started.

---

## 6. Scope & Version Boundaries

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           CAMSTHETICS ROADMAP                               │
├─────────────────────────────────────────────────────────────────────────────┤
│  v1.0 — Core Launch                                                         │
│  • Share Sheet Extension (Pinterest, Safari, Photos)                        │
│  • Clipboard Link Resolver (Public Pinterest oEmbed & OpenGraph)            │
│  • Photo Library Ingest (PHPicker)                                          │
│  • Curated Built-in Aesthetic Starter Library                               │
│  • 5D Live Coaching Engine (Tilt, Lateral, Distance, Height, Pitch)         │
│  • Anti-flicker Hysteresis & Confidence Tiers (FULL, PARTIAL, MINIMAL)      │
│  • Native AVFoundation Camera (Smart HDR, Lens Switcher, Exposure, AF)      │
│  • Drag-to-Compare Review & Local Session History                           │
│  • Apple CoreHaptics & Dynamic Type Accessibility                           │
├─────────────────────────────────────────────────────────────────────────────┤
│  v1.1 — Enhanced Coaching & Exploration                                     │
│  • Mode A: Environment Scene Scan & Recommendation Engine                   │
│  • Live Human Body Pose Skeleton Guide (Vision framework)                   │
│  • Audio / Voice Coaching Prompts (for solo tripod shooting)                │
│  • 1-Click Auto-Straighten / Crop in Post-Capture Review                    │
│  • Direct Pinterest OAuth Account Sync (with Token Broker)                  │
├─────────────────────────────────────────────────────────────────────────────┤
│  v2.0 — Pro & Connected Workflows                                           │
│  • Apple Watch Live Viewfinder Companion                                    │
│  • Multi-Subject Group Composition Detection                                │
│  • Custom User-Created Pose Packs & Community Sharing                       │
│  • ProRAW 48MP Burst Best-Shot AI Selector                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│  Future / Not Started — Camsthetics Decision Engine                        │
│  • MotionShoot ("Intelligent Photoshoot Mode") — video-to-curated-photoshoot│
│    frame selection; see §5.2, `CAMERA_DECISION_RESEARCH.md` §12,           │
│    `IMPLEMENTATION_PLAN.md` Phase 8                                        │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 7. Open Product Decisions & Clarifications

| # | Question / Decision Area | Options | Current Working Default | Impact |
|---|---|---|---|---|
| **OPD-1** | **OAuth vs. No-Auth Ingest for v1.0** | (A) Share Sheet + Link Resolver + Curated Library only.<br>(B) Full Pinterest OAuth + Token Broker. | **Option A for v1.0**; OAuth in v1.1. | Eliminates server dependency for launch, 100% client-side privacy. |
| **OPD-2** | **Pose Overlay Detail in v1.0** | (A) Clean bounding box + eye-line anchor.<br>(B) Full Vision pose skeleton overlay. | **Option A for v1.0**; Full skeleton in v1.1. | Keeps v1.0 coaching uncluttered; ensures rock-solid baseline before skeleton tuning. |
| **OPD-3** | **Audio Coaching Channel** | (A) Visual + CoreHaptics only.<br>(B) Optional Voice prompts (`AVSpeechSynthesizer`). | **Visual + Haptics in v1.0**; Voice in v1.1. | Prevents audio annoyance in public spaces during initial launch. |
