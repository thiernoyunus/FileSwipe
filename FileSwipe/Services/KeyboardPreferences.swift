import SwiftUI

/// Optional keyboard bindings for Keep / Delete.
/// Off by default — swipe and on-screen buttons always work.
@MainActor
final class KeyboardPreferences: ObservableObject {
    static let shared = KeyboardPreferences()

    private enum Keys {
        static let enabled = "keyboardShortcutsEnabled"
        static let keep = "keepKeyID"
        static let delete = "deleteKeyID"
    }

    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Keys.enabled) }
    }

    @Published var keepKey: AssignableKey {
        didSet { UserDefaults.standard.set(keepKey.rawValue, forKey: Keys.keep) }
    }

    @Published var deleteKey: AssignableKey {
        didSet { UserDefaults.standard.set(deleteKey.rawValue, forKey: Keys.delete) }
    }

    private init() {
        let defaults = UserDefaults.standard
        // Default: OFF
        isEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? false
        keepKey = AssignableKey(rawValue: defaults.string(forKey: Keys.keep) ?? "") ?? .rightArrow
        deleteKey = AssignableKey(rawValue: defaults.string(forKey: Keys.delete) ?? "") ?? .leftArrow
    }

    /// Returns keep / delete if this press matches a configured binding.
    func action(for press: KeyPress) -> ReviewKeyAction? {
        guard isEnabled else { return nil }
        // Only plain keys — no Command/Option/Shift combos
        if !press.modifiers.subtracting([.numericPad, .function]).isEmpty {
            return nil
        }

        if keepKey.matches(press) { return .keep }
        if deleteKey.matches(press) { return .delete }
        return nil
    }
}

enum ReviewKeyAction {
    case keep
    case delete
}

/// Keys the user can assign to Keep or Delete.
enum AssignableKey: String, CaseIterable, Identifiable, Hashable {
    case leftArrow
    case rightArrow
    case upArrow
    case downArrow
    case `return`
    case space
    case delete
    case forwardDelete
    case tab
    case escape
    case a, b, c, d, e, f, g, h, i, j, k, l, m
    case n, o, p, q, r, s, t, u, v, w, x, y, z
    case digit0, digit1, digit2, digit3, digit4
    case digit5, digit6, digit7, digit8, digit9

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .leftArrow: return "← Left Arrow"
        case .rightArrow: return "→ Right Arrow"
        case .upArrow: return "↑ Up Arrow"
        case .downArrow: return "↓ Down Arrow"
        case .return: return "Return / Enter"
        case .space: return "Space"
        case .delete: return "Delete (Backspace)"
        case .forwardDelete: return "Forward Delete"
        case .tab: return "Tab"
        case .escape: return "Escape"
        case .digit0: return "0"
        case .digit1: return "1"
        case .digit2: return "2"
        case .digit3: return "3"
        case .digit4: return "4"
        case .digit5: return "5"
        case .digit6: return "6"
        case .digit7: return "7"
        case .digit8: return "8"
        case .digit9: return "9"
        default:
            return rawValue.uppercased()
        }
    }

    var shortLabel: String {
        switch self {
        case .leftArrow: return "←"
        case .rightArrow: return "→"
        case .upArrow: return "↑"
        case .downArrow: return "↓"
        case .return: return "⏎"
        case .space: return "Space"
        case .delete: return "⌫"
        case .forwardDelete: return "⌦"
        case .tab: return "Tab"
        case .escape: return "Esc"
        case .digit0: return "0"
        case .digit1: return "1"
        case .digit2: return "2"
        case .digit3: return "3"
        case .digit4: return "4"
        case .digit5: return "5"
        case .digit6: return "6"
        case .digit7: return "7"
        case .digit8: return "8"
        case .digit9: return "9"
        default:
            return rawValue.uppercased()
        }
    }

    func matches(_ press: KeyPress) -> Bool {
        switch self {
        case .leftArrow: return press.key == .leftArrow
        case .rightArrow: return press.key == .rightArrow
        case .upArrow: return press.key == .upArrow
        case .downArrow: return press.key == .downArrow
        case .return: return press.key == .return
        case .space: return press.key == .space
        case .delete: return press.key == .delete
        case .forwardDelete: return press.key == .deleteForward
        case .tab: return press.key == .tab
        case .escape: return press.key == .escape
        case .digit0: return charactersMatch(press, "0")
        case .digit1: return charactersMatch(press, "1")
        case .digit2: return charactersMatch(press, "2")
        case .digit3: return charactersMatch(press, "3")
        case .digit4: return charactersMatch(press, "4")
        case .digit5: return charactersMatch(press, "5")
        case .digit6: return charactersMatch(press, "6")
        case .digit7: return charactersMatch(press, "7")
        case .digit8: return charactersMatch(press, "8")
        case .digit9: return charactersMatch(press, "9")
        default:
            return charactersMatch(press, rawValue)
        }
    }

    private func charactersMatch(_ press: KeyPress, _ expected: String) -> Bool {
        press.characters.lowercased() == expected.lowercased()
    }

    /// Map a live key press into an assignable key (for the “press a key” recorder).
    static func from(press: KeyPress) -> AssignableKey? {
        switch press.key {
        case .leftArrow: return .leftArrow
        case .rightArrow: return .rightArrow
        case .upArrow: return .upArrow
        case .downArrow: return .downArrow
        case .return: return .return
        case .space: return .space
        case .delete: return .delete
        case .deleteForward: return .forwardDelete
        case .tab: return .tab
        case .escape: return .escape
        default: break
        }

        let chars = press.characters.lowercased()
        guard chars.count == 1, let ch = chars.first else { return nil }

        if ch.isLetter {
            return AssignableKey(rawValue: String(ch))
        }
        if ch.isNumber {
            return AssignableKey(rawValue: "digit\(ch)")
        }
        return nil
    }
}
