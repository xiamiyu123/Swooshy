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
        let defaults = makeUserDefaults()
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
        store.experimentalBrowserTabCloseEnabled = true
        store.experimentalDisplayMoveActionsEnabled = true
        store.smartBrowserTabCloseEnabled = true
        store.closeAndQuitConfirmationEnabled = true
        store.titleBarTriggerHeight = 42
        store.titleBarCornerDragHoldDuration = 0.9
        store.updateDockGestureAction(.closeWindow, for: .pinchIn)
        store.updateDockGestureEnabled(false, for: .pinchIn)
        store.updateTitleBarGestureAction(.maximize, for: .swipeLeft)
        store.updateTitleBarGestureEnabled(false, for: .swipeLeft)

        let reloadedStore = SettingsStore(userDefaults: defaults)

        #expect(reloadedStore.languageOverride == .simplifiedChinese)
        #expect(!reloadedStore.hotKeysEnabled)
        #expect(reloadedStore.statusItemIcon == .windowGrid)
        #expect(!reloadedStore.dockGesturesEnabled)
        #expect(!reloadedStore.titleBarGesturesEnabled)
        #expect(!reloadedStore.dockCornerDragSnapEnabled)
        #expect(!reloadedStore.titleBarCornerDragSnapEnabled)
        #expect(reloadedStore.collapseStatusItemWindowActions)
        #expect(reloadedStore.titleBarOverlayProtectionEnabled)
        #expect(reloadedStore.experimentalBrowserTabCloseEnabled)
        #expect(reloadedStore.experimentalDisplayMoveActionsEnabled)
        #expect(reloadedStore.smartBrowserTabCloseEnabled)
        #expect(reloadedStore.closeAndQuitConfirmationEnabled)
        #expect(reloadedStore.titleBarTriggerHeight == 42)
        #expect(reloadedStore.titleBarCornerDragHoldDuration == 0.9)
        #expect(reloadedStore.dockGestureAction(for: .pinchIn) == .closeWindow)
        #expect(!reloadedStore.dockGestureIsEnabled(for: .pinchIn))
        #expect(reloadedStore.titleBarGestureAction(for: .swipeLeft) == .maximize)
        #expect(!reloadedStore.titleBarGestureIsEnabled(for: .swipeLeft))
    }

    @Test
    func persistsDebugLoggingPreference() {
        let defaults = makeUserDefaults()
        let store = SettingsStore(userDefaults: defaults)
        store.debugLoggingEnabled = true

        let reloadedStore = SettingsStore(userDefaults: defaults)

        #expect(reloadedStore.debugLoggingEnabled)
    }

    @Test
    func persistsCustomHotKeyBinding() {
        let defaults = makeUserDefaults()
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
        let store = makeSettingsStore()
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
    func swapsConflictingShortcutWhenUpdatedActionUsesFallbackBinding() throws {
        let defaults = makeUserDefaults()
        let legacyBindings = HotKeyBindings.defaults.filter { $0.action != .toggleFullScreen }
        defaults.set(try JSONEncoder().encode(legacyBindings), forKey: "settings.hotKeyBindings")

        let store = SettingsStore(userDefaults: defaults)
        let originalCenter = store.hotKeyBinding(for: .center)

        store.updateHotKeyBinding(
            HotKeyBinding(
                action: .toggleFullScreen,
                key: originalCenter.key,
                modifiers: originalCenter.modifiers
            )
        )

        #expect(store.hotKeyBinding(for: .toggleFullScreen).key == originalCenter.key)
        #expect(store.hotKeyBinding(for: .center).key == .f)

        let accelerators = store.hotKeyBindings.map { "\($0.keyCode)-\($0.carbonModifiers)" }
        #expect(Set(accelerators).count == accelerators.count)
    }

    @Test
    func systemLanguageUsesCurrentPreferredLanguages() {
        let store = makeSettingsStore()
        #expect(!store.preferredLanguages.isEmpty)
    }

    @Test
    func welcomeGuideFlagIsConsumedOnlyOnceAndPersists() {
        let defaults = makeUserDefaults()
        let store = SettingsStore(userDefaults: defaults)
        #expect(!store.hasSeenWelcomeGuide)
        #expect(store.consumeWelcomeGuidePresentationFlag())
        #expect(store.hasSeenWelcomeGuide)
        #expect(!store.consumeWelcomeGuidePresentationFlag())

        let reloadedStore = SettingsStore(userDefaults: defaults)
        #expect(reloadedStore.hasSeenWelcomeGuide)
        #expect(!reloadedStore.consumeWelcomeGuidePresentationFlag())
    }

    @Test
    func resetPersistedConfigurationClearsStoredValues() {
        let defaults = makeUserDefaults()
        let store = SettingsStore(userDefaults: defaults)
        store.languageOverride = .simplifiedChinese
        store.hotKeysEnabled = false
        store.dockGesturesEnabled = false
        store.titleBarGesturesEnabled = false
        store.dockCornerDragSnapEnabled = false
        store.titleBarCornerDragSnapEnabled = false
        store.collapseStatusItemWindowActions = true
        store.titleBarOverlayProtectionEnabled = true
        store.smartPinchExitFullScreenEnabled = false
        store.smartBrowserTabCloseEnabled = true
        store.closeAndQuitConfirmationEnabled = true
        store.titleBarTriggerHeight = 40
        store.titleBarCornerDragHoldDuration = 1.2
        store.statusItemIcon = .windowGrid
        store.debugLoggingEnabled = true
        _ = store.consumeWelcomeGuidePresentationFlag()
        store.updateDockGestureAction(.closeWindow, for: .pinchIn)

        SettingsStore.resetPersistedConfiguration(in: defaults)
        let reloadedStore = SettingsStore(userDefaults: defaults)

        #expect(reloadedStore.languageOverride == .system)
        #expect(reloadedStore.hotKeysEnabled)
        #expect(reloadedStore.dockGesturesEnabled)
        #expect(reloadedStore.titleBarGesturesEnabled)
        #expect(reloadedStore.dockCornerDragSnapEnabled)
        #expect(reloadedStore.titleBarCornerDragSnapEnabled)
        #expect(reloadedStore.collapseStatusItemWindowActions)
        #expect(reloadedStore.titleBarOverlayProtectionEnabled)
        #expect(reloadedStore.smartPinchExitFullScreenEnabled)
        #expect(!reloadedStore.smartBrowserTabCloseEnabled)
        #expect(!reloadedStore.closeAndQuitConfirmationEnabled)
        #expect(reloadedStore.titleBarTriggerHeight == SettingsStore.defaultTitleBarTriggerHeight)
        #expect(reloadedStore.titleBarCornerDragHoldDuration == SettingsStore.defaultTitleBarCornerDragHoldDuration)
        #expect(reloadedStore.statusItemIcon == .gale)
        #expect(!reloadedStore.debugLoggingEnabled)
        #expect(!reloadedStore.hasSeenWelcomeGuide)
        #expect(reloadedStore.dockGestureAction(for: .pinchIn) == .quitApplication)
    }

    @Test
    func titleBarOverlayProtectionDefaultsToEnabled() {
        let store = makeSettingsStore()

        #expect(store.titleBarOverlayProtectionEnabled)
    }

    @Test
    func titleBarTriggerHeightDefaultsToStandardHeight() {
        let store = makeSettingsStore()

        #expect(store.titleBarTriggerHeight == SettingsStore.defaultTitleBarTriggerHeight)
    }

    @Test
    func titleBarCornerDragHoldDurationDefaultsToQuickActivation() {
        let store = makeSettingsStore()

        #expect(store.titleBarCornerDragHoldDuration == SettingsStore.defaultTitleBarCornerDragHoldDuration)
    }

    @Test
    func cornerDragSnapDefaultsToEnabledForDockAndTitleBar() {
        let store = makeSettingsStore()

        #expect(store.dockCornerDragSnapEnabled)
        #expect(store.titleBarCornerDragSnapEnabled)
    }

    @Test
    func statusItemWindowActionsCollapseByDefault() {
        let store = makeSettingsStore()

        #expect(store.collapseStatusItemWindowActions)
    }

    @Test
    func pinchGestureUsesQuitApplicationByDefault() {
        let store = makeSettingsStore()
        #expect(store.dockGestureAction(for: .pinchIn) == .quitApplication)
    }

    @Test
    func horizontalDockGesturesUseWindowCyclingByDefault() {
        let store = makeSettingsStore()
        #expect(store.dockGestureAction(for: .swipeLeft) == .cycleWindowsForward)
        #expect(store.dockGestureAction(for: .swipeRight) == .cycleWindowsBackward)
    }

    @Test
    func titleBarGesturesUseExpectedActionsByDefault() {
        let store = makeSettingsStore()
        #expect(store.titleBarGestureAction(for: .swipeLeft) == .leftHalf)
        #expect(store.titleBarGestureAction(for: .swipeRight) == .rightHalf)
        #expect(store.titleBarGestureAction(for: .swipeDown) == .minimize)
        #expect(store.titleBarGestureAction(for: .swipeUp) == .center)
        #expect(store.titleBarGestureAction(for: .pinchIn) == .closeWindow)
    }

    @Test
    func persistsGestureOnlyExitMaximizeActions() {
        let defaults = makeUserDefaults()
        let store = SettingsStore(userDefaults: defaults)
        store.updateDockGestureAction(.exitFullScreenWindow, for: .pinchOut)
        store.updateTitleBarGestureAction(.exitFullScreen, for: .pinchOut)

        let reloadedStore = SettingsStore(userDefaults: defaults)

        #expect(reloadedStore.dockGestureAction(for: .pinchOut) == .exitFullScreenWindow)
        #expect(reloadedStore.titleBarGestureAction(for: .pinchOut) == .exitFullScreen)
    }

    @Test
    func persistsDockGestureDisplayMoveActions() {
        let defaults = makeUserDefaults()
        let store = SettingsStore(userDefaults: defaults)
        store.experimentalDisplayMoveActionsEnabled = true
        store.updateDockGestureAction(.moveWindowToNextDisplay, for: .swipeUp)
        store.updateDockGestureAction(.moveWindowToPreviousDisplay, for: .swipeDown)
        store.updateTitleBarGestureAction(.moveToNextDisplay, for: .swipeRight)

        let reloadedStore = SettingsStore(userDefaults: defaults)

        #expect(reloadedStore.dockGestureAction(for: .swipeUp) == .moveWindowToNextDisplay)
        #expect(reloadedStore.dockGestureAction(for: .swipeDown) == .moveWindowToPreviousDisplay)
        #expect(reloadedStore.titleBarGestureAction(for: .swipeRight) == .moveToNextDisplay)
    }

    @Test
    func displayMoveActionsAreHiddenUntilExperimentalModeIsEnabled() {
        let store = makeSettingsStore()
        let displayMoveWindowActions: Set<WindowAction> = [.moveToNextDisplay, .moveToPreviousDisplay]
        let displayMoveDockActions: Set<DockGestureAction> = [.moveWindowToNextDisplay, .moveWindowToPreviousDisplay]

        #expect(!store.experimentalDisplayMoveActionsEnabled)
        #expect(displayMoveWindowActions.isDisjoint(with: store.availableWindowActions))
        #expect(displayMoveWindowActions.isDisjoint(with: store.availableWindowGestureActions))
        #expect(displayMoveDockActions.isDisjoint(with: store.availableDockGestureActions))
        #expect(store.availableWindowActions.contains(.leftHalf))
        #expect(store.availableDockGestureActions.contains(.minimizeWindow))

        store.experimentalDisplayMoveActionsEnabled = true

        #expect(Set(store.availableWindowActions).isSuperset(of: displayMoveWindowActions))
        #expect(Set(store.availableWindowGestureActions).isSuperset(of: displayMoveWindowActions))
        #expect(Set(store.availableDockGestureActions).isSuperset(of: displayMoveDockActions))
    }

    @Test
    func savedDisplayMoveGestureActionsFallBackWhileExperimentalModeIsDisabled() {
        let store = makeSettingsStore()
        store.experimentalDisplayMoveActionsEnabled = true
        store.updateDockGestureAction(.moveWindowToNextDisplay, for: .swipeUp)
        store.updateTitleBarGestureAction(.moveToPreviousDisplay, for: .swipeDown)

        store.experimentalDisplayMoveActionsEnabled = false

        #expect(store.dockGestureBinding(for: .swipeUp).action == .moveWindowToNextDisplay)
        #expect(store.dockGestureAction(for: .swipeUp) == .restoreWindow)
        #expect(store.titleBarGestureBinding(for: .swipeDown)?.action == .moveToPreviousDisplay)
        #expect(store.titleBarGestureAction(for: .swipeDown) == .minimize)

        store.experimentalDisplayMoveActionsEnabled = true

        #expect(store.dockGestureAction(for: .swipeUp) == .moveWindowToNextDisplay)
        #expect(store.titleBarGestureAction(for: .swipeDown) == .moveToPreviousDisplay)
    }

    @Test
    func assigningDisplayMoveGestureActionsRequiresExperimentalMode() {
        let store = makeSettingsStore()
        store.updateDockGestureAction(.moveWindowToNextDisplay, for: .swipeUp)
        store.updateTitleBarGestureAction(.moveToPreviousDisplay, for: .swipeDown)

        #expect(store.dockGestureBinding(for: .swipeUp).action == .restoreWindow)
        #expect(store.titleBarGestureBinding(for: .swipeDown)?.action == .minimize)
    }

    @Test
    func legacyGestureBindingsWithoutEnabledFlagsStillDecode() {
        let defaults = makeUserDefaults()
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
        #expect(store.dockGestureIsEnabled(for: .swipeLeft))
        #expect(store.titleBarGestureAction(for: .swipeLeft) == .maximize)
        #expect(store.titleBarGestureIsEnabled(for: .swipeLeft))
    }

    @Test
    func corruptPersistedBindingsFallBackToDefaultsAndAreCleared() {
        let defaults = makeUserDefaults()
        defaults.set(Data("{".utf8), forKey: "settings.hotKeyBindings")
        defaults.set(Data("{".utf8), forKey: "settings.dockGestureBindings")
        defaults.set(Data("{".utf8), forKey: "settings.titleBarGestureBindings")

        let store = SettingsStore(userDefaults: defaults)

        #expect(store.hotKeyBindings == HotKeyBindings.defaults)
        #expect(store.dockGestureBindings == DockGestureBindings.defaults)
        #expect(store.titleBarGestureBindings == TitleBarGestureBindings.defaults)
        #expect(defaults.data(forKey: "settings.hotKeyBindings") == nil)
        #expect(defaults.data(forKey: "settings.dockGestureBindings") == nil)
        #expect(defaults.data(forKey: "settings.titleBarGestureBindings") == nil)
    }

    @Test
    func backwardWindowCyclingHotkeyHasDefaultBinding() {
        let store = makeSettingsStore()
        let binding = store.hotKeyBinding(for: .cycleSameAppWindowsBackward)

        #expect(binding.key == .grave)
        #expect(binding.modifiers == .commandShiftOptionControl)
    }

    @Test
    func resetPersistedConfigurationPreservesExperimentalBrowserTabCloseOptIn() {
        let defaults = makeUserDefaults()
        let store = SettingsStore(userDefaults: defaults)
        store.experimentalBrowserTabCloseEnabled = true
        store.experimentalDisplayMoveActionsEnabled = true
        store.smartBrowserTabCloseEnabled = true

        SettingsStore.resetPersistedConfiguration(in: defaults)
        let reloadedStore = SettingsStore(userDefaults: defaults)

        #expect(reloadedStore.experimentalBrowserTabCloseEnabled)
        #expect(reloadedStore.experimentalDisplayMoveActionsEnabled)
        #expect(!reloadedStore.smartBrowserTabCloseEnabled)
    }

    @Test
    func resetAdvancedSettingsRestoresBrowserTabCloseDefaults() {
        let store = makeSettingsStore()
        store.experimentalBrowserTabCloseEnabled = true
        store.experimentalDisplayMoveActionsEnabled = true
        store.smartBrowserTabCloseEnabled = true
        store.titleBarOverlayProtectionEnabled = false
        store.smartPinchExitFullScreenEnabled = false
        store.closeAndQuitConfirmationEnabled = true
        store.reverseCancelEnabled = false
        store.reverseCancelSensitivity = 0.8
        store.swipeSensitivity = 0.2
        store.pinchSensitivity = 0.7
        store.titleBarTriggerHeight = 48
        store.titleBarCornerDragHoldDuration = 1.0

        store.resetAdvancedSettingsToDefaults()

        #expect(!store.experimentalBrowserTabCloseEnabled)
        #expect(!store.experimentalDisplayMoveActionsEnabled)
        #expect(!store.smartBrowserTabCloseEnabled)
        #expect(store.titleBarOverlayProtectionEnabled)
        #expect(store.smartPinchExitFullScreenEnabled)
        #expect(!store.closeAndQuitConfirmationEnabled)
        #expect(store.reverseCancelEnabled)
        #expect(store.reverseCancelSensitivity == 0.5)
        #expect(store.swipeSensitivity == 0.5)
        #expect(store.pinchSensitivity == 0.5)
        #expect(store.titleBarTriggerHeight == SettingsStore.defaultTitleBarTriggerHeight)
        #expect(store.titleBarCornerDragHoldDuration == SettingsStore.defaultTitleBarCornerDragHoldDuration)
    }

    @Test
    func sensitivitySettingsClampPersistedAndAssignedValues() {
        let defaults = makeUserDefaults()
        defaults.set(-0.25, forKey: "settings.reverseCancelSensitivity")
        defaults.set(1.25, forKey: "settings.swipeSensitivity")
        defaults.set(1.5, forKey: "settings.pinchSensitivity")

        let store = SettingsStore(userDefaults: defaults)
        #expect(store.reverseCancelSensitivity == 0)
        #expect(store.swipeSensitivity == 1)
        #expect(store.pinchSensitivity == 1)

        store.reverseCancelSensitivity = 2
        store.swipeSensitivity = -1
        store.pinchSensitivity = 0.35

        #expect(store.reverseCancelSensitivity == 1)
        #expect(store.swipeSensitivity == 0)
        #expect(store.pinchSensitivity == 0.35)

        let reloadedStore = SettingsStore(userDefaults: defaults)
        #expect(reloadedStore.reverseCancelSensitivity == 1)
        #expect(reloadedStore.swipeSensitivity == 0)
        #expect(reloadedStore.pinchSensitivity == 0.35)
    }

    @Test
    func titleBarTriggerHeightClampsPersistedAndAssignedValues() {
        let defaults = makeUserDefaults()
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
        let defaults = makeUserDefaults()
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
        let store = makeSettingsStore()
        store.experimentalBrowserTabCloseEnabled = true
        store.smartBrowserTabCloseEnabled = true
        store.pinchCloseConfirmationEnabled = true

        let recorder = await recordSettingsChanges(from: store) {
            store.experimentalBrowserTabCloseEnabled = false
        }

        #expect(!store.experimentalBrowserTabCloseEnabled)
        #expect(!store.smartBrowserTabCloseEnabled)
        #expect(!store.pinchCloseConfirmationEnabled)
        #expect(recorder.count == 1)
        #expect(recorder.categories == [.advancedGestureBehavior])
    }

    @Test
    func reenablingExperimentalBrowserTabCloseRestoresDefaultPinchConfirmation() {
        let defaults = makeUserDefaults()
        let store = SettingsStore(userDefaults: defaults)

        store.experimentalBrowserTabCloseEnabled = true
        #expect(store.pinchCloseConfirmationEnabled)

        store.experimentalBrowserTabCloseEnabled = false
        #expect(!store.pinchCloseConfirmationEnabled)
        #expect(defaults.object(forKey: "settings.pinchCloseConfirmationEnabled") == nil)

        store.experimentalBrowserTabCloseEnabled = true
        #expect(store.pinchCloseConfirmationEnabled)
    }

    @Test
    func explicitPinchConfirmationOptOutSurvivesExperimentalBrowserTabCloseToggle() {
        let defaults = makeUserDefaults()
        let store = SettingsStore(userDefaults: defaults)

        store.experimentalBrowserTabCloseEnabled = true
        store.pinchCloseConfirmationEnabled = false

        store.experimentalBrowserTabCloseEnabled = false
        store.experimentalBrowserTabCloseEnabled = true

        #expect(!store.pinchCloseConfirmationEnabled)
        #expect(defaults.bool(forKey: "settings.pinchCloseConfirmationEnabled") == false)
        #expect(defaults.object(forKey: "settings.pinchCloseConfirmationEnabled") != nil)
    }

    @Test
    func togglingDisplayMoveExperimentalModeInvalidatesHiddenEntrypoints() async {
        let store = makeSettingsStore()

        let recorder = await recordSettingsChanges(from: store) {
            store.experimentalDisplayMoveActionsEnabled = true
        }

        #expect(recorder.count == 1)
        #expect(
            recorder.categories.isSuperset(
                of: [.hotKeys, .gestureMonitoring, .statusMenu, .gestureHUD, .advancedGestureBehavior]
            )
        )
    }

    @Test
    func browserTabCloseDependentOptionsRequireExperimentalMode() {
        let defaults = makeUserDefaults()
        let store = SettingsStore(userDefaults: defaults)
        store.smartBrowserTabCloseEnabled = true
        store.pinchCloseConfirmationEnabled = true

        #expect(!store.smartBrowserTabCloseEnabled)
        #expect(!store.pinchCloseConfirmationEnabled)
        #expect(!defaults.bool(forKey: "settings.smartBrowserTabCloseEnabled"))
        #expect(!defaults.bool(forKey: "settings.pinchCloseConfirmationEnabled"))
    }

    @Test
    func disablingExperimentalBrowserTabCloseClearsTabCloseGestureActions() {
        let defaults = makeUserDefaults()
        let store = SettingsStore(userDefaults: defaults)
        store.experimentalBrowserTabCloseEnabled = true
        store.updateDockGestureAction(.closeTab, for: .swipeUp)
        store.updateDockGestureEnabled(false, for: .swipeUp)
        store.updateTitleBarGestureAction(.closeTab, for: .pinchOut)
        store.updateTitleBarGestureEnabled(false, for: .pinchOut)

        store.experimentalBrowserTabCloseEnabled = false

        #expect(store.dockGestureAction(for: .swipeUp) == .restoreWindow)
        #expect(!store.dockGestureIsEnabled(for: .swipeUp))
        #expect(store.titleBarGestureAction(for: .pinchOut) == .toggleFullScreen)
        #expect(!store.titleBarGestureIsEnabled(for: .pinchOut))

        let reloadedStore = SettingsStore(userDefaults: defaults)
        #expect(reloadedStore.dockGestureAction(for: .swipeUp) == .restoreWindow)
        #expect(reloadedStore.titleBarGestureAction(for: .pinchOut) == .toggleFullScreen)
    }

    @Test
    func disablingExperimentalBrowserTabCloseWithMappedActionsInvalidatesGestureEntrypoints() async {
        let store = makeSettingsStore()
        store.experimentalBrowserTabCloseEnabled = true
        store.updateDockGestureAction(.closeTab, for: .swipeUp)
        store.updateTitleBarGestureAction(.closeTab, for: .pinchOut)

        let recorder = await recordSettingsChanges(from: store) {
            store.experimentalBrowserTabCloseEnabled = false
        }

        #expect(recorder.count == 1)
        #expect(
            recorder.categories.isSuperset(of: [.gestureMonitoring, .gestureHUD, .advancedGestureBehavior])
        )
    }

    @Test
    func launchSanitizesPersistedTabCloseGestureActionsWhenExperimentalModeIsDisabled() throws {
        let defaults = makeUserDefaults()
        let dockBindings = [
            DockGestureBinding(gesture: .swipeUp, isEnabled: false, action: .closeTab),
        ]
        let titleBarBindings = [
            TitleBarGestureBinding(gesture: .pinchOut, isEnabled: false, action: .closeTab),
        ]
        defaults.set(try JSONEncoder().encode(dockBindings), forKey: "settings.dockGestureBindings")
        defaults.set(try JSONEncoder().encode(titleBarBindings), forKey: "settings.titleBarGestureBindings")
        defaults.set(false, forKey: "settings.experimentalBrowserTabCloseEnabled")
        defaults.set(true, forKey: "settings.smartBrowserTabCloseEnabled")
        defaults.set(true, forKey: "settings.pinchCloseConfirmationEnabled")

        let store = SettingsStore(userDefaults: defaults)

        #expect(!store.smartBrowserTabCloseEnabled)
        #expect(!store.pinchCloseConfirmationEnabled)
        #expect(store.dockGestureAction(for: .swipeUp) == .restoreWindow)
        #expect(!store.dockGestureIsEnabled(for: .swipeUp))
        #expect(store.titleBarGestureAction(for: .pinchOut) == .toggleFullScreen)
        #expect(!store.titleBarGestureIsEnabled(for: .pinchOut))

        let persistedDockBindings = try JSONDecoder().decode(
            [DockGestureBinding].self,
            from: #require(defaults.data(forKey: "settings.dockGestureBindings"))
        )
        let persistedTitleBarBindings = try JSONDecoder().decode(
            [TitleBarGestureBinding].self,
            from: #require(defaults.data(forKey: "settings.titleBarGestureBindings"))
        )

        #expect(persistedDockBindings.first?.action == .restoreWindow)
        #expect(persistedDockBindings.first?.isEnabled == false)
        #expect(persistedTitleBarBindings.first?.action == .toggleFullScreen)
        #expect(persistedTitleBarBindings.first?.isEnabled == false)
        #expect(!defaults.bool(forKey: "settings.smartBrowserTabCloseEnabled"))
        #expect(!defaults.bool(forKey: "settings.pinchCloseConfirmationEnabled"))
    }

    @Test
    func coalescesSynchronousSettingsChangeNotifications() async {
        let store = makeSettingsStore()

        let recorder = await recordSettingsChanges(from: store) {
            store.hotKeysEnabled = false
            store.dockGesturesEnabled = false
            store.titleBarGesturesEnabled = false
        }

        #expect(recorder.count == 1)
        #expect(recorder.categories.isSuperset(of: [.hotKeys, .gestureMonitoring]))
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "Swooshy.SettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeSettingsStore() -> SettingsStore {
        SettingsStore(userDefaults: makeUserDefaults())
    }

    private func recordSettingsChanges(
        from store: SettingsStore,
        perform updateSettings: () -> Void
    ) async -> NotificationRecorder {
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

        updateSettings()
        await yieldForPendingMainActorWork()
        return recorder
    }
}
