import SwiftUI

/// Dynamic Score Meter — `docs/DESIGN_SYSTEM.md` §4: "( 88% Match )".
/// Tabular figures (`.monospacedDigit()`) so the number updating never
/// shifts surrounding layout.
public struct ScoreBadge: View {
    public var score: Int
    public var isOnTarget: Bool

    public init(score: Int, isOnTarget: Bool) {
        self.score = score
        self.isOnTarget = isOnTarget
    }

    public var body: some View {
        Text("\(score)% Match")
            .camTabularStyle()
            .foregroundStyle(isOnTarget ? CamColor.targetGreen : CamColor.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(CamColor.glassMaterial, in: Capsule())
            .animation(CamAnimation.gentle, value: score)
            .accessibilityLabel("Composition match")
            .accessibilityValue(isOnTarget ? "\(score) percent, on target" : "\(score) percent")
    }
}

#Preview {
    ZStack {
        Color.black
        VStack(spacing: 12) {
            ScoreBadge(score: 62, isOnTarget: false)
            ScoreBadge(score: 88, isOnTarget: true)
        }
    }
}
