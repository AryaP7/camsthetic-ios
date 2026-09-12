import SwiftUI
import CamstheticsEngine
import CamstheticsUI

@main
struct CamstheticsApp: App {
    @State private var showDebugMenu = false

    var body: some Scene {
        WindowGroup {
            CameraScreen()
                #if DEBUG
                .onAppear {
                    // Environment-variable auto-open hooks — same reasoning
                    // as before: lets device testing reach specific screens
                    // over `devicectl` without a human tapping through menus.
                    let env = ProcessInfo.processInfo.environment
                    if env["CAMSTHETICS_AUTO_OPEN_PREVIEW"] == "1" || env["CAMSTHETICS_AUTO_VALIDATE"] == "1" {
                        showDebugMenu = true
                    }
                }
                .sheet(isPresented: $showDebugMenu) {
                    DebugMenuView()
                }
                // Triple-tap opens the debug menu — unobtrusive gesture that
                // won't conflict with single-tap focus/expose or pinch-to-zoom.
                .onTapGesture(count: 3) {
                    showDebugMenu = true
                }
                #endif
        }
    }
}

// MARK: - Debug harness menu (DEBUG builds only)

#if DEBUG
/// Development-only menu providing access to the phase-specific test
/// harnesses (fidelity proof, preview validation, mockup demo, vision
/// smoke test). Accessible via triple-tap on the camera screen. Each
/// harness owns its own `CameraService` instances — they are isolated,
/// disposable, and never share state with the production `CameraScreen`.
private struct DebugMenuView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showCaptureFidelityProof = false
    @State private var showPreviewValidation = false
    @State private var showCameraMockupDemo = false
    @State private var showVisionSmokeTest = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("Camsthetics Debug")
                    .font(.title)
                Text("CamstheticsEngine linked: \(CoachingDimension.allCases.count) dimensions")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button("Capture Fidelity Proof (Phase 2.0)") {
                    showCaptureFidelityProof = true
                }
                .padding(.top, 24)

                Button("Preview Validation (Phase 2.2)") {
                    showPreviewValidation = true
                }

                Button("Camera UI Mockup (Design)") {
                    showCameraMockupDemo = true
                }

                Button("Vision Smoke Test (Phase 3)") {
                    showVisionSmokeTest = true
                }
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .fullScreenCover(isPresented: $showCaptureFidelityProof) {
            CaptureFidelityProofView()
        }
        .fullScreenCover(isPresented: $showPreviewValidation) {
            PreviewValidationScaffold()
        }
        .fullScreenCover(isPresented: $showCameraMockupDemo) {
            CameraMockupDemoView()
        }
        .fullScreenCover(isPresented: $showVisionSmokeTest) {
            VisionSmokeTestView()
        }
        .onAppear {
            let env = ProcessInfo.processInfo.environment
            if env["CAMSTHETICS_AUTO_OPEN_PREVIEW"] == "1" || env["CAMSTHETICS_AUTO_VALIDATE"] == "1" {
                showPreviewValidation = true
            }
            if env["CAMSTHETICS_AUTO_OPEN_VISION_SMOKE_TEST"] == "1" {
                showVisionSmokeTest = true
            }
        }
    }
}
#endif
