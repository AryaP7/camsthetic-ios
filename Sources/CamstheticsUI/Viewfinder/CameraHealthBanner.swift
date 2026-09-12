import SwiftUI

/// Presents `CameraHealthPresentation` states that aren't simply "running
/// normally" — mirrors the overlay pattern already used in
/// `App/Camsthetics/CameraPreviewView.swift` (Track A) so a future
/// integration can show the same message shape for the same underlying
/// states, without this module depending on `CamstheticsServices`.
public struct CameraHealthBanner: View {
    public var health: CameraHealthPresentation

    public init(health: CameraHealthPresentation) {
        self.health = health
    }

    public var body: some View {
        Group {
            switch health {
            case .running:
                EmptyView()
            case .idle:
                banner("Camera idle")
            case .starting:
                banner("Starting camera…")
            case .interrupted(let reason):
                banner("Camera interrupted: \(reason)")
            case .recovering:
                banner("Resuming camera…")
            case .failed(let description):
                banner("Camera error: \(description)")
            case .permissionDenied:
                banner("Camera access denied — enable it in Settings")
            }
        }
        .animation(CamAnimation.gentle, value: health)
    }

    private func banner(_ message: String) -> some View {
        Text(message)
            .font(CamFont.secondary())
            .foregroundStyle(CamColor.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(CamColor.glassMaterial, in: Capsule())
    }
}

#Preview {
    ZStack {
        Color.black
        VStack(spacing: 12) {
            CameraHealthBanner(health: .starting)
            CameraHealthBanner(health: .interrupted(reason: "audioDeviceInUseByAnotherClient"))
            CameraHealthBanner(health: .recovering)
            CameraHealthBanner(health: .permissionDenied)
        }
    }
}
