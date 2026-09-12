import SwiftUI

/// Focal-length indicator. Not itself named in `docs/DESIGN_SYSTEM.md`'s
/// component list, but the lens/zoom system (§1.5 of `PRODUCT_SPEC.md`)
/// implies a focal-length readout is meaningful alongside the zoom pill;
/// kept minimal (tabular figures, glass pill, matching every other
/// numeric readout's styling) and structured to receive a real value
/// later without changing its API.
public struct FocalLengthIndicator: View {
    public var focalLengthMM: Double

    public init(focalLengthMM: Double) {
        self.focalLengthMM = focalLengthMM
    }

    public var body: some View {
        Text(String(format: "%.0fmm", focalLengthMM))
            .camTabularStyle()
            .foregroundStyle(CamColor.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(CamColor.glassMaterial, in: Capsule())
            .animation(CamAnimation.gentle, value: focalLengthMM)
            .accessibilityLabel("Focal length")
            .accessibilityValue("\(Int(focalLengthMM)) millimeters")
    }
}

#Preview {
    ZStack {
        Color.black
        FocalLengthIndicator(focalLengthMM: 24)
    }
}
