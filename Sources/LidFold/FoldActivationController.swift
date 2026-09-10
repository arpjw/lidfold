import Foundation

/// Applies hysteresis to hinge readings so capture and rendering do not flap near the cutoff.
@MainActor
final class FoldActivationController {
    let activationAngle: Double
    let deactivationAngle: Double

    private(set) var isActive = false

    init(activationAngle: Double = 76, deactivationAngle: Double = 80) {
        precondition(activationAngle < deactivationAngle)
        self.activationAngle = activationAngle
        self.deactivationAngle = deactivationAngle
    }

    @discardableResult
    func update(angle: Double?) -> Bool {
        guard let angle, angle.isFinite, (0...180).contains(angle) else {
            isActive = false
            return false
        }

        if isActive {
            if angle > deactivationAngle {
                isActive = false
            }
        } else if angle < activationAngle {
            isActive = true
        }

        return isActive
    }

    func deactivate() {
        isActive = false
    }
}
