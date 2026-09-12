import SwiftUI

/// Bottom Action Triad — `docs/DESIGN_SYSTEM.md` §4: "[🖼️ Gallery]
/// (⚪️ Shutter) [🎯 Target]" — "Recent Capture / Shutter Button /
/// Reference Peek". Anchored in the bottom 30% thumb deck per §1's
/// "Spatial Ergonomics" principle.
public struct BottomActionTriad: View {
    /// SF Symbol name for the last-photo thumbnail; `nil` is the
    /// documented empty state (no capture yet this session).
    public var thumbnailSystemImage: String?
    public var isShutterPressed: Bool
    public var autoCaptureProgress: Double?
    public var onGalleryTap: () -> Void
    public var onShutterTap: () -> Void
    public var onTargetTap: () -> Void

    public init(
        thumbnailSystemImage: String?,
        isShutterPressed: Bool,
        autoCaptureProgress: Double?,
        onGalleryTap: @escaping () -> Void,
        onShutterTap: @escaping () -> Void,
        onTargetTap: @escaping () -> Void
    ) {
        self.thumbnailSystemImage = thumbnailSystemImage
        self.isShutterPressed = isShutterPressed
        self.autoCaptureProgress = autoCaptureProgress
        self.onGalleryTap = onGalleryTap
        self.onShutterTap = onShutterTap
        self.onTargetTap = onTargetTap
    }

    public var body: some View {
        HStack {
            Button(action: onGalleryTap) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.10))
                    if let symbol = thumbnailSystemImage {
                        Image(systemName: symbol)
                            .font(.system(size: 16))
                            .foregroundStyle(CamColor.textSecondary)
                    }
                }
                .frame(width: 44, height: 44)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(CamColor.textPrimary.opacity(0.4), lineWidth: 1)
                )
            }
            .accessibilityLabel("Recent capture")
            .accessibilityValue(thumbnailSystemImage == nil ? "No photos yet" : "")
            .accessibilityHint("Opens your recent captures")

            Spacer()

            ShutterButton(isPressed: isShutterPressed, autoCaptureProgress: autoCaptureProgress, onTap: onShutterTap)

            Spacer()

            Button(action: onTargetTap) {
                Image(systemName: "target")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(CamColor.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(CamColor.glassMaterial, in: Circle())
            }
            .accessibilityLabel("Reference target")
            .accessibilityHint("Shows the target photo you're matching")
        }
        .padding(.horizontal, 36)
    }
}

#Preview {
    ZStack {
        Color.black
        BottomActionTriad(
            thumbnailSystemImage: nil,
            isShutterPressed: false,
            autoCaptureProgress: nil,
            onGalleryTap: {},
            onShutterTap: {},
            onTargetTap: {}
        )
    }
}
