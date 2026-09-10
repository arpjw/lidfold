import Foundation

struct FoldParameters: Equatable {
    let progress: Double
    let perspective: Double
    let blurRadius: Double
    let shadowOpacity: Double

    static func map(
        angle: Double,
        clearAt clearAngle: Double = 78,
        fullyFoldedAt foldedAngle: Double = 8
    ) -> FoldParameters {
        let span = max(clearAngle - foldedAngle, 1)
        let progress = min(max((clearAngle - angle) / span, 0), 1)
        let eased = progress * progress * (3 - 2 * progress)

        return FoldParameters(
            progress: eased,
            perspective: 0.72 * eased,
            blurRadius: 18 * eased,
            shadowOpacity: 0.46 * eased
        )
    }
}
