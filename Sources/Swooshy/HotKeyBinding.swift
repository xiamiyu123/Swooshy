import AppKit
import Carbon.HIToolbox
import Foundation

enum ShortcutModifierSet: String, CaseIterable, Codable, Identifiable, Sendable {
    case commandShiftControl
    case commandShiftOption
    case commandShiftOptionControl
    case commandOnly
    case commandShift
    case commandOption
    case commandControl
    case commandOptionControl

    var id: String { rawValue }

    var eventFlags: NSEvent.ModifierFlags {
        switch self {
        case .commandShiftControl:
            [.command, .shift, .control]
        case .commandShiftOption:
            [.command, .shift, .option]
        case .commandShiftOptionControl:
            [.command, .shift, .option, .control]
        case .commandOnly:
            [.command]
        case .commandShift:
            [.command, .shift]
        case .commandOption:
            [.command, .option]
        case .commandControl:
            [.command, .control]
        case .commandOptionControl:
            [.command, .option, .control]
        }
    }

    var carbonModifiers: UInt32 {
        let flags = eventFlags
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        return result
    }

    var displayString: String {
        let flags = eventFlags
        var result = ""
        if flags.contains(.control) { result += "⌃" }
        if flags.contains(.option) { result += "⌥" }
        if flags.contains(.shift) { result += "⇧" }
        if flags.contains(.command) { result += "⌘" }
        return result
    }

    init?(eventFlags: NSEvent.ModifierFlags) {
        let normalizedFlags = eventFlags.intersection([
            .command,
            .shift,
            .option,
            .control,
        ])

        guard
            normalizedFlags.contains(.command),
            let modifierSet = Self.allCases.first(where: { $0.eventFlags == normalizedFlags })
        else {
            return nil
        }

        self = modifierSet
    }
}

enum ShortcutKey: String, CaseIterable, Codable, Identifiable, Sendable {
    private enum KeyLabel {
        case character(String)
        case function(menu: String, display: String)
    }

    private struct KeyMetadata {
        let keyCode: UInt32
        let label: KeyLabel
    }

    case zero
    case one
    case two
    case three
    case four
    case five
    case six
    case seven
    case eight
    case nine
    case leftArrow
    case rightArrow
    case upArrow
    case downArrow
    case grave
    case a
    case b
    case c
    case d
    case e
    case f
    case g
    case h
    case i
    case j
    case k
    case l
    case m
    case n
    case o
    case p
    case q
    case r
    case s
    case t
    case u
    case v
    case w
    case x
    case y
    case z

    var id: String { rawValue }

    var keyCode: UInt32 {
        metadata.keyCode
    }

    var menuKeyEquivalent: String {
        switch label {
        case .character(let character):
            return character
        case .function(let menu, _):
            return menu
        }
    }

    var displayKey: String {
        switch label {
        case .character(let character):
            return character.uppercased()
        case .function(_, let display):
            return display
        }
    }

    private var label: KeyLabel {
        metadata.label
    }

    private var metadata: KeyMetadata {
        switch self {
        case .zero:
            KeyMetadata(keyCode: UInt32(kVK_ANSI_0), label: .character("0"))
        case .one:
            KeyMetadata(keyCode: UInt32(kVK_ANSI_1), label: .character("1"))
        case .two:
            KeyMetadata(keyCode: UInt32(kVK_ANSI_2), label: .character("2"))
        case .three:
            KeyMetadata(keyCode: UInt32(kVK_ANSI_3), label: .character("3"))
        case .four:
            KeyMetadata(keyCode: UInt32(kVK_ANSI_4), label: .character("4"))
        case .five:
            KeyMetadata(keyCode: UInt32(kVK_ANSI_5), label: .character("5"))
        case .six:
            KeyMetadata(keyCode: UInt32(kVK_ANSI_6), label: .character("6"))
        case .seven:
            KeyMetadata(keyCode: UInt32(kVK_ANSI_7), label: .character("7"))
        case .eight:
            KeyMetadata(keyCode: UInt32(kVK_ANSI_8), label: .character("8"))
        case .nine:
            KeyMetadata(keyCode: UInt32(kVK_ANSI_9), label: .character("9"))
        case .grave:
            KeyMetadata(keyCode: UInt32(kVK_ANSI_Grave), label: .character("`"))
        case .a:
            KeyMetadata(keyCode: UInt32(kVK_ANSI_A), label: .character(rawValue))
        case .b:
            KeyMetadata(keyCode: UInt32(kVK_ANSI_B), label: .character(rawValue))
        case .c:
            KeyMetadata(keyCode: UInt32(kVK_ANSI_C), label: .character(rawValue))
        case .d:
            KeyMetadata(keyCode: UInt32(kVK_ANSI_D), label: .character(rawValue))
        case .e:
            KeyMetadata(keyCode: UInt32(kVK_ANSI_E), label: .character(rawValue))
        case .f:
            KeyMetadata(keyCode: UInt32(kVK_ANSI_F), label: .character(rawValue))
        case .g:
            KeyMetadata(keyCode: UInt32(kVK_ANSI_G), label: .character(rawValue))
        case .h:
            KeyMetadata(keyCode: UInt32(kVK_ANSI_H), label: .character(rawValue))
        case .i:
            KeyMetadata(keyCode: UInt32(kVK_ANSI_I), label: .character(rawValue))
        case .j:
            KeyMetadata(keyCode: UInt32(kVK_ANSI_J), label: .character(rawValue))
        case .k:
            KeyMetadata(keyCode: UInt32(kVK_ANSI_K), label: .character(rawValue))
        case .l:
            KeyMetadata(keyCode: UInt32(kVK_ANSI_L), label: .character(rawValue))
        case .m:
            KeyMetadata(keyCode: UInt32(kVK_ANSI_M), label: .character(rawValue))
        case .n:
            KeyMetadata(keyCode: UInt32(kVK_ANSI_N), label: .character(rawValue))
        case .o:
            KeyMetadata(keyCode: UInt32(kVK_ANSI_O), label: .character(rawValue))
        case .p:
            KeyMetadata(keyCode: UInt32(kVK_ANSI_P), label: .character(rawValue))
        case .q:
            KeyMetadata(keyCode: UInt32(kVK_ANSI_Q), label: .character(rawValue))
        case .r:
            KeyMetadata(keyCode: UInt32(kVK_ANSI_R), label: .character(rawValue))
        case .s:
            KeyMetadata(keyCode: UInt32(kVK_ANSI_S), label: .character(rawValue))
        case .t:
            KeyMetadata(keyCode: UInt32(kVK_ANSI_T), label: .character(rawValue))
        case .u:
            KeyMetadata(keyCode: UInt32(kVK_ANSI_U), label: .character(rawValue))
        case .v:
            KeyMetadata(keyCode: UInt32(kVK_ANSI_V), label: .character(rawValue))
        case .w:
            KeyMetadata(keyCode: UInt32(kVK_ANSI_W), label: .character(rawValue))
        case .x:
            KeyMetadata(keyCode: UInt32(kVK_ANSI_X), label: .character(rawValue))
        case .y:
            KeyMetadata(keyCode: UInt32(kVK_ANSI_Y), label: .character(rawValue))
        case .z:
            KeyMetadata(keyCode: UInt32(kVK_ANSI_Z), label: .character(rawValue))
        case .leftArrow:
            KeyMetadata(
                keyCode: UInt32(kVK_LeftArrow),
                label: .function(
                    menu: Self.menuFunctionKeyEquivalent(for: NSLeftArrowFunctionKey, fallback: "←"),
                    display: "←"
                )
            )
        case .rightArrow:
            KeyMetadata(
                keyCode: UInt32(kVK_RightArrow),
                label: .function(
                    menu: Self.menuFunctionKeyEquivalent(for: NSRightArrowFunctionKey, fallback: "→"),
                    display: "→"
                )
            )
        case .upArrow:
            KeyMetadata(
                keyCode: UInt32(kVK_UpArrow),
                label: .function(
                    menu: Self.menuFunctionKeyEquivalent(for: NSUpArrowFunctionKey, fallback: "↑"),
                    display: "↑"
                )
            )
        case .downArrow:
            KeyMetadata(
                keyCode: UInt32(kVK_DownArrow),
                label: .function(
                    menu: Self.menuFunctionKeyEquivalent(for: NSDownArrowFunctionKey, fallback: "↓"),
                    display: "↓"
                )
            )
        }
    }

    init?(keyCode: UInt16) {
        guard let key = Self.keysByCode[UInt32(keyCode)] else {
            return nil
        }
        self = key
    }

    private static let keysByCode: [UInt32: ShortcutKey] = {
        Dictionary(uniqueKeysWithValues: allCases.map { ($0.keyCode, $0) })
    }()

    private static func menuFunctionKeyEquivalent(for functionKey: Int, fallback: String) -> String {
        guard let scalar = UnicodeScalar(UInt32(functionKey)) else {
            return fallback
        }

        return String(Character(scalar))
    }
}

struct HotKeyBinding: Codable, Equatable, Sendable {
    let action: WindowAction
    let key: ShortcutKey
    let modifiers: ShortcutModifierSet

    var keyCode: UInt32 { key.keyCode }
    var carbonModifiers: UInt32 { modifiers.carbonModifiers }
    var menuKeyEquivalent: String { key.menuKeyEquivalent }
    var menuModifierFlags: NSEvent.ModifierFlags { modifiers.eventFlags }
    var menuDisplayKey: String { key.displayKey }
}

enum HotKeyBindings {
    static let defaults: [HotKeyBinding] = [
        HotKeyBinding(action: .leftHalf, key: .leftArrow, modifiers: .commandOptionControl),
        HotKeyBinding(action: .rightHalf, key: .rightArrow, modifiers: .commandOptionControl),
        HotKeyBinding(action: .maximize, key: .upArrow, modifiers: .commandOptionControl),
        HotKeyBinding(action: .center, key: .c, modifiers: .commandOptionControl),
        HotKeyBinding(action: .topLeftQuarter, key: .u, modifiers: .commandOptionControl),
        HotKeyBinding(action: .topRightQuarter, key: .i, modifiers: .commandOptionControl),
        HotKeyBinding(action: .bottomLeftQuarter, key: .j, modifiers: .commandOptionControl),
        HotKeyBinding(action: .bottomRightQuarter, key: .k, modifiers: .commandOptionControl),
        HotKeyBinding(action: .moveToNextDisplay, key: .n, modifiers: .commandOptionControl),
        HotKeyBinding(action: .moveToPreviousDisplay, key: .n, modifiers: .commandShiftOptionControl),
        HotKeyBinding(action: .minimize, key: .m, modifiers: .commandOptionControl),
        HotKeyBinding(action: .closeWindow, key: .w, modifiers: .commandOptionControl),
        HotKeyBinding(action: .closeTab, key: .w, modifiers: .commandShiftOptionControl),
        HotKeyBinding(action: .quitApplication, key: .q, modifiers: .commandOptionControl),
        HotKeyBinding(action: .cycleSameAppWindowsForward, key: .grave, modifiers: .commandOptionControl),
        HotKeyBinding(action: .cycleSameAppWindowsBackward, key: .grave, modifiers: .commandShiftOptionControl),
        HotKeyBinding(action: .toggleFullScreen, key: .f, modifiers: .commandOptionControl),
    ]

    static func binding(for action: WindowAction, in bindings: [HotKeyBinding] = defaults) -> HotKeyBinding? {
        bindings.first(where: { $0.action == action })
    }
}
