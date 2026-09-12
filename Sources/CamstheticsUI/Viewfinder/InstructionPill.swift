import SwiftUI

/// Floating Instruction Pill (HUD) — `docs/DESIGN_SYSTEM.md` §4.1.
/// Frosted glass capsule, height 36pt, padding 12pt horizontal, directional
/// SF Symbol + concise uppercase copy. Motion: interactive spring on text
/// change (`gentleSpring`, per §5's "Instruction Pill Swap" row).
public struct InstructionPill: View {
    public var symbolName: String
    public var text: String

    /// `docs/DESIGN_SYSTEM.md` §7: "Reduced Motion... converts instruction
    /// swaps into clean, gentle alpha cross-fades" (rather than the
    /// default scale+opacity transition).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(symbolName: String, text: String) {
        self.symbolName = symbolName
        self.text = text
    }

    public var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbolName)
                .font(.system(size: 14, weight: .semibold))
            Text(text)
                .camInstructionLabelStyle()
                // DESIGN_SYSTEM.md §7: "scale up to .accessibilityMedium"
                // (UIKit's UIContentSizeCategory naming). SwiftUI's
                // equivalent scale is DynamicTypeSize.accessibility1 — the
                // first accessibility tier, matching accessibilityMedium's
                // position in UIKit's category ordering.
                .dynamicTypeSize(...(.accessibility1))
        }
        .foregroundStyle(CamColor.textPrimary)
        .padding(.horizontal, 12)
        .frame(minHeight: 36)
        .background(CamColor.glassMaterial, in: Capsule())
        .id(text)
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.92)))
        .animation(CamAnimation.gentle, value: text)
        .accessibilityElement(children: .combine)
        // DESIGN_SYSTEM.md §7: "The coaching overlay acts as an
        // AccessibilityLiveRegion. Surfaced instructions are spoken
        // concisely." `.accessibilityAddTraits(.updatesFrequently)` is
        // SwiftUI's live-region equivalent — VoiceOver announces new
        // values without the view needing focus first.
        .accessibilityAddTraits(.updatesFrequently)
    }
}

#Preview {
    ZStack {
        Color.black
        InstructionPill(symbolName: "arrow.counterclockwise", text: "Rotate left 3°")
    }
}
