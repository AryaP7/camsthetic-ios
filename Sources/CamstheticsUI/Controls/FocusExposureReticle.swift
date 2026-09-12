import SwiftUI

/// Tap-to-Focus & Exposure reticle — `docs/PRODUCT_SPEC.md` §1.5:
/// "Single tap places a 70×70pt animated yellow reticle and sets AF/AE
/// point (auto-cancels after 3s). Sliding the sun icon adjacent to the
/// reticle adjusts exposure compensation (±2.0 EV). Long press locks
/// AE/AF with an on-screen 'AE/AF LOCK' yellow indicator."
///
/// Mock only: `onDragExposure`/`onLongPress` mutate `CameraMockupState`
/// values, never a real `AVCaptureDevice`'s exposure properties.
public struct FocusExposureReticle: View {
    public var position: CGPoint
    public var isExpanded: Bool
    public var isLocked: Bool
    public var exposureBiasEV: Double
    public var onDragExposure: (Double) -> Void
    public var onLongPress: () -> Void

    public init(
        position: CGPoint,
        isExpanded: Bool,
        isLocked: Bool,
        exposureBiasEV: Double,
        onDragExposure: @escaping (Double) -> Void,
        onLongPress: @escaping () -> Void
    ) {
        self.position = position
        self.isExpanded = isExpanded
        self.isLocked = isLocked
        self.exposureBiasEV = exposureBiasEV
        self.onDragExposure = onDragExposure
        self.onLongPress = onLongPress
    }

    private let reticleSize: CGFloat = 70
    private let sliderTrackHeight: CGFloat = 90

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .stroke(CamColor.yellow, lineWidth: 1.5)
                .frame(width: reticleSize, height: reticleSize)
                .onLongPressGesture(perform: onLongPress)
                .accessibilityLabel("Focus and exposure point")
                .accessibilityValue(isLocked ? "Locked" : "Unlocked")
                .accessibilityHint("Double tap and hold to lock focus and exposure")
                .accessibilityAddTraits(.isButton)

            if isLocked {
                Text("AE/AF Lock")
                    .camInstructionLabelStyle()
                    .foregroundStyle(CamColor.yellow)
                    .offset(y: -reticleSize / 2 - 16)
                    .transition(.opacity)
            }

            if isExpanded {
                exposureSlider
                    .offset(x: reticleSize / 2 + 18)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .position(position)
        .animation(CamAnimation.gentle, value: isExpanded)
        .animation(CamAnimation.snappy, value: isLocked)
    }

    private var exposureSlider: some View {
        VStack {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 13))
                .foregroundStyle(CamColor.yellow)
        }
        .frame(width: 28, height: sliderTrackHeight, alignment: .center)
        .offset(y: CGFloat(-exposureBiasEV / 2.0) * (sliderTrackHeight / 2))
        .background(
            Capsule().fill(CamColor.glassMaterial).frame(width: 4, height: sliderTrackHeight)
        )
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let normalized = -value.location.y / (sliderTrackHeight / 2)
                    onDragExposure(normalized * 2.0)
                }
        )
        // A drag gesture alone isn't operable by VoiceOver — this exposes
        // the same ±2.0 EV range as a standard adjustable control so it
        // can be moved with a swipe-up/down VoiceOver gesture instead.
        .accessibilityElement()
        .accessibilityLabel("Exposure compensation")
        .accessibilityValue(String(format: "%+.1f EV", exposureBiasEV))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onDragExposure(exposureBiasEV + 0.1)
            case .decrement: onDragExposure(exposureBiasEV - 0.1)
            @unknown default: break
            }
        }
    }
}

#Preview {
    ZStack {
        Color.black
        FocusExposureReticle(
            position: CGPoint(x: 200, y: 300),
            isExpanded: true,
            isLocked: false,
            exposureBiasEV: 0.6,
            onDragExposure: { _ in },
            onLongPress: {}
        )
    }
}
