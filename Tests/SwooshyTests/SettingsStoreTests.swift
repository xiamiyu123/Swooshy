import Foundation
import Testing
@testable import Swooshy

private final class NotificationRecorder: @unchecked Sendable {
    private(set) var count = 0
    private(set) var categories: SettingsChangeCategory = []

    func record(_ notification: Notification) {
        count += 1
        categories.formUnion(notification.settingsChangeCategories)
    }
}

@MainActor
struct SettingsStoreTests {
    @Test
    func persistsLanguageAndHotKeyPreferences() {
        let suiteName = "Swooshy.SettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = SettingsStore(userDefaults: defaults)
        store.languageOverride = .simplifiedChinese
        store.hotKeysEnabled = false
        store.statusItemIcon = .windowGrid
        store.dockGesturesEnabled = false
        store.titleBarGesturesEnabled = false
        store.dockCornerDragSnapEnabled = false
        store.titleBarCornerDragSnapEnabled = false
        store.collapseStatusItemWindowActions = true
        store.titleBarOverlayProtectionEnabled = true
        store.smartBrowserTabCloseEnabled = true
        store.titleBarTriggerHeight = 42
        store.titleBarCornerDragHoldDuration = 0.9
        store.updateDockGestureAction(.closeWindow, for: .pinchIn)
        store.updateDockGestureEnabled(false, for: .pinchIn)
        store.updateTitleBarGestureAction(.maximize, for: .swipeLeft)
        store.updateTitleBarGestureEnabled(false, for: .swipeLeft)

        let reloadedStore = SettingsStore(userDefaults: defaults)

        #expect(reloadedStore.languageOverride == .simplifiedChinese)
        #expect(reloadedStore.hotKeysEnabled == false)
        #expect(reloadedStore.statusItemIcon == .windowGrid)
        #expect(reloadedStore.dockGesturesEnabled == false)
        #expect(reloadedStore.titleBarGesturesEnabled == false)
        #expect(reloadedStore.dockCornerDragSnapEnabled == false)
        #expect(reloadedStore.titleBarCornerDragSnapEnabled == false)
        #expect(reloadedStore.collapseStatusItemWindowActions == true)
        #expect(reloadedStore.titleBarOverlayProtectionEnabled == true)
        #expect(reloadedStore.smartBrowserTabCloseEnabled == true)
        #expect(reloadedStore.titleBarTriggerHeight == 42)
        #expect(reloadedStore.titleBarCornerDragHoldDuration == 0.9)
        #expect(reloadedStore.dockGestureAction(for: .pinchIn) == .closeWindow)
        #expect(reloadedStore.dockGestureIsEnabled(for: .pinchIn) == false)
        #expect(reloadedStore.titleBarGestureAction(for: .swipeLeft) == .maximize)
        #expect(reloadedStore.titleBarGestureIsEnabled(for: .swipeLeft) == false)
    }

    @Test
    func persistsDebugLoggingPreference() {
        let suiteName = "Swooshy.SettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = SettingsStore(userDefaults: defaults)
        store.debugLoggingEnabled = true

        let reloadedStore = SettingsStore(userDefaults: defaults)

        #expect(reloadedStore.debugLoggingEnabled == true)
    }

    @Test
    func persistsCustomHotKeyBinding() {
        let suiteName = "Swooshy.SettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = SettingsStore(userDefaults: defaults)
        store.updateHotKeyKey(.w, for: .maximize)
        store.updateHotKeyModifiers(.commandShift, for: .maximize)

        let reloadedStore = SettingsStore(userDefaults: defaults)
        let binding = reloadedStore.hotKeyBinding(for: .maximize)

        #expect(binding.key == .w)
        #expect(binding.modifiers == .commandShift)
    }

    @Test
    func swapsConflictingBindingsToKeepShortcutsUnique() {
        let suiteName = "Swooshy.SettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = SettingsStore(userDefaults: defaults)
        let originalLeft = store.hotKeyBinding(for: .leftHalf)
        let originalCenter = store.hotKeyBinding(for: .center)

        store.updateHotKeyBinding(
            HotKeyBinding(
                action: .center,
                key: originalLeft.key,
                modifiers: originalLeft.modifiers
            )
        )

        #expect(store.hotKeyBinding(for: .center).key == originalLeft.key)
        #expect(store.hotKeyBinding(for: .leftHalf).key == originalCenter.key)
    }

    @Test
    func systemLanguageUsesCurrentPreferredLanguages() {
        let suiteName = "Swooshy.SettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = SettingsStore(userDefaults: defaults)
        #expect(store.preferredLanguages.isEmpty == false)
    }

    @Test
    func welcomeGuideFlagIsConsumedOnlyOnceAndPersists() {
        let suiteName = "Swooshy.SettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = SettingsStore(userDefaults: defaults)
        #expect(store.hasSeenWelcomeGuide == false)
        #expect(store.consumeWelcomeGuidePresentationFlag() == true)
        #expect(store.hasSeenWelcomeGuide == true)
        #expect(store.consumeWelcomeGuidePresentationFlag() == false)

        let reloadedStore = SettingsStore(userDefaults: defaults)
        #expect(reloadedStore.hasSeenWelcomeGuide == true)
        #expect(reloadedStore.consumeWelcomeGuidePresentationFlag() == false)
    }

    @Test
    func resetPersistedConfigurationClearsStoredValues() {
        let suiteName = "Swooshy.SettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = SettingsStore(userDefaults: defaults)
        store.languageOverride = .simplifiedChinese
        store.hotKeysEnabled = false
        store.dockGesturesEnabled = false
        store.titleBarGesturesEnabled = false
        store.dockCornerDragSnapEnabled = false
        store.titleBarCornerDragSnapEnabled = false
        store.collapseStatusItemWindowActions = true
        store.titleBarOverlayProtectionEnabled = true
        store.smartBrowserTabCloseEnabled = true
        store.titleBarTriggerHeight = 40
        store.titleBarCornerDragHoldDuration = 1.2
        store.statusItemIcon = .windowGrid
        store.debugLoggingEnabled = true
        _ = store.consumeWelcomeGuidePresentationFlag()
        store.updateDockGestureAction(.closeWindow, for: .pinchIn)

        SettingsStore.resetPersistedConfiguration(in: defaults)
        let reloadedStore = SettingsStore(userDefaults: defaults)

        #expect(reloadedStore.languageOverride == .system)
        #expect(reloadedStore.hotKeysEnabled == true)
        #expect(reloadedStore.dockGesturesEnabled == true)
        #expect(reloadedStore.titleBarGesturesEnabled == true)
        #expect(reloadedStore.dockCornerDragSnapEnabled == true)
        #expect(reloadedStore.titleBarCornerDragSnapEnabled == true)
        #expect(reloadedStore.collapseStatusItemWindowActions == true)
        #expect(reloadedStore.titleBarOverlayProtectionEnabled == true)
        #expect(reloadedStore.smartBrowserTabCloseEnabled == false)
        #expect(reloadedStore.titleBarTriggerHeight == SettingsStore.defaultTitleBarTriggerHeight)
        #expect(reloadedStore.titleBarCornerDragHoldDuration == SettingsStore.defaultTitleBarCornerDragHoldDuration)
        #expect(reloadedStore.statusItemIcon == .gale)
        #expect(reloadedStore.debugLoggingEnabled == false)
        #expect(reloadedStore.hasSeenWelcomeGuide == false)
        #expect(reloadedStore.dockGestureAction(for: .pinchIn) == .quitApplication)
    }

    @Test
    func titleBarOverlayProtectionDefaultsToEnabled() {
        let suiteName = "Swooshy.SettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = SettingsStore(userDefaults: defaults)

        #expect(store.titleBarOverlayProtectionEnabled == true)
    }

    @Test
    func titleBarTriggerHeightDefaultsToStandardHeight() {
        let suiteName = "Swooshy.SettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = SettingsStore(userDefaults: defaults)

        #expect(store.titleBarTriggerHeight == SettingsStore.defaultTitleBarTriggerHeight)
    }

    @Test
    func titleBarCornerDragHoldDurationDefaultsToQuickActivation() {
        let suiteName = "Swooshy.SettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = SettingsStore(userDefaults: defaults)

        #expect(store.titleBarCornerDragHoldDuration == SettingsStore.defaultTitleBarCornerDragHoldDuration)
    }

    @Test
    func cornerDragSnapDefaultsToEnabledForDockAndTitleBar() {
        let suiteName = "Swooshy.SettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = SettingsStore(userDefaults: defaults)

        #expect(store.dockCornerDragSnapEnabled == true)
        #expect(store.titleBarCornerDragSnapEnabled == true)
    }

    @Test
    func statusItemWindowActionsCollapseByDefault() {
        let suiteName = "Swooshy.SettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = SettingsStore(userDefaults: defaults)

        #expect(store.collapseStatusItemWindowActions == true)
    }

    @Test
    func pinchGestureUsesQuitApplicationByDefault() {
        let suiteName = "Swooshy.SettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = SettingsStore(userDefaults: defaults)
        #expect(store.dockGestureAction(for: .pinchIn) == .quitApplication)
    }

    @Test
    func horizontalDockGesturesUseWindowCyclingByDefault() {
        let suiteName = "Swooshy.SettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = SettingsStore(userDefaults: defaults)
        #expect(store.dockGestureAction(for: .swipeLeft) == .cycleWindowsForward)
        #expect(store.dockGestureAction(for: .swipeRight) == .cycleWindowsBackward)
    }

    @Test
    func titleBarGesturesUseExpectedActionsByDefault() {
        let suiteName = "Swooshy.SettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = SettingsStore(userDefaults: defaults)
        #expect(store.titleBarGestureAction(for: .swipeLeft) == .leftHalf)
        #expect(store.titleBarGestureAction(for: .swipeRight) == .rightHalf)
        #expect(store.titleBarGestureAction(for: .swipeDown) == .minimize)
        #expect(store.titleBarGestureAction(for: .swipeUp) == .center)
        #expect(store.titleBarGestureAction(for: .pinchIn) == .closeWindow)
    }

    @Test
    func persistsGestureOnlyExitMaximizeActions() {
        let suiteName = "Swooshy.SettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = SettingsStore(userDefaults: defaults)
        store.updateDockGestureAction(.exitFullScreenWindow, for: .pinchOut)
        store.updateTitleBarGestureAction(.exitFullScreen, for: .pinchOut)

        let reloadedStore = SettingsStore(userDefaults: defaults)

        #expect(reloadedStore.dockGestureAction(for: .pinchOut) == .exitFullScreenWindow)
        #expect(reloadedStore.titleBarGestureAction(for: .pinchOut) == .exitFullScreen)
    }

    @Test
    func legacyGestureBindingsWithoutEnabledFlagsStillDecode() {
        let suiteName = "Swooshy.SettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let legacyDockData = Data("""
        [
          {"gesture":"swipeLeft","action":"closeWindow"},
          {"gesture":"pinchIn","action":"quitApplication"}
        ]
        """.utf8)
        let legacyTitleBarData = Data("""
        [
          {"gesture":"swipeLeft","action":2},
          {"gesture":"swipeUp","action":3}
        ]
        """.utf8)
        defaults.set(legacyDockData, forKey: "settings.dockGestureBindings")
        defaults.set(legacyTitleBarData, forKey: "settings.titleBarGestureBindings")

        let store = SettingsStore(userDefaults: defaults)

        #expect(store.dockGestureAction(for: .swipeLeft) == .closeWindow)
        #expect(store.dockGestureIsEnabled(for: .swipeLeft) == true)
        #expect(store.titleBarGestureAction(for: .swipeLeft) == .maximize)
        #expect(store.titleBarGestureIsEnabled(for: .swipeLeft) == true)
    }

    @Test
    func backwardWindowCyclingHotkeyHasDefaultBinding() {
        let suiteName = "Swooshy.SettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = SettingsStore(userDefaults: defaults)
        let binding = store.hotKeyBinding(for: .cycleSameAppWindowsBackward)

        #expect(binding.key == .grave)
        #expect(binding.modifiers == .commandShiftOptionControl)
    }

    @Test
    func resetPersistedConfigurationPreservesExperimentalBrowserTabCloseOptIn() {
        let suiteName = "Swooshy.SettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = SettingsStore(userDefaults: defaults)
        store.experimentalBrowserTabCloseEnabled = true
        store.smartBrowserTabCloseEnabled = true

        SettingsStore.resetPersistedConfiguration(in: defaults)
        let reloadedStore = SettingsStore(userDefaults: defaults)

        #expect(reloadedStore.experimentalBrowserTabCloseEnabled == true)
        #expect(reloadedStore.smartBrowserTabCloseEnabled == false)
    }

    @Test
    func resetAdvancedSettingsRestoresBrowserTabCloseDefaults() {
        let suiteName = "Swooshy.SettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = SettingsStore(userDefaults: defaults)
        store.experimentalBrowserTabCloseEnabled = true
        store.smartBrowserTabCloseEnabled = true
        store.titleBarOverlayProtectionEnabled = false
        store.smartPinchExitFullScreenEnabled = false
        store.reverseCancelEnabled = false
        store.reverseCancelSensitivity = 0.8
        store.swipeSensitivity = 0.2
        store.pinchSensitivity = 0.7
        store.titleBarTriggerHeight = 48
        store.titleBarCornerDragHoldDuration = 1.0

        store.resetAdvancedSettingsToDefaults()

        #expect(store.experimentalBrowserTabCloseEnabled == false)
        #expect(store.smartBrowserTabCloseEnabled == false)
        #expect(store.titleBarOverlayProtectionEnabled == true)
        #expect(store.smartPinchExitFullScreenEnabled == true)
        #expect(store.reverseCancelEnabled == true)
        #expect(store.reverseCancelSensitivity == 0.5)
        #expect(store.swipeSensitivity == 0.5)
        #expect(store.pinchSensitivity == 0.5)
        #expect(store.titleBarTriggerHeight == SettingsStore.defaultTitleBarTriggerHeight)
        #expect(store.titleBarCornerDragHoldDuration == SettingsStore.defaultTitleBarCornerDragHoldDuration)
    }

    @Test
    func titleBarTriggerHeightClampsPersistedAndAssignedValues() {
        let suiteName = "Swooshy.SettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(
            SettingsStore.maximumTitleBarTriggerHeight + 10,
            forKey: "settings.titleBarTriggerHeight"
        )

        let store = SettingsStore(userDefaults: defaults)
        #expect(store.titleBarTriggerHeight == SettingsStore.maximumTitleBarTriggerHeight)

        store.titleBarTriggerHeight = SettingsStore.minimumTitleBarTriggerHeight - 10
        #expect(store.titleBarTriggerHeight == SettingsStore.minimumTitleBarTriggerHeight)

        let reloadedStore = SettingsStore(userDefaults: defaults)
        #expect(reloadedStore.titleBarTriggerHeight == SettingsStore.minimumTitleBarTriggerHeight)
    }

    @Test
    func titleBarCornerDragHoldDurationClampsPersistedAndAssignedValues() {
        let suiteName = "Swooshy.SettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(
            SettingsStore.minimumTitleBarCornerDragHoldDuration - 0.1,
            forKey: "settings.titleBarCornerDragHoldDuration"
        )

        let store = SettingsStore(userDefaults: defaults)
        #expect(store.titleBarCornerDragHoldDuration == SettingsStore.minimumTitleBarCornerDragHoldDuration)

        store.titleBarCornerDragHoldDuration = SettingsStore.maximumTitleBarCornerDragHoldDuration + 1
        #expect(store.titleBarCornerDragHoldDuration == SettingsStore.maximumTitleBarCornerDragHoldDuration)

        let reloadedStore = SettingsStore(userDefaults: defaults)
        #expect(reloadedStore.titleBarCornerDragHoldDuration == SettingsStore.maximumTitleBarCornerDragHoldDuration)
    }

    @Test
    func disablingExperimentalBrowserTabCloseDisablesSmartModeAndCoalescesNotification() async {
        let suiteName = "Swooshy.SettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = SettingsStore(userDefaults: defaults)
        store.experimentalBrowserTabCloseEnabled = true
        store.smartBrowserTabCloseEnabled = true

        let recorder = NotificationRecorder()
        let token = NotificationCenter.default.addObserver(
            forName: .settingsDidChange,
            object: store,
            queue: .main
        ) { notification in
            recorder.record(notification)
        }
        defer {
            NotificationCenter.default.removeObserver(token)
        }

        store.experimentalBrowserTabCloseEnabled = false

        for _ in 0 ..< 3 {
            await Task.yield()
        }

        #expect(store.experimentalBrowserTabCloseEnabled == false)
        #expect(store.smartBrowserTabCloseEnabled == false)
        #expect(recorder.count == 1)
        #expect(recorder.categories == [.advancedGestureBehavior])
    }

    @Test
    func coalescesSynchronousSettingsChangeNotifications() async {
        let suiteName = "Swooshy.SettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = SettingsStore(userDefaults: defaults)
        let recorder = NotificationRecorder()
        let token = NotificationCenter.default.addObserver(
            forName: .settingsDidChange,
            object: store,
            queue: .main
        ) { notification in
            recorder.record(notification)
        }
        defer {
            NotificationCenter.default.removeObserver(token)
        }

        store.hotKeysEnabled = false
        store.dockGesturesEnabled = false
        store.titleBarGesturesEnabled = false

        for _ in 0 ..< 3 {
            await Task.yield()
        }

        #expect(recorder.count == 1)
        #expect(recorder.categories.contains(.hotKeys))
        #expect(recorder.categories.contains(.gestureMonitoring))
    }
}
