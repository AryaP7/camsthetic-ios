import SwiftUI
import CamstheticsEngine

@main
struct CamstheticsApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

/// Minimal placeholder view. Its only job right now is to prove, at runtime,
/// that the application target actually links against CamstheticsEngine
/// (by referencing a public engine type) rather than merely compiling
/// against a stub. No production UI belongs here yet.
private struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Camsthetics")
                .font(.title)
            Text("CamstheticsEngine linked: \(CoachingDimension.allCases.count) dimensions")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
