import SwiftUI

/// Spirit Horizon Indicator — `docs/DESIGN_SYSTEM.md` §4.2. Two hairline
/// bars (1.5pt stroke, 28pt width each) with a center gap. Rotates with
/// device roll in translucent white while unlevel; when `|Δθ| ≤ 0.5°`
/// (the caller decides this via `isLevel`), bars snap horizontal and
/// illuminate Apple Camera Yellow.
public struct SpiritLevelIndicator: View {
    public var rollDegrees: Double
    public var isLevel: Bool

    public init(rollDegrees: Double, isLevel: Bool) {
        self.rollDegrees = rollDegrees
        self.isLevel = isLevel
    }

    private var barColor: Color { isLevel ? CamColor.yellow : CamColor.textPrimary.opacity(0.5) }

    public var body: some View {
        HStack(spacing: 14) {
            Rectangle().fill(barColor).frame(width: 28, height: 1.5)
            Rectangle().fill(barColor).frame(width: 28, height: 1.5)
        }
        .rotationEffect(.degrees(isLevel ? 0 : rollDegrees))
        .animation(.interactiveSpring(response: 0.15, dampingFraction: 0.9), value: rollDegrees)
        .animation(CamAnimation.snappy, value: isLevel)
    }
}

#Preview {
    ZStack {
        Color.black
        VStack(spacing: 24) {
            SpiritLevelIndicator(rollDegrees: -6, isLevel: false)
            SpiritLevelIndicator(rollDegrees: 0, isLevel: true)
        }
    }
}
