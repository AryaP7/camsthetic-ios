# Design System & Interaction Guidelines — Camsthetics (iOS)

**Document Version:** 1.0  
**Status:** Authoritative Foundation  
**Companion Documents:** `PRD.md`, `PRODUCT_SPEC.md`, `ARCHITECTURE.md`

---

## 1. Design Philosophy: Native Apple Elegance

Camsthetics is designed to feel like an authentic, first-party Apple camera experience. It avoids unnecessary chrome, loud gradients, and cognitive clutter. The interface is engineered for **one-handed thumb reach**, **glanceable clarity**, and **whisper-quiet guidance**.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           CORE DESIGN PRINCIPLES                            │
├─────────────────────────────────────────────────────────────────────────────┤
│  1. Unobtrusive Clarity:     The camera subject is the hero. Guidance only  │
│                              appears when needed and never blocks the view. │
│                                                                             │
│  2. Spatial Ergonomics:      All primary interactions are anchored within   │
│                              the bottom 30% thumb deck for easy single-     │
│                              handed operation.                              │
│                                                                             │
│  3. Tactile Precision:       Feedback is delivered through Taptic Engine    │
│                              impulses, allowing users to "feel" alignment.  │
│                                                                             │
│  4. Dynamic Responsiveness:  Every transition is interactive, interruptible,│
│                              and driven by Apple spring physics.            │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Color System & Semantic Tokens

All UI elements use high-contrast, dark-mode-optimized tokens designed for outdoor and low-light readability:

| Token Name | Hex / SwiftUI Color | Opacity | Semantic Purpose |
|---|---|---|---|
| `camBackground` | `#000000` (OLED Black) | $100\%$ | Viewfinder letterbox framing, deep chrome background. |
| `camTextPrimary` | `#FFFFFF` (Pure White) | $100\%$ | Primary HUD icons, active instruction text, shutter ring. |
| `camTextSecondary` | `#FFFFFF` | $65\%$ | Inactive mode labels, subtitle hints, secondary metadata. |
| `camTextTertiary` | `#FFFFFF` | $40\%$ | Tick marks, inactive control badges, subtle ghost lines. |
| `camYellow` | `#FFCC00` (Apple Camera Yellow) | $100\%$ | Active focus reticle, level alignment lock, AE/AF lock badge. |
| `camTargetGreen` | `#34C759` (Apple System Green) | $100\%$ | Framing locked "On Target" ($\ge 85\%$), shutter glow. |
| `camGlassMaterial` | `.ultraThinMaterial` (Dark) | Adaptive | Control capsules, instruction pills, bottom sheets. |
| `camTextScrim` | Linear Gradient (`#000000` $\to$ `#00000000`) | $40\% \to 0\%$ | Protective background behind white text over bright skies. |

---

## 3. Typography & Numerical Formatting

* **Font Family:** San Francisco (`SF Pro` for text, `SF Compact` for dials, `SF Mono` for data).
* **Strict Tabular Figures:** All dynamic numerical readouts **must** apply `.monospacedDigit()` to prevent horizontal layout shudder when numbers update.

```
• Large Titles (Sheet headers):     SF Pro Display Bold, 28pt
• Instruction Label:                SF Pro Text Semibold, 15pt, uppercase, +1.0pt tracking
• Tabular Angle / Timer / Zoom:     SF Pro Text Medium, 14pt (monospacedDigit)
• Secondary Guidance Cue:           SF Pro Text Regular, 12pt
• Mode Carousel Labels:             SF Pro Text Medium, 13pt, uppercase, +0.8pt tracking
```

---

## 4. Layout Architecture & Component Anatomy

```
┌─────────────────────────────────────────────────────────────┐
│  [⚡️ Flash]         [▲ Drawer Chevron]         [RAW / Live]  │ ◄── Top Status Bar (20pt SF Symbols)
├─────────────────────────────────────────────────────────────┤
│                                                             │
│                                                             │
│                 [ ↻ Rotate Left 3° ]                        │ ◄── Floating Instruction Pill
│                                                             │
│                 [ ───   Level Line   ─── ]                  │ ◄── Spirit Horizon Indicator
│                                                             │
│                 ┌ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┐                     │
│                 │   Ghost Silhouette  │                     │ ◄── Adaptive Target Frame
│                 └ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┘                     │
│                                                             │
│                                            ( 88% Match )    │ ◄── Dynamic Score Meter
│                                                             │
├─────────────────────────────────────────────────────────────┤
│                  (.5)    ( 1x )    ( 2 )    ( 3 )           │ ◄── Lens / Zoom Pill
│                                                             │
│         PHOTO       COACH       SCAN       PORTRAIT         │ ◄── Horizontal Mode Carousel
│                                                             │
│   [ 🖼️ Gallery ]          (  ⚪️  )          [ 🎯 Target ]   │ ◄── Bottom Action Triad
│    Recent Capture       Shutter Button      Reference Peek  │
└─────────────────────────────────────────────────────────────┘
```

### Component Details

#### 1. Floating Instruction Pill (HUD)
* **Visual:** Frosted glass capsule (`.ultraThinMaterial`, dark blur), height $36\text{pt}$, padding $12\text{pt}$ horizontal.
* **Content:** Directional SF Symbol arrow (e.g. `arrow.left`, `arrow.clockwise`) + concise uppercase copy (*"PAN LEFT"*, *"STEP BACK"*).
* **Motion:** Interactive spring transition (response $0.35\text{s}$, damping $0.82$) on text change.

#### 2. Spirit Horizon Indicator
* **Visual:** Two hairline horizontal bars ($1.5\text{pt}$ stroke, $28\text{pt}$ width each) with a center gap.
* **Behavior:** When roll error $|\Delta\theta| > 0.5^\circ$, bars rotate with device roll in translucent white ($50\%$ opacity). When $|\Delta\theta| \le 0.5^\circ$, bars snap horizontal, illuminate in **Apple Camera Yellow** (`#FFCC00`), and fire a crisp haptic tick.

#### 3. Ghost Subject Silhouette
* **Visual:** Smooth, rounded rectangular outline or human body vector silhouette ($1.5\text{pt}$ anti-aliased hairline stroke).
* **Adaptive Opacity:**
  * Searching / Approaching ($< 85\%$): $40\%$ opacity in neutral white.
  * Locked "On Target" ($\ge 85\%$): $90\%$ opacity in **System Green** (`#34C759`) with a subtle $1.02\times$ breathing pulse.

#### 4. The Apple Shutter Button
* **Visual:** Outer white circle ring ($72\text{pt}$ diameter, $3\text{pt}$ stroke width) with a solid white center core ($62\text{pt}$ diameter).
* **Touch-Down:** Center core scales down to $54\text{pt}$ ($0.2\text{s}$ spring, damping $0.70$).
* **Touch-Up / Fire:** Core springs back to $62\text{pt}$ accompanied by a $0.1\text{s}$ white screen flash and an impact haptic pulse.
* **Auto-Capture Ring:** A green countdown stroke fills the outer ring ($3\text{s} \to 0\text{s}$) when auto-capture is active.

---

## 5. Animation Physics & Spring Specifications

All animations use fluid Apple spring curves with zero linear or easing artifacts:

```swift
// Apple Standard Spring Curves
let interactiveSpring = Animation.spring(response: 0.30, dampingFraction: 0.80)
let gentleSpring      = Animation.spring(response: 0.45, dampingFraction: 0.85)
let snappySpring      = Animation.spring(response: 0.22, dampingFraction: 0.72)
```

| Component / State Change | Animation Curve | Duration / Response |
|---|---|---|
| **Lens Switch Pill Tap** | `snappySpring` | $0.22\text{s}$ response |
| **Drawer Chevron Expand/Collapse** | `interactiveSpring` | $0.30\text{s}$ response |
| **Instruction Pill Swap** | `gentleSpring` + `.opacity` | $0.40\text{s}$ response |
| **Shutter Button Press/Release** | `snappySpring` | $0.20\text{s}$ response |
| **Target Sheet Presentation** | `.interactiveSpring` (Detents: `.medium`, `.large`) | System Sheet Spring |

---

## 6. Tactile Haptic System (CoreHaptics)

The app employs a deliberate, four-tier haptic hierarchy:

```
1. Selection Tick (UISelectionFeedbackGenerator)
   • Triggered when: Horizon snaps level (±0.5°), Mode carousel changes, Lens switch detent.
   • Sensation: Single, ultra-sharp micro-transient.

2. On-Target Pulse (UINotificationFeedbackGenerator - .success)
   • Triggered when: Match score crosses ≥ 85% entry threshold.
   • Sensation: Soft, rewarding double-tap vibration.

3. Shutter Actuation (UIImpactFeedbackGenerator - .medium / .heavy)
   • Triggered when: Photo capture executes.
   • Sensation: Solid mechanical shutter click.

4. Directional Guidance (Custom CoreHaptics Pattern)
   • Triggered when: User requires lateral movement correction.
   • Sensation: Asymmetric directional pulse.
```

---

## 7. Accessibility & Human Factors

* **VoiceOver Support:** The coaching overlay acts as an `AccessibilityLiveRegion`. Surfaced instructions are spoken concisely ("Rotate right three degrees", "Step back").
* **Reduced Motion (`@Environment(\.accessibilityReduceMotion)`):** Disables spring scale oscillations and converts instruction swaps into clean, gentle alpha cross-fades.
* **Dynamic Type Safety:** Viewfinder HUD labels scale up to `.accessibilityMedium` while maintaining strict coordinate bounding boxes to prevent obstructing the camera viewport.
* **High-Contrast Scrim Protection:** Every text label and floating badge is backed by a localized dark gradient scrim ensuring $\ge 4.5:1$ contrast against any camera background (including direct sunlight or white snow).
