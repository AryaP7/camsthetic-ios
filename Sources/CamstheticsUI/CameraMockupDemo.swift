import SwiftUI

// MARK: - Temporary UI-only demo/preview surface (Track B)
//
// Lets the whole camera mockup be reviewed without any camera hardware —
// a design/mockup surface, not the final production camera implementation.
// Owns its own `CameraMockupState` and a placeholder gradient background
// standing in for the live feed (see `CameraMockupView`'s doc comment for
// how a real background gets substituted later).
//
// A small dev toolbar exercises interaction states (idle / pressed /
// selected / disabled / expanded / collapsed / dragging / transition) on
// demand, so this screen can be reviewed as a finished design surface in
// one sitting rather than requiring many manual taps.
public struct CameraMockupDemoView: View {
    @State private var state = CameraMockupState()
    @State private var showDevToolbar = true

    public init() {}

    public var body: some View {
        ZStack(alignment: .topLeading) {
            CameraMockupView(state: state) {
                placeholderBackground
            }

            if showDevToolbar {
                devToolbar
                    .padding(.top, 100)
                    .padding(.leading, 12)
            }
        }
        // statusBarHidden()/persistentSystemOverlays() are iOS-only —
        // guarded so this target still builds on macOS (this package's
        // fast cross-platform build/test tier); this whole view is a
        // camera-mockup screen meaningful on iOS only regardless.
        #if os(iOS)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        #endif
    }

    /// Stands in for the live camera feed — clearly a placeholder (a
    /// gradient + a faint viewfinder glyph), never a real capture path.
    private var placeholderBackground: some View {
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.16), Color(white: 0.05)],
                startPoint: .top,
                endPoint: .bottom
            )
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 120, weight: .ultraLight))
                .foregroundStyle(.white.opacity(0.06))
        }
    }

    private var devToolbar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MOCKUP CONTROLS")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.5))

            devButton("Toggle On-Target") {
                state.isOnTarget.toggle()
                state.matchScore = state.isOnTarget ? 91 : 58
                state.instructionText = state.isOnTarget ? "Hold steady" : "Rotate left 3°"
                state.instructionSymbolName = state.isOnTarget ? "checkmark" : "arrow.counterclockwise"
            }
            devButton("Toggle Level") {
                state.isLevel.toggle()
                state.rollDegrees = state.isLevel ? 0 : -4.5
            }
            devButton("Toggle Grid") { state.toggleGrid() }
            devButton("Simulate Capture") { state.triggerMockCapture() }
            devButton("Toggle Auto-Capture Ring") {
                state.autoCaptureProgress = state.autoCaptureProgress == nil ? 0.4 : nil
            }
            devButton("Cycle Focal Length") {
                let lengths: [Double] = [13, 24, 48, 77]
                let next = lengths.first(where: { $0 > state.focalLengthMM }) ?? lengths[0]
                state.focalLengthMM = next
            }
            devButton("Clear Reticle") { state.clearReticle() }
            devButton("Cycle Camera Health") {
                let sequence: [CameraHealthPresentation] = [
                    .running, .starting, .recovering,
                    .interrupted(reason: "audioDeviceInUseByAnotherClient"),
                    .failed(description: "Mock runtime error"), .permissionDenied
                ]
                let currentIndex = sequence.firstIndex(of: state.cameraHealth) ?? 0
                state.cameraHealth = sequence[(currentIndex + 1) % sequence.count]
            }
            devButton("Hide Controls") { showDevToolbar = false }
        }
        .padding(10)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
    }

    private func devButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    CameraMockupDemoView()
}
