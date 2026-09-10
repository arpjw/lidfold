import Foundation
import XCTest
@testable import LidFold

@MainActor
final class SettingsStoreTests: XCTestCase {
    func testUsesConservativeDefaults() {
        let (suiteName, preferences) = makePreferences()
        defer { preferences.removePersistentDomain(forName: suiteName) }
        let store = SettingsStore(preferences: preferences)

        XCTAssertEqual(store.activationAngle, 76)
        XCTAssertEqual(store.deactivationAngle, 80)
        XCTAssertEqual(store.maximumBlurRadius, 18)
        XCTAssertEqual(store.maximumPerspective, 0.72)
        XCTAssertEqual(store.maximumShadowOpacity, 0.46)
        XCTAssertFalse(store.effectEnabledAtLaunch)
        XCTAssertFalse(store.launchAtLogin)
        XCTAssertFalse(store.reducedMotion)
    }

    func testPersistsAllSettings() {
        let (suiteName, preferences) = makePreferences()
        defer { preferences.removePersistentDomain(forName: suiteName) }
        var store = SettingsStore(preferences: preferences)
        store.setActivationAngle(68)
        store.setDeactivationAngle(84)
        store.setMaximumBlurRadius(24)
        store.setMaximumPerspective(0.6)
        store.setMaximumShadowOpacity(0.3)
        store.setEffectEnabledAtLaunch(true)
        store.setLaunchAtLogin(true)
        store.setReducedMotion(true)

        store = SettingsStore(preferences: preferences)
        XCTAssertEqual(store.activationAngle, 68)
        XCTAssertEqual(store.deactivationAngle, 84)
        XCTAssertEqual(store.maximumBlurRadius, 24)
        XCTAssertEqual(store.maximumPerspective, 0.6)
        XCTAssertEqual(store.maximumShadowOpacity, 0.3)
        XCTAssertTrue(store.effectEnabledAtLaunch)
        XCTAssertTrue(store.launchAtLogin)
        XCTAssertTrue(store.reducedMotion)
    }

    func testClampsValuesAndPreservesThresholdGap() {
        let (suiteName, preferences) = makePreferences()
        defer { preferences.removePersistentDomain(forName: suiteName) }
        let store = SettingsStore(preferences: preferences)

        store.setDeactivationAngle(70)
        store.setActivationAngle(90)
        XCTAssertEqual(store.activationAngle, 69)

        store.setDeactivationAngle(20)
        XCTAssertEqual(store.deactivationAngle, 70)

        store.setMaximumBlurRadius(200)
        store.setMaximumPerspective(-1)
        store.setMaximumShadowOpacity(.infinity)
        XCTAssertEqual(store.maximumBlurRadius, 40)
        XCTAssertEqual(store.maximumPerspective, 0)
        XCTAssertEqual(store.maximumShadowOpacity, 0)
    }

    private func makePreferences() -> (String, UserDefaults) {
        let suiteName = "SettingsStoreTests.\(UUID().uuidString)"
        return (suiteName, UserDefaults(suiteName: suiteName)!)
    }
}
