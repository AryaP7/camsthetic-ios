import SwiftUI

/// Top status bar — `docs/DESIGN_SYSTEM.md` §4: "[⚡️ Flash] [▲ Drawer
/// Chevron] [RAW / Live]", 20pt SF Symbols.
public struct TopStatusBar: View {
    public var isFlashOn: Bool
    public var isDrawerExpanded: Bool
    public var isRawEnabled: Bool
    public var onFlashTap: () -> Void
    public var onChevronTap: () -> Void

    public init(
        isFlashOn: Bool,
        isDrawerExpanded: Bool,
        isRawEnabled: Bool,
        onFlashTap: @escaping () -> Void,
        onChevronTap: @escaping () -> Void
    ) {
        self.isFlashOn = isFlashOn
        self.isDrawerExpanded = isDrawerExpanded
        self.isRawEnabled = isRawEnabled
        self.onFlashTap = onFlashTap
        self.onChevronTap = onChevronTap
    }

    public var body: some View {
        HStack {
            Button(action: onFlashTap) {
                Image(systemName: isFlashOn ? "bolt.fill" : "bolt.slash.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(isFlashOn ? CamColor.yellow : CamColor.textPrimary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Flash")
            .accessibilityValue(isFlashOn ? "On" : "Off")
            .accessibilityAddTraits(isFlashOn ? [.isSelected] : [])

            Spacer()

            Button(action: onChevronTap) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(CamColor.textPrimary)
                    .rotationEffect(.degrees(isDrawerExpanded ? 180 : 0))
                    .frame(width: 44, height: 44)
            }
            .animation(CamAnimation.interactive, value: isDrawerExpanded)
            .accessibilityLabel("Camera settings")
            .accessibilityValue(isDrawerExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint("Shows additional camera controls")

            Spacer()

            Text(isRawEnabled ? "RAW" : "LIVE")
                .camModeLabelStyle()
                .foregroundStyle(CamColor.textSecondary)
                .frame(width: 44)
                .accessibilityLabel(isRawEnabled ? "RAW capture mode" : "Live capture mode")
        }
        .padding(.horizontal, 12)
        .background(CamColor.textScrim.frame(height: 100), alignment: .top)
    }
}

#Preview {
    ZStack {
        Color.black
        TopStatusBar(
            isFlashOn: false,
            isDrawerExpanded: false,
            isRawEnabled: false,
            onFlashTap: {},
            onChevronTap: {}
        )
    }
}
