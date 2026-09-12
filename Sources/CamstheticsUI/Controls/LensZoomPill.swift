import SwiftUI

/// Lens / Zoom Pill — `docs/DESIGN_SYSTEM.md` §4: "(.5) ( 1x ) ( 2 ) ( 3 )".
/// `docs/PRODUCT_SPEC.md` §1.5: "Floating glass capsule with .5, 1x, 2,
/// 3x." Options are passed in (mock here; runtime-derived
/// `CamstheticsServices.LensOption`s later — see `CameraMockupView.swift`)
/// — never hard-coded inside this view. Selection uses `snappySpring`
/// (§5's "Lens Switch Pill Tap" row).
public struct LensZoomPill: View {
    public var options: [MockLensOption]
    public var selectedID: String
    public var onSelect: (MockLensOption) -> Void

    public init(options: [MockLensOption], selectedID: String, onSelect: @escaping (MockLensOption) -> Void) {
        self.options = options
        self.selectedID = selectedID
        self.onSelect = onSelect
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                let isSelected = option.id == selectedID
                Button {
                    withAnimation(CamAnimation.snappy) { onSelect(option) }
                } label: {
                    Text(option.label)
                        .camTabularStyle()
                        .foregroundStyle(isSelected ? Color.black : CamColor.textPrimary)
                        .frame(minWidth: 32, minHeight: 32)
                        .background(
                            Circle().fill(isSelected ? CamColor.yellow : Color.clear)
                        )
                        // Visual circle stays 32pt (matches the compact
                        // capsule design); tap target is widened to
                        // Apple HIG's 44pt minimum via contentShape, which
                        // doesn't affect what's drawn.
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(option.label) zoom")
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .padding(4)
        .background(CamColor.glassMaterial, in: Capsule())
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    ZStack {
        Color.black
        LensZoomPill(
            options: [
                MockLensOption(id: "0.5", label: ".5", zoomFactor: 0.5),
                MockLensOption(id: "1", label: "1x", zoomFactor: 1),
                MockLensOption(id: "2", label: "2", zoomFactor: 2),
                MockLensOption(id: "3", label: "3", zoomFactor: 3)
            ],
            selectedID: "1",
            onSelect: { _ in }
        )
    }
}
