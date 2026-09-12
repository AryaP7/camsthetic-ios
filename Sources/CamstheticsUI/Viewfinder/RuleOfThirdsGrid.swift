import SwiftUI

/// Rule-of-thirds composition grid. This is the only grid system
/// documented anywhere in the project's specs — `docs/PRD.md`'s §"Physical,
/// Actionable Guidance" principle: "if a subject cannot be detected, it
/// falls back to sensor-exact horizon leveling and rule-of-thirds scene
/// cues," and `docs/PRODUCT_SPEC.md` §1.4's MINIMAL confidence tier
/// ("Horizon Line Placement (Rule of Thirds)"). No other named grid
/// (golden ratio, diagonal, etc.) is specified, so none is implemented
/// here — inventing one would be undocumented product functionality.
///
/// Visually subtle per the design brief: thin hairlines, low opacity, so
/// the overlay never competes with the live subject.
public struct RuleOfThirdsGrid: View {
    public var isVisible: Bool

    public init(isVisible: Bool) {
        self.isVisible = isVisible
    }

    public var body: some View {
        GeometryReader { proxy in
            Path { path in
                let width = proxy.size.width
                let height = proxy.size.height
                for i in 1...2 {
                    let x = width * CGFloat(i) / 3
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: height))

                    let y = height * CGFloat(i) / 3
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: width, y: y))
                }
            }
            .stroke(CamColor.textPrimary.opacity(0.28), lineWidth: 0.75)
        }
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(false)
        .animation(CamAnimation.gentle, value: isVisible)
    }
}

#Preview {
    ZStack {
        Color.black
        RuleOfThirdsGrid(isVisible: true)
    }
}
