import SwiftUI

// MARK: - Phase 2.0 — Capture Fidelity Proof screen (THROWAWAY UI)
//
// Deliberately minimal: three buttons (Trials A/B/C) and a status log. No design
// system, no production navigation. See CaptureFidelityProofHarness.swift for the
// constraints this whole feature exists under and is expected to be deleted after.

struct CaptureFidelityProofView: View {
    @StateObject private var harness = CaptureFidelityProofHarness()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Capture Fidelity Proof")
                    .font(.title2.bold())
                Spacer()
                Button("Close") { dismiss() }
            }

            Text("Physical device only — do not run in the Simulator. Each trial reconfigures the capture session and takes one photo via AVCapturePhotoOutput.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                ForEach(CaptureFidelityTrial.allCases) { trial in
                    Button("Run \(trial.rawValue)") {
                        harness.runTrial(trial)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(harness.isBusy)
                }
                if harness.isBusy {
                    ProgressView()
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                ForEach(CaptureFidelityTrial.allCases) { trial in
                    Text(trial.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let urls = harness.lastArtifactURLs {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Last artifacts (Documents/CaptureFidelityProof/):")
                        .font(.caption.bold())
                    Text(urls.photo.lastPathComponent)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                    Text(urls.json.lastPathComponent)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }

            Divider()

            Text("Status log")
                .font(.caption.bold())
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(harness.statusLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(.caption, design: .monospaced))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
    }
}
