// CoachingEngine.swift
// CamstheticsEngine
// Unified pure Swift coaching engine facade orchestrating normalization, diffing, hysteresis, and scoring.

import Foundation

/// Output state emitted by `CoachingEngine` for each evaluated frame.
public struct CoachingOutput: Equatable, Sendable {
    /// Match score percentage (0–100).
    public var score: Int

    /// Active confidence tier (FULL, PARTIAL, MINIMAL).
    public var tier: ConfidenceTier

    /// Prioritized and hysteresis-filtered surfaced movement instructions (at most 2).
    public var surfacedInstructions: [CoachingInstruction]

    /// Whether framing has achieved the On-Target threshold (>=85%).
    public var isOnTarget: Bool

    /// On-Target and auto-capture detailed state.
    public var onTargetState: OnTargetState

    /// Target composition normalized to common aspect ratio.
    public var normalizedTarget: CompositionParams

    /// Live composition normalized to common aspect ratio.
    public var normalizedLive: CompositionParams

    /// 5D spatial delta between normalized target and live compositions.
    public var delta: CompositionDelta

    /// Frame evaluation timestamp.
    public var timestamp: TimeInterval

    public init(
        score: Int,
        tier: ConfidenceTier,
        surfacedInstructions: [CoachingInstruction],
        isOnTarget: Bool,
        onTargetState: OnTargetState,
        normalizedTarget: CompositionParams,
        normalizedLive: CompositionParams,
        delta: CompositionDelta,
        timestamp: TimeInterval
    ) {
        self.score = score
        self.tier = tier
        self.surfacedInstructions = surfacedInstructions
        self.isOnTarget = isOnTarget
        self.onTargetState = onTargetState
        self.normalizedTarget = normalizedTarget
        self.normalizedLive = normalizedLive
        self.delta = delta
        self.timestamp = timestamp
    }
}

/// Unified, thread-safe, deterministic pure Swift Coaching Engine.
public struct CoachingEngine: Equatable, Sendable {
    private var tierResolver: TierResolver
    private var hysteresisFilter: AntiFlickerFilter
    private var onTargetGate: OnTargetGate

    public init() {
        self.tierResolver = TierResolver()
        self.hysteresisFilter = AntiFlickerFilter()
        self.onTargetGate = OnTargetGate()
    }

    /// Evaluates a live camera frame against an ingested target reference image.
    /// - Parameters:
    ///   - target: Raw extracted composition parameters from the reference target.
    ///   - live: Raw extracted composition parameters from the live camera viewfinder.
    ///   - timestamp: Monotonic frame timestamp in seconds.
    ///   - autoCaptureEnabled: Whether auto-capture shutter triggers are active.
    ///   - useZoomFallback: Whether to surface zoom instructions instead of distance stepping.
    /// - Returns: Complete `CoachingOutput` containing score, instructions, and target lock state.
    public mutating func processFrame(
        target: CompositionParams,
        live: CompositionParams,
        timestamp: TimeInterval,
        autoCaptureEnabled: Bool = false,
        useZoomFallback: Bool = false
    ) -> CoachingOutput {
        // Step 1: Aspect Normalization (PRODUCT_SPEC.md 1.2.1)
        let commonAspect = AspectNormalizer.commonAspect(
            targetAspect: target.aspectRatio,
            liveAspect: live.aspectRatio
        )
        let normTarget = AspectNormalizer.normalizeComposition(target, commonAspect: commonAspect)
        let normLive = AspectNormalizer.normalizeComposition(live, commonAspect: commonAspect)

        // Step 2: Confidence Tier Resolution with 5-frame stability (PRODUCT_SPEC.md 1.4.2)
        let activeTier = tierResolver.update(target: normTarget, live: normLive)

        // Step 3: 5D Spatial Delta Computation (PRODUCT_SPEC.md 1.3.1)
        let delta = DeltaEngine.computeDelta(target: normTarget, live: normLive)

        // Step 4: Anti-Chatter Hysteresis & Priority Surfacing (PRODUCT_SPEC.md 1.3.3)
        var surfaced = hysteresisFilter.update(
            delta: delta,
            target: normTarget,
            live: normLive,
            timestamp: timestamp,
            useZoomFallback: useZoomFallback
        )

        // If tier is PARTIAL the live subject is missing: surface "Tilt active + Find your subject"
        // (PRODUCT_SPEC.md 1.4.2). Tilt is the only dimension measurable without a live subject, so an
        // active tilt cue keeps its slot and is never replaced by the prompt; any residual subject-dependent
        // cue (which can outlive the 5-frame tier transition) is dropped so it cannot crowd out the prompt
        // or collide with `.findSubject` on the lateral dimension.
        if activeTier == .partial {
            var partialSurfaced = [CoachingInstruction]()
            if let tiltCue = surfaced.first(where: { $0.dimension == .tilt }) {
                partialSurfaced.append(tiltCue)
            }
            if !partialSurfaced.contains(.findSubject) {
                partialSurfaced.append(.findSubject)
            }
            surfaced = Array(partialSurfaced.prefix(AntiFlickerFilter.maxSurfacedInstructions))
        }

        // Step 5: Gaussian Match Scoring (PRODUCT_SPEC.md 1.4.1)
        let score = GaussianMatchScorer.computeScore(delta: delta, tier: activeTier)

        // Step 6: On-Target Gate & Auto-Capture countdown (PRODUCT_SPEC.md 1.4.1 & 1.5.2)
        let onTargetState = onTargetGate.update(
            score: score,
            tier: activeTier,
            timestamp: timestamp,
            autoCaptureEnabled: autoCaptureEnabled
        )

        return CoachingOutput(
            score: score,
            tier: activeTier,
            surfacedInstructions: surfaced,
            isOnTarget: onTargetState.isOnTarget,
            onTargetState: onTargetState,
            normalizedTarget: normTarget,
            normalizedLive: normLive,
            delta: delta,
            timestamp: timestamp
        )
    }

    /// Resets all internal hysteresis state, dwell timers, and gates.
    public mutating func reset() {
        tierResolver.reset()
        hysteresisFilter.reset()
        onTargetGate.reset()
    }
}
