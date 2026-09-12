import SwiftUI

/// Horizontal Mode Carousel — `docs/DESIGN_SYSTEM.md` §4: "PHOTO COACH
/// SCAN PORTRAIT". Horizontal scroll/tap interaction; selection uses
/// `interactiveSpring` (§5's "Drawer Chevron Expand/Collapse" curve — the
/// carousel isn't itself named in the animation table, so the nearest
/// documented interactive-selection curve is used rather than inventing a
/// new one).
public struct ModeCarousel: View {
    public var modes: [CaptureMode]
    public var selected: CaptureMode
    public var onSelect: (CaptureMode) -> Void

    public init(modes: [CaptureMode] = CaptureMode.allCases, selected: CaptureMode, onSelect: @escaping (CaptureMode) -> Void) {
        self.modes = modes
        self.selected = selected
        self.onSelect = onSelect
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    ForEach(modes) { mode in
                        Button {
                            withAnimation(CamAnimation.interactive) { onSelect(mode) }
                        } label: {
                            Text(mode.rawValue)
                                .camModeLabelStyle()
                                .foregroundStyle(mode == selected ? CamColor.yellow : CamColor.textSecondary)
                        }
                        .buttonStyle(.plain)
                        // 44pt minimum hit target (Apple HIG) even though
                        // the visual label is smaller — DESIGN_SYSTEM.md
                        // doesn't specify a pixel hit-target for this
                        // control, so this is an accessibility fix, not a
                        // deviation from a documented value.
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                        .accessibilityLabel("\(mode.rawValue.capitalized) mode")
                        .accessibilityAddTraits(mode == selected ? [.isSelected] : [])
                        .id(mode)
                    }
                }
                .padding(.horizontal, 20)
            }
            .onChange(of: selected) { _, newValue in
                withAnimation(CamAnimation.interactive) { proxy.scrollTo(newValue, anchor: .center) }
            }
        }
        .frame(height: 44)
    }
}

#Preview {
    ZStack {
        Color.black
        ModeCarousel(selected: .coach, onSelect: { _ in })
    }
}
