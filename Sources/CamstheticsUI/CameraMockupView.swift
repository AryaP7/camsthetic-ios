import SwiftUI

// MARK: - Composed camera mockup screen (Track B — UI/design only)
//
// Assembles every component in `Viewfinder/` and `Controls/` into the
// full-screen layout documented in `docs/DESIGN_SYSTEM.md` §4's ASCII
// diagram (top status bar → instruction pill → level line → ghost frame →
// score meter → lens/zoom pill → mode carousel → bottom action triad).
//
// This view NEVER imports CamstheticsServices and NEVER calls
// CameraService — see `CameraMockupState.swift`'s doc comment. The
// `background` parameter is exactly the seam that lets a real camera feed
// be substituted later without touching this file's layout: today the
// demo (`CameraMockupDemoView`) passes a placeholder gradient; a future
// production screen would pass the App target's real
// `CameraPreviewView(cameraService:)` here instead — this file doesn't
// know or care which.
public struct CameraMockupView<Background: View>: View {
    @Bindable private var state: CameraMockupState
    private let background: () -> Background

    public init(state: CameraMockupState, @ViewBuilder background: @escaping () -> Background) {
        self.state = state
        self.background = background
    }

    public var body: some View {
        GeometryReader { proxy in
            let isLandscape = proxy.size.width > proxy.size.height

            ZStack {
                background()
                    .ignoresSafeArea()

                RuleOfThirdsGrid(isVisible: state.showRuleOfThirdsGrid)
                    .ignoresSafeArea()

                if let reticle = state.reticlePosition {
                    FocusExposureReticle(
                        position: reticle,
                        isExpanded: state.isExposureExpanded,
                        isLocked: state.isAEAFLocked,
                        exposureBiasEV: state.exposureBiasEV,
                        onDragExposure: { state.dragExposure(to: $0) },
                        onLongPress: { state.lockAEAF() }
                    )
                }

                VStack {
                    TopStatusBar(
                        isFlashOn: state.isFlashOn,
                        isDrawerExpanded: state.isDrawerExpanded,
                        isRawEnabled: state.isRawEnabled,
                        onFlashTap: { state.toggleFlash() },
                        onChevronTap: { state.toggleDrawer() }
                    )
                    CameraHealthBanner(health: state.cameraHealth)
                        .padding(.top, 4)
                    Spacer(minLength: 8)
                    hudCluster
                    Spacer(minLength: 8)
                }
                .padding(.top, 4)

                if isLandscape {
                    HStack {
                        Spacer()
                        controlCluster(isLandscape: true)
                            .padding(.trailing, 20)
                    }
                } else {
                    VStack {
                        Spacer()
                        controlCluster(isLandscape: false)
                            .padding(.bottom, 20)
                    }
                }

                VStack {
                    HStack {
                        Spacer()
                        FocalLengthIndicator(focalLengthMM: state.focalLengthMM)
                            .padding(.trailing, 16)
                    }
                    .padding(.top, 60)
                    Spacer()
                }
            }
            .contentShape(Rectangle())
            // `.simultaneousGesture`, NOT `.onTapGesture`/`.gesture` — a
            // plain `.gesture` attachment is EXCLUSIVE over this whole
            // ZStack's subtree, so it silently won the gesture arena
            // against `FocusExposureReticle`'s own `DragGesture` on its
            // sun-icon slider: dragging that slider never fired a single
            // `onChanged`, confirmed on a physical iPhone 16 by
            // `CameraScreenTests.testExposureSliderReachesRealHardware`
            // (`exposureRequested` stayed pinned at 0.00 across two
            // different drag-synthesis techniques). `.simultaneousGesture`
            // lets both this tap-to-focus gesture AND any descendant's own
            // gesture (the exposure slider, and any future control) recognize
            // independently instead of one exclusively claiming the touch.
            .simultaneousGesture(
                SpatialTapGesture().onEnded { value in
                    state.focusAndExpose(at: value.location)
                }
            )
        }
    }

    /// Instruction pill → spirit level → ghost silhouette → score badge,
    /// stacked in the exact order DESIGN_SYSTEM.md §4's diagram shows.
    private var hudCluster: some View {
        VStack(spacing: 14) {
            InstructionPill(symbolName: state.instructionSymbolName, text: state.instructionText)
            SpiritLevelIndicator(rollDegrees: state.rollDegrees, isLevel: state.isLevel)
            Spacer(minLength: 30)
            GhostSilhouette(isOnTarget: state.isOnTarget)
            Spacer(minLength: 30)
            HStack {
                Spacer()
                ScoreBadge(score: state.matchScore, isOnTarget: state.isOnTarget)
            }
            .padding(.horizontal, 24)
        }
    }

    /// Lens pill → mode carousel → bottom action triad. Anchored to the
    /// bottom thumb deck in portrait (`docs/DESIGN_SYSTEM.md` §1's
    /// "Spatial Ergonomics" principle); anchored to the trailing edge in
    /// landscape, matching the same one-handed-reachability intent when
    /// the device is rotated (not itself specified numerically in the
    /// docs, so kept minimal rather than invented in detail).
    @ViewBuilder
    private func controlCluster(isLandscape: Bool) -> some View {
        if isLandscape {
            VStack(spacing: 16) {
                LensZoomPill(options: state.lensOptions, selectedID: state.selectedLensID) { state.selectLens($0) }
                ModeCarousel(selected: state.selectedMode) { state.selectMode($0) }
                BottomActionTriad(
                    thumbnailSystemImage: state.lastPhotoThumbnailSystemImage,
                    isShutterPressed: state.isShutterPressed,
                    autoCaptureProgress: state.autoCaptureProgress,
                    onGalleryTap: {},
                    onShutterTap: { state.triggerMockCapture() },
                    onTargetTap: {}
                )
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 8)
            .background(CamColor.glassMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        } else {
            VStack(spacing: 18) {
                LensZoomPill(options: state.lensOptions, selectedID: state.selectedLensID) { state.selectLens($0) }
                ModeCarousel(selected: state.selectedMode) { state.selectMode($0) }
                BottomActionTriad(
                    thumbnailSystemImage: state.lastPhotoThumbnailSystemImage,
                    isShutterPressed: state.isShutterPressed,
                    autoCaptureProgress: state.autoCaptureProgress,
                    onGalleryTap: {},
                    onShutterTap: { state.triggerMockCapture() },
                    onTargetTap: {}
                )
            }
        }
    }
}
