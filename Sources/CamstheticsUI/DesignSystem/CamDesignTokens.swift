import SwiftUI

// MARK: - Design tokens (Track B — UI mockup only)
//
// Direct translation of `docs/DESIGN_SYSTEM.md` §2/§3/§5 into SwiftUI. This
// module has zero dependency on CamstheticsServices/CamstheticsEngine —
// it is pure presentation, deliberately kept architecturally separate so
// UI work never touches CameraService or capture logic (see this file's
// sibling `CameraMockupView.swift` for the "no CameraService calls"
// constraint this whole module honors).

/// Color tokens — `docs/DESIGN_SYSTEM.md` §2.
public enum CamColor {
    public static let background = Color.black
    public static let textPrimary = Color.white
    public static let textSecondary = Color.white.opacity(0.65)
    public static let textTertiary = Color.white.opacity(0.40)
    /// Apple Camera Yellow, `#FFCC00`.
    public static let yellow = Color(red: 1.0, green: 0.8, blue: 0.0)
    /// Apple System Green, `#34C759`.
    public static let targetGreen = Color(red: 0.204, green: 0.780, blue: 0.349)
    public static let glassMaterial: Material = .ultraThinMaterial
    public static let textScrim = LinearGradient(
        colors: [Color.black.opacity(0.4), Color.black.opacity(0.0)],
        startPoint: .top,
        endPoint: .bottom
    )
}

/// Typography — `docs/DESIGN_SYSTEM.md` §3. Font *sizes/weights* only;
/// tracking/case transforms are applied via the `View` extensions below
/// since SwiftUI expresses those as view modifiers, not `Font` properties.
public enum CamFont {
    public static func largeTitle() -> Font { .system(size: 28, weight: .bold, design: .default) }
    public static func instructionLabel() -> Font { .system(size: 15, weight: .semibold, design: .default) }
    public static func tabular() -> Font { .system(size: 14, weight: .medium, design: .default) }
    public static func secondary() -> Font { .system(size: 12, weight: .regular, design: .default) }
    public static func modeLabel() -> Font { .system(size: 13, weight: .medium, design: .default) }
}

public extension View {
    /// "Instruction Label: SF Pro Text Semibold, 15pt, uppercase, +1.0pt tracking."
    func camInstructionLabelStyle() -> some View {
        self.font(CamFont.instructionLabel()).tracking(1.0).textCase(.uppercase)
    }

    /// "Mode Carousel Labels: SF Pro Text Medium, 13pt, uppercase, +0.8pt tracking."
    func camModeLabelStyle() -> some View {
        self.font(CamFont.modeLabel()).tracking(0.8).textCase(.uppercase)
    }

    /// "Strict Tabular Figures: all dynamic numerical readouts must apply
    /// .monospacedDigit() to prevent horizontal layout shudder."
    func camTabularStyle() -> some View {
        self.font(CamFont.tabular()).monospacedDigit()
    }
}

/// Animation curves — `docs/DESIGN_SYSTEM.md` §5.
public enum CamAnimation {
    public static let interactive = Animation.spring(response: 0.30, dampingFraction: 0.80)
    public static let gentle = Animation.spring(response: 0.45, dampingFraction: 0.85)
    public static let snappy = Animation.spring(response: 0.22, dampingFraction: 0.72)
}
