import SwiftUI

/// The Apple Shutter Button — `docs/DESIGN_SYSTEM.md` §4.4. Outer ring
/// 72pt/3pt stroke, solid core 62pt scaling to 54pt on press (0.2s
/// spring, damping 0.70 — close to `snappySpring`'s 0.22s/0.72, used
/// here for consistency with §5's own "Shutter Button Press/Release" row
/// which names `snappySpring`). Auto-capture ring: green countdown
/// stroke filling the outer ring.
///
/// Mock only — `onTap` never calls `AVCapturePhotoOutput`; the caller
/// (`CameraMockupState.triggerMockCapture()`) only flips local view state.
public struct ShutterButton: View {
    public var isPressed: Bool
    /// `nil` when auto-capture isn't armed; `0...1` fills the countdown ring.
    public var autoCaptureProgress: Double?
    public var onTap: () -> Void

    public init(isPressed: Bool, autoCaptureProgress: Double?, onTap: @escaping () -> Void) {
        self.isPressed = isPressed
        self.autoCaptureProgress = autoCaptureProgress
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle()
                    .stroke(CamColor.textPrimary, lineWidth: 3)
                    .frame(width: 72, height: 72)

                if let progress = autoCaptureProgress {
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(CamColor.targetGreen, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 72, height: 72)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.1), value: progress)
                }

                Circle()
                    .fill(CamColor.textPrimary)
                    .frame(width: isPressed ? 54 : 62, height: isPressed ? 54 : 62)
            }
        }
        .buttonStyle(.plain)
        .animation(CamAnimation.snappy, value: isPressed)
        .contentShape(Circle())
        .accessibilityLabel("Shutter")
        .accessibilityHint(autoCaptureProgress != nil ? "Auto-capture counting down" : "Takes a photo")
    }
}

#Preview {
    ZStack {
        Color.black
        HStack(spacing: 32) {
            ShutterButton(isPressed: false, autoCaptureProgress: nil, onTap: {})
            ShutterButton(isPressed: true, autoCaptureProgress: nil, onTap: {})
            ShutterButton(isPressed: false, autoCaptureProgress: 0.6, onTap: {})
        }
    }
}
