import Carbon.HIToolbox
import CoreGraphics

// Presses shortcuts like ⌘C. The phone sends the character ("c"), not a
// key code, because key codes are physical positions: on a Slovenian or
// German layout the "Z" position types "Y", so a hard-coded ⌘Z would undo
// nothing. The current layout is searched for the key producing the
// character instead.
enum KeyCombo {

    private static let namedKeys: [String: CGKeyCode] = [
        "esc": 53, "tab": 48, "space": 49, "return": 36,
        "delete": 51, "forwarddelete": 117,
        "left": 123, "right": 124, "down": 125, "up": 126,
        "home": 115, "end": 119, "pageup": 116, "pagedown": 121
    ]

    private static let modifierKeys: [String: (keyCode: CGKeyCode, flag: CGEventFlags)] = [
        "cmd": (55, .maskCommand),
        "shift": (56, .maskShift),
        "opt": (58, .maskAlternate),
        "ctrl": (59, .maskControl)
    ]

    /// `modifiers` is a comma-separated list such as "cmd,shift" (may be
    /// empty); `key` is a named key from the table above or one character.
    static func press(modifiers: String, key: String) {
        var modifierNames = modifiers
            .split(separator: ",")
            .map(String.init)
            .filter { modifierKeys[$0] != nil }

        let keyCode: CGKeyCode

        if let named = namedKeys[key.lowercased()] {
            keyCode = named
        } else if let character = key.first, let resolved = resolveKey(for: character) {
            keyCode = resolved.keyCode
            if resolved.needsShift && !modifierNames.contains("shift") {
                modifierNames.append("shift")
            }
        } else {
            return
        }

        let source = CGEventSource(stateID: .hidSystemState)
        var flags: CGEventFlags = []

        // Press the modifier keys themselves too: system shortcuts such as
        // ⌘Tab and Spotlight watch modifier state, not just event flags.
        for name in modifierNames {
            guard let modifier = modifierKeys[name] else { continue }
            flags.insert(modifier.flag)
            post(modifier.keyCode, down: true, flags: flags, source: source)
        }

        var keyFlags = flags
        if (123...126).contains(keyCode) {
            // Real arrow keys carry these flags; ⌃← / ⌃→ (switch Space)
            // aren't recognized without them.
            keyFlags.insert([.maskNumericPad, .maskSecondaryFn])
        }

        post(keyCode, down: true, flags: keyFlags, source: source)
        post(keyCode, down: false, flags: keyFlags, source: source)

        for name in modifierNames.reversed() {
            guard let modifier = modifierKeys[name] else { continue }
            flags.remove(modifier.flag)
            post(modifier.keyCode, down: false, flags: flags, source: source)
        }
    }

    private static func post(_ keyCode: CGKeyCode, down: Bool, flags: CGEventFlags, source: CGEventSource?) {
        let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down)
        event?.flags = flags
        event?.post(tap: .cghidEventTap)
    }

    private static func resolveKey(for character: Character) -> (keyCode: CGKeyCode, needsShift: Bool)? {
        guard let inputSource = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutPointer = TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }

        let layoutData = Unmanaged<CFData>.fromOpaque(layoutPointer).takeUnretainedValue() as Data
        let target = String(character)
        let shiftState = UInt32((shiftKey >> 8) & 0xFF)

        return layoutData.withUnsafeBytes { buffer -> (CGKeyCode, Bool)? in
            guard let layout = buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return nil }

            for (modifierState, needsShift) in [(UInt32(0), false), (shiftState, true)] {
                for keyCode in 0..<128 {
                    var deadKeyState: UInt32 = 0
                    var length = 0
                    var characters = [UniChar](repeating: 0, count: 4)

                    let status = UCKeyTranslate(
                        layout,
                        UInt16(keyCode),
                        UInt16(kUCKeyActionDisplay),
                        modifierState,
                        UInt32(LMGetKbdType()),
                        OptionBits(kUCKeyTranslateNoDeadKeysBit),
                        &deadKeyState,
                        characters.count,
                        &length,
                        &characters
                    )

                    if status == noErr,
                       length > 0,
                       String(utf16CodeUnits: characters, count: length) == target {
                        return (CGKeyCode(keyCode), needsShift)
                    }
                }
            }

            return nil
        }
    }
}
