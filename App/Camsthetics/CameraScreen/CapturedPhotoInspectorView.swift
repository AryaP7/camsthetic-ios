import SwiftUI

// MARK: - Full-screen, pinch-zoomable captured-photo inspector
//
// Displays exactly the `UIImage` decoded from `CameraService.capturePhoto()`'s
// unmodified bytes — nothing here resizes, re-encodes, or processes it
// further. Originally written for `PreviewValidationScaffold.swift`'s Part 5
// hardware-checkpoint review (judging fine detail/sharpness/artifacts
// on-device without pulling files to a Mac); shared here (not `private`,
// not duplicated) so `CameraScreen` — the production camera screen — gets
// the same real-photo review the scaffold always had, rather than silently
// discarding every capture.
struct CapturedPhotoInspectorView: View {
    let image: UIImage
    let label: String
    let onClose: () -> Void

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = max(1.0, min(lastScale * value, 8.0))
                        }
                        .onEnded { _ in lastScale = scale }
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            guard scale > 1.0 else { return }
                            offset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                        }
                        .onEnded { _ in lastOffset = offset }
                )
                .onTapGesture(count: 2) {
                    scale = 1.0; lastScale = 1.0
                    offset = .zero; lastOffset = .zero
                }

            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.6), in: Capsule())
                Spacer()
                Button("Close", action: onClose)
                    .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }
}
