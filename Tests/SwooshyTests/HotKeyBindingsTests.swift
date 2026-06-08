import AppKit
import Carbon.HIToolbox
import Testing
@testable import Swooshy

struct HotKeyBindingsTests {
    private func expectedMenuFunctionKeyEquivalent(for functionKey: Int, fallback: String) -> String {
        guard let scalar = UnicodeScalar(UInt32(functionKey)) else {
            return fallback
        }

        return String(Character(scalar))
    }

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
    func menuKeyEquivalentsRemainStableForArrowShortcuts() {
        let arrowShortcuts: [(key: ShortcutKey, functionKey: Int, fallback: String)] = [
            (.leftArrow, NSLeftArrowFunctionKey, "←"),
            (.rightArrow, NSRightArrowFunctionKey, "→"),
            (.upArrow, NSUpArrowFunctionKey, "↑"),
            (.downArrow, NSDownArrowFunctionKey, "↓"),
        ]

        for (key, functionKey, fallback) in arrowShortcuts {
            let expectedMenuEquivalent = expectedMenuFunctionKeyEquivalent(
                for: functionKey,
                fallback: fallback
            )
            #expect(key.menuKeyEquivalent == expectedMenuEquivalent)
        }
    }

    @Test
    func shortcutKeyLabelsRemainStable() {
        let expectedLabels: [(key: ShortcutKey, menu: String, display: String)] = [
            (.zero, "0", "0"),
            (.one, "1", "1"),
            (.two, "2", "2"),
            (.three, "3", "3"),
            (.four, "4", "4"),
            (.five, "5", "5"),
            (.six, "6", "6"),
            (.seven, "7", "7"),
            (.eight, "8", "8"),
            (.nine, "9", "9"),
            (
                .leftArrow,
                expectedMenuFunctionKeyEquivalent(for: NSLeftArrowFunctionKey, fallback: "←"),
                "←"
            ),
            (
                .rightArrow,
                expectedMenuFunctionKeyEquivalent(for: NSRightArrowFunctionKey, fallback: "→"),
                "→"
            ),
            (
                .upArrow,
                expectedMenuFunctionKeyEquivalent(for: NSUpArrowFunctionKey, fallback: "↑"),
                "↑"
            ),
            (
                .downArrow,
                expectedMenuFunctionKeyEquivalent(for: NSDownArrowFunctionKey, fallback: "↓"),
                "↓"
            ),
            (.grave, "`", "`"),
            (.a, "a", "A"),
            (.b, "b", "B"),
            (.c, "c", "C"),
            (.d, "d", "D"),
            (.e, "e", "E"),
            (.f, "f", "F"),
            (.g, "g", "G"),
            (.h, "h", "H"),
            (.i, "i", "I"),
            (.j, "j", "J"),
            (.k, "k", "K"),
            (.l, "l", "L"),
            (.m, "m", "M"),
            (.n, "n", "N"),
            (.o, "o", "O"),
            (.p, "p", "P"),
            (.q, "q", "Q"),
            (.r, "r", "R"),
            (.s, "s", "S"),
            (.t, "t", "T"),
            (.u, "u", "U"),
            (.v, "v", "V"),
            (.w, "w", "W"),
            (.x, "x", "X"),
            (.y, "y", "Y"),
            (.z, "z", "Z"),
        ]

        #expect(expectedLabels.map(\.key) == ShortcutKey.allCases)

        for (key, menu, display) in expectedLabels {
            #expect(key.menuKeyEquivalent == menu)
            #expect(key.displayKey == display)
        }
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

    @Test
    func shortcutModifiersRoundTripThroughEventFlags() {
        for modifierSet in ShortcutModifierSet.allCases {
            #expect(ShortcutModifierSet(eventFlags: modifierSet.eventFlags) == modifierSet)
        }
    }

    @Test
    func shortcutModifiersIgnoreNonShortcutFlags() {
        #expect(
            ShortcutModifierSet(
                eventFlags: [.command, .option, .control, .numericPad]
            ) == .commandOptionControl
        )
        #expect(
            ShortcutModifierSet(
                eventFlags: [.command, .shift, .capsLock, .function]
            ) == .commandShift
        )
    }
}
