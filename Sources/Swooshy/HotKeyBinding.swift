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
            return [.command, .shift, .control]
        case .commandShiftOption:
            return [.command, .shift, .option]
        case .commandShiftOptionControl:
            return [.command, .shift, .option, .control]
        case .commandOnly:
            return [.command]
        case .commandShift:
            return [.command, .shift]
        case .commandOption:
            return [.command, .option]
        case .commandControl:
            return [.command, .control]
        case .commandOptionControl:
            return [.command, .option, .control]
        }
    }

    var carbonModifiers: UInt32 {
        var result: UInt32 = 0
        if eventFlags.contains(.command) { result |= UInt32(cmdKey) }
        if eventFlags.contains(.shift) { result |= UInt32(shiftKey) }
        if eventFlags.contains(.option) { result |= UInt32(optionKey) }
        if eventFlags.contains(.control) { result |= UInt32(controlKey) }
        return result
    }

    var displayString: String {
        var result = ""
        if eventFlags.contains(.control) { result += "⌃" }
        if eventFlags.contains(.option) { result += "⌥" }
        if eventFlags.contains(.shift) { result += "⇧" }
        if eventFlags.contains(.command) { result += "⌘" }
        return result
    }

    init?(eventFlags: NSEvent.ModifierFlags) {
        let normalizedFlags = eventFlags.intersection(.deviceIndependentFlagsMask)

        guard normalizedFlags.contains(.command) else {
            return nil
        }

        guard let match = Self.supportedFlagsByEventMask[normalizedFlags.rawValue] else {
            return nil
        }

        self = match
    }

    private static let supportedFlagsByEventMask: [NSEvent.ModifierFlags.RawValue: ShortcutModifierSet] = [
        NSEvent.ModifierFlags.command.rawValue: .commandOnly,
        NSEvent.ModifierFlags([.command, .shift]).rawValue: .commandShift,
        NSEvent.ModifierFlags([.command, .option]).rawValue: .commandOption,
        NSEvent.ModifierFlags([.command, .control]).rawValue: .commandControl,
        NSEvent.ModifierFlags([.command, .option, .control]).rawValue: .commandOptionControl,
        NSEvent.ModifierFlags([.command, .shift, .control]).rawValue: .commandShiftControl,
        NSEvent.ModifierFlags([.command, .shift, .option]).rawValue: .commandShiftOption,
        NSEvent.ModifierFlags([.command, .shift, .option, .control]).rawValue: .commandShiftOptionControl,
    ]
}

enum ShortcutKey: String, CaseIterable, Codable, Identifiable, Sendable {
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
        switch self {
        case .zero:
            return UInt32(kVK_ANSI_0)
        case .one:
            return UInt32(kVK_ANSI_1)
        case .two:
            return UInt32(kVK_ANSI_2)
        case .three:
            return UInt32(kVK_ANSI_3)
        case .four:
            return UInt32(kVK_ANSI_4)
        case .five:
            return UInt32(kVK_ANSI_5)
        case .six:
            return UInt32(kVK_ANSI_6)
        case .seven:
            return UInt32(kVK_ANSI_7)
        case .eight:
            return UInt32(kVK_ANSI_8)
        case .nine:
            return UInt32(kVK_ANSI_9)
        case .leftArrow:
            return UInt32(kVK_LeftArrow)
        case .rightArrow:
            return UInt32(kVK_RightArrow)
        case .upArrow:
            return UInt32(kVK_UpArrow)
        case .downArrow:
            return UInt32(kVK_DownArrow)
        case .grave:
            return UInt32(kVK_ANSI_Grave)
        case .a:
            return UInt32(kVK_ANSI_A)
        case .b:
            return UInt32(kVK_ANSI_B)
        case .c:
            return UInt32(kVK_ANSI_C)
        case .d:
            return UInt32(kVK_ANSI_D)
        case .e:
            return UInt32(kVK_ANSI_E)
        case .f:
            return UInt32(kVK_ANSI_F)
        case .g:
            return UInt32(kVK_ANSI_G)
        case .h:
            return UInt32(kVK_ANSI_H)
        case .i:
            return UInt32(kVK_ANSI_I)
        case .j:
            return UInt32(kVK_ANSI_J)
        case .k:
            return UInt32(kVK_ANSI_K)
        case .l:
            return UInt32(kVK_ANSI_L)
        case .m:
            return UInt32(kVK_ANSI_M)
        case .n:
            return UInt32(kVK_ANSI_N)
        case .o:
            return UInt32(kVK_ANSI_O)
        case .p:
            return UInt32(kVK_ANSI_P)
        case .q:
            return UInt32(kVK_ANSI_Q)
        case .r:
            return UInt32(kVK_ANSI_R)
        case .s:
            return UInt32(kVK_ANSI_S)
        case .t:
            return UInt32(kVK_ANSI_T)
        case .u:
            return UInt32(kVK_ANSI_U)
        case .v:
            return UInt32(kVK_ANSI_V)
        case .w:
            return UInt32(kVK_ANSI_W)
        case .x:
            return UInt32(kVK_ANSI_X)
        case .y:
            return UInt32(kVK_ANSI_Y)
        case .z:
            return UInt32(kVK_ANSI_Z)
        }
    }

    var menuKeyEquivalent: String {
        switch self {
        case .zero:
            return "0"
        case .one:
            return "1"
        case .two:
            return "2"
        case .three:
            return "3"
        case .four:
            return "4"
        case .five:
            return "5"
        case .six:
            return "6"
        case .seven:
            return "7"
        case .eight:
            return "8"
        case .nine:
            return "9"
        case .leftArrow:
            return String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!))
        case .rightArrow:
            return String(Character(UnicodeScalar(NSRightArrowFunctionKey)!))
        case .upArrow:
            return String(Character(UnicodeScalar(NSUpArrowFunctionKey)!))
        case .downArrow:
            return String(Character(UnicodeScalar(NSDownArrowFunctionKey)!))
        case .grave:
            return "`"
        case .a:
            return "a"
        case .b:
            return "b"
        case .c:
            return "c"
        case .d:
            return "d"
        case .e:
            return "e"
        case .f:
            return "f"
        case .g:
            return "g"
        case .h:
            return "h"
        case .i:
            return "i"
        case .j:
            return "j"
        case .k:
            return "k"
        case .l:
            return "l"
        case .m:
            return "m"
        case .n:
            return "n"
        case .o:
            return "o"
        case .p:
            return "p"
        case .q:
            return "q"
        case .r:
            return "r"
        case .s:
            return "s"
        case .t:
            return "t"
        case .u:
            return "u"
        case .v:
            return "v"
        case .w:
            return "w"
        case .x:
            return "x"
        case .y:
            return "y"
        case .z:
            return "z"
        }
    }

    var displayKey: String {
        switch self {
        case .zero:
            return "0"
        case .one:
            return "1"
        case .two:
            return "2"
        case .three:
            return "3"
        case .four:
            return "4"
        case .five:
            return "5"
        case .six:
            return "6"
        case .seven:
            return "7"
        case .eight:
            return "8"
        case .nine:
            return "9"
        case .leftArrow:
            return "←"
        case .rightArrow:
            return "→"
        case .upArrow:
            return "↑"
        case .downArrow:
            return "↓"
        case .grave:
            return "`"
        case .a:
            return "A"
        case .b:
            return "B"
        case .c:
            return "C"
        case .d:
            return "D"
        case .e:
            return "E"
        case .f:
            return "F"
        case .g:
            return "G"
        case .h:
            return "H"
        case .i:
            return "I"
        case .j:
            return "J"
        case .k:
            return "K"
        case .l:
            return "L"
        case .m:
            return "M"
        case .n:
            return "N"
        case .o:
            return "O"
        case .p:
            return "P"
        case .q:
            return "Q"
        case .r:
            return "R"
        case .s:
            return "S"
        case .t:
            return "T"
        case .u:
            return "U"
        case .v:
            return "V"
        case .w:
            return "W"
        case .x:
            return "X"
        case .y:
            return "Y"
        case .z:
            return "Z"
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
        HotKeyBinding(action: .minimize, key: .m, modifiers: .commandOptionControl),
        HotKeyBinding(action: .closeWindow, key: .w, modifiers: .commandOptionControl),
        HotKeyBinding(action: .quitApplication, key: .q, modifiers: .commandOptionControl),
        HotKeyBinding(action: .cycleSameAppWindowsForward, key: .grave, modifiers: .commandOptionControl),
        HotKeyBinding(action: .cycleSameAppWindowsBackward, key: .grave, modifiers: .commandShiftOptionControl),
    ]

    static func binding(for action: WindowAction, in bindings: [HotKeyBinding] = defaults) -> HotKeyBinding? {
        bindings.first(where: { $0.action == action })
    }
}
