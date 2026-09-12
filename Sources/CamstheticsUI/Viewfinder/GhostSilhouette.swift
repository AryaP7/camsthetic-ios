import SwiftUI

/// Ghost Subject Silhouette — `docs/DESIGN_SYSTEM.md` §4.3. Rounded
/// rectangular outline (1.5pt hairline stroke). Searching/approaching:
/// 40% opacity neutral white. Locked on-target (≥85%): 90% opacity
/// System Green with a subtle 1.02× breathing pulse.
public struct GhostSilhouette: View {
    public var isOnTarget: Bool
    public var frameSize: CGSize

    /// `docs/DESIGN_SYSTEM.md` §7: "Reduced Motion... Disables spring
    /// scale oscillations." The breathing pulse is exactly that.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(isOnTarget: Bool, frameSize: CGSize = CGSize(width: 170, height: 230)) {
        self.isOnTarget = isOnTarget
        self.frameSize = frameSize
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .strokeBorder(
                isOnTarget ? CamColor.targetGreen : CamColor.textPrimary,
                style: StrokeStyle(lineWidth: 1.5, dash: isOnTarget ? [] : [6, 5])
            )
            .frame(width: frameSize.width, height: frameSize.height)
            .opacity(isOnTarget ? 0.9 : 0.4)
            .scaleEffect(isOnTarget && !reduceMotion ? 1.02 : 1.0)
            .animation(
                isOnTarget && !reduceMotion
                    ? .easeInOut(duration: 1.4).repeatForever(autoreverses: true)
                    : CamAnimation.gentle,
                value: isOnTarget
            )
    }
}

#Preview {
    ZStack {
        Color.black
        HStack(spacing: 32) {
            GhostSilhouette(isOnTarget: false)
            GhostSilhouette(isOnTarget: true)
        }
    }
}
