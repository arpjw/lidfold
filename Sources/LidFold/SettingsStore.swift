import Foundation

/// User-configurable fold behavior persisted in the standard preferences domain.
@MainActor
final class SettingsStore: ObservableObject {
    struct Defaults: Equatable {
        var activationAngle = 76.0
        var deactivationAngle = 80.0
        var maximumBlurRadius = 18.0
        var maximumPerspective = 0.72
        var maximumShadowOpacity = 0.46
        var effectEnabledAtLaunch = false
        var launchAtLogin = false
        var reducedMotion = false
    }

    @Published private(set) var activationAngle: Double
    @Published private(set) var deactivationAngle: Double
    @Published private(set) var maximumBlurRadius: Double
    @Published private(set) var maximumPerspective: Double
    @Published private(set) var maximumShadowOpacity: Double
    @Published private(set) var effectEnabledAtLaunch: Bool
    @Published private(set) var launchAtLogin: Bool
    @Published private(set) var reducedMotion: Bool

    private let preferences: UserDefaults
    private let defaults: Defaults

    init(preferences: UserDefaults = .standard, defaults: Defaults = Defaults()) {
        self.preferences = preferences
        self.defaults = defaults

        let storedActivation = Self.double(
            forKey: Key.activationAngle,
            in: preferences,
            default: defaults.activationAngle,
            range: 5...89
        )
        let storedDeactivation = Self.double(
            forKey: Key.deactivationAngle,
            in: preferences,
            default: defaults.deactivationAngle,
            range: 6...100
        )

        let normalizedActivation = min(storedActivation, storedDeactivation - 1)
        activationAngle = normalizedActivation
        deactivationAngle = max(storedDeactivation, normalizedActivation + 1)
        maximumBlurRadius = Self.double(
            forKey: Key.maximumBlurRadius,
            in: preferences,
            default: defaults.maximumBlurRadius,
            range: 0...40
        )
        maximumPerspective = Self.double(
            forKey: Key.maximumPerspective,
            in: preferences,
            default: defaults.maximumPerspective,
            range: 0...1
        )
        maximumShadowOpacity = Self.double(
            forKey: Key.maximumShadowOpacity,
            in: preferences,
            default: defaults.maximumShadowOpacity,
            range: 0...1
        )
        effectEnabledAtLaunch = Self.bool(
            forKey: Key.effectEnabledAtLaunch,
            in: preferences,
            default: defaults.effectEnabledAtLaunch
        )
        launchAtLogin = Self.bool(
            forKey: Key.launchAtLogin,
            in: preferences,
            default: defaults.launchAtLogin
        )
        reducedMotion = Self.bool(
            forKey: Key.reducedMotion,
            in: preferences,
            default: defaults.reducedMotion
        )
    }

    func setActivationAngle(_ value: Double) {
        activationAngle = Self.clamp(value, to: 5...min(89, deactivationAngle - 1))
        preferences.set(activationAngle, forKey: Key.activationAngle)
    }

    func setDeactivationAngle(_ value: Double) {
        deactivationAngle = Self.clamp(value, to: max(6, activationAngle + 1)...100)
        preferences.set(deactivationAngle, forKey: Key.deactivationAngle)
    }

    func setMaximumBlurRadius(_ value: Double) {
        maximumBlurRadius = Self.clamp(value, to: 0...40)
        preferences.set(maximumBlurRadius, forKey: Key.maximumBlurRadius)
    }

    func setMaximumPerspective(_ value: Double) {
        maximumPerspective = Self.clamp(value, to: 0...1)
        preferences.set(maximumPerspective, forKey: Key.maximumPerspective)
    }

    func setMaximumShadowOpacity(_ value: Double) {
        maximumShadowOpacity = Self.clamp(value, to: 0...1)
        preferences.set(maximumShadowOpacity, forKey: Key.maximumShadowOpacity)
    }

    func setEffectEnabledAtLaunch(_ enabled: Bool) {
        effectEnabledAtLaunch = enabled
        preferences.set(enabled, forKey: Key.effectEnabledAtLaunch)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLogin = enabled
        preferences.set(enabled, forKey: Key.launchAtLogin)
    }

    func setReducedMotion(_ enabled: Bool) {
        reducedMotion = enabled
        preferences.set(enabled, forKey: Key.reducedMotion)
    }

    func restoreDefaults() {
        activationAngle = defaults.activationAngle
        deactivationAngle = defaults.deactivationAngle
        preferences.set(activationAngle, forKey: Key.activationAngle)
        preferences.set(deactivationAngle, forKey: Key.deactivationAngle)
        setMaximumBlurRadius(defaults.maximumBlurRadius)
        setMaximumPerspective(defaults.maximumPerspective)
        setMaximumShadowOpacity(defaults.maximumShadowOpacity)
        setEffectEnabledAtLaunch(defaults.effectEnabledAtLaunch)
        setLaunchAtLogin(defaults.launchAtLogin)
        setReducedMotion(defaults.reducedMotion)
    }

    private static func double(
        forKey key: String,
        in preferences: UserDefaults,
        default defaultValue: Double,
        range: ClosedRange<Double>
    ) -> Double {
        guard let number = preferences.object(forKey: key) as? NSNumber else {
            return defaultValue
        }
        return clamp(number.doubleValue, to: range)
    }

    private static func bool(
        forKey key: String,
        in preferences: UserDefaults,
        default defaultValue: Bool
    ) -> Bool {
        (preferences.object(forKey: key) as? NSNumber)?.boolValue ?? defaultValue
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        guard value.isFinite else { return range.lowerBound }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    private enum Key {
        static let activationAngle = "settings.activationAngle"
        static let deactivationAngle = "settings.deactivationAngle"
        static let maximumBlurRadius = "settings.maximumBlurRadius"
        static let maximumPerspective = "settings.maximumPerspective"
        static let maximumShadowOpacity = "settings.maximumShadowOpacity"
        static let effectEnabledAtLaunch = "settings.effectEnabledAtLaunch"
        static let launchAtLogin = "settings.launchAtLogin"
        static let reducedMotion = "settings.reducedMotion"
    }
}
