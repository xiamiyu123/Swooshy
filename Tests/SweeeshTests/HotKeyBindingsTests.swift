import Carbon.HIToolbox
import Testing
@testable import Sweeesh

struct HotKeyBindingsTests {
    @Test
    func defaultBindingsCoverEveryWindowAction() {
        #expect(Set(HotKeyBindings.defaults.map(\.action)) == Set(WindowAction.allCases))
    }

    @Test
    func defaultBindingsUseUniqueAccelerators() {
        let accelerators = HotKeyBindings.defaults.map { "\($0.keyCode)-\($0.carbonModifiers)" }
        #expect(Set(accelerators).count == HotKeyBindings.defaults.count)
    }

    @Test
    func shortcutKeyCanResolveFromRecordedKeyCode() {
        #expect(ShortcutKey(keyCode: UInt16(kVK_ANSI_Q)) == .q)
        #expect(ShortcutKey(keyCode: UInt16(kVK_LeftArrow)) == .leftArrow)
    }

    @Test
    func shortcutModifiersResolveFromRecordedFlags() {
        #expect(
            ShortcutModifierSet(
                eventFlags: [.command, .option, .control]
            ) == .commandOptionControl
        )
        #expect(
            ShortcutModifierSet(
                eventFlags: [.command, .shift]
            ) == .commandShift
        )
    }
}
