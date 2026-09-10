import Foundation

struct FoldParameters: Equatable {
    let progress: Double
    let perspective: Double
    let blurRadius: Double
    let shadowOpacity: Double

    static func map(
        angle: Double,
        clearAt clearAngle: Double = 78,
        fullyFoldedAt foldedAngle: Double = 8,
        maximumPerspective: Double = 0.72,
        maximumBlurRadius: Double = 18,
        maximumShadowOpacity: Double = 0.46,
        reducedMotion: Bool = false
    ) -> FoldParameters {
        let span = max(clearAngle - foldedAngle, 1)
        let progress = min(max((clearAngle - angle) / span, 0), 1)
        let eased = progress * progress * (3 - 2 * progress)
        let motionProgress = reducedMotion ? 0 : eased

        return FoldParameters(
            progress: motionProgress,
            perspective: min(max(maximumPerspective, 0), 1) * motionProgress,
            blurRadius: min(max(maximumBlurRadius, 0), 40) * motionProgress,
            shadowOpacity: min(max(maximumShadowOpacity, 0), 1) * eased
        )
    }
}
