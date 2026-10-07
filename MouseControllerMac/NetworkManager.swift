import AppKit
import Combine
import CoreGraphics
import Foundation
import Network

final class NetworkManager: ObservableObject {

    @Published private(set) var pairingCode: String

    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]

    private var scrollRemainder: CGPoint = .zero
    private var moveRemainder: CGPoint = .zero
    private var isLeftButtonDown = false

    private var failedAttempts: [Date] = []
    private var lockedUntil: Date = .distantPast

    private static let pairingCodeKey = "pairingCode"

    init() {
        if let saved = UserDefaults.standard.string(forKey: Self.pairingCodeKey),
           Pairing.normalized(saved).count == Pairing.codeLength {
            pairingCode = saved
        } else {
            pairingCode = Pairing.newCode()
            UserDefaults.standard.set(pairingCode, forKey: Self.pairingCodeKey)
        }

        // Without Accessibility permission macOS silently drops every event
        // we post, so ask up front; this shows the system prompt that links
        // to System Settings. It's a no-op once permission is granted.
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)

        startServer()
    }

    /// Paired phones keep working until the code changes; a new code
    /// disconnects them all and they must enter it again.
    func resetPairingCode() {
        pairingCode = Pairing.newCode()
        UserDefaults.standard.set(pairingCode, forKey: Self.pairingCodeKey)
        startServer()
    }

    // MARK: - Server

    func startServer() {
        listener?.cancel()
        listener = nil
        connections.values.forEach { $0.cancel() }
        connections.removeAll()

        if isLeftButtonDown {
            leftMouseUp()
        }

        do {
            let newListener = try NWListener(using: Pairing.parameters(code: pairingCode), on: 5555)

            // Advertised over Bonjour under the Mac's name so the phone can
            // find it without typing an IP. Type must match the iOS app's
            // MacDiscovery.serviceType.
            newListener.service = NWListener.Service(type: "_mousectrl._tcp")

            newListener.newConnectionHandler = { [weak self] connection in
                MainActor.assumeIsolated {
                    self?.handleConnection(connection)
                }
            }

            newListener.stateUpdateHandler = { [weak self, weak newListener] state in
                guard case .failed = state else { return }

                MainActor.assumeIsolated {
                    guard let self, self.listener === newListener else { return }
                    self.restartServerSoon()
                }
            }

            newListener.start(queue: .main)
            listener = newListener
        } catch {
            print("Failed to start server: \(error)")
            restartServerSoon()
        }
    }

    // The port can briefly stay busy after a restart or wake from sleep.
    private func restartServerSoon() {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.startServer()
        }
    }

    private func handleConnection(_ connection: NWConnection) {
        // Rate-limit code guessing: after repeated wrong codes, refuse
        // everyone for a while.
        guard Date() >= lockedUntil else {
            connection.cancel()
            return
        }

        connections[ObjectIdentifier(connection)] = connection

        connection.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                guard let self else { return }

                switch state {
                case .ready:
                    // TLS is up, so the phone has proven it knows the code.
                    self.sendVolumeLevel(to: connection)

                case .failed(let error):
                    self.connectionEnded(connection, error: error)

                case .cancelled:
                    self.connectionEnded(connection)

                default:
                    break
                }
            }
        }

        connection.start(queue: .main)
        receive(on: connection)
    }

    // A wrong code fails the TLS handshake with a decrypt/MAC error. A peer
    // that just opens and closes the port (the phone's hotspot scan) ends
    // the handshake with a "closed" error, which isn't a guess.
    private static func isWrongCode(_ error: NWError) -> Bool {
        guard case .tls(let status) = error else { return false }
        return ![errSSLClosedAbort, errSSLClosedGraceful, errSSLClosedNoNotify].contains(status)
    }

    private func recordFailedAttempt() {
        let now = Date()
        failedAttempts = failedAttempts.filter { now.timeIntervalSince($0) < 60 } + [now]

        if failedAttempts.count >= 5 {
            lockedUntil = now.addingTimeInterval(30)
            failedAttempts.removeAll()
        }
    }

    // Called from both the state handler and the receive loop, since either
    // can see the failure first; only the first call for a connection counts.
    private func connectionEnded(_ connection: NWConnection, error: NWError? = nil) {
        guard connections.removeValue(forKey: ObjectIdentifier(connection)) != nil else { return }

        if let error, Self.isWrongCode(error) {
            recordFailedAttempt()
        }

        // The phone vanished mid-drag; don't leave the button held.
        if isLeftButtonDown {
            leftMouseUp()
        }
    }

    private func receive(on connection: NWConnection, buffer: Data = Data()) {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 65536
        ) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self else { return }

                var buffer = buffer
                if let data = data {
                    buffer.append(data)
                }

                // Messages are newline-delimited; TCP delivers a byte stream,
                // so a chunk can contain several messages or a partial one.
                while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                    let messageData = Data(buffer[buffer.startIndex..<newlineIndex])
                    buffer.removeSubrange(buffer.startIndex...newlineIndex)

                    if let message = String(data: messageData, encoding: .utf8),
                       !message.isEmpty {
                        self.handleMessage(message, from: connection)
                    }
                }

                if error == nil && !isComplete {
                    self.receive(on: connection, buffer: buffer)
                } else {
                    self.connectionEnded(connection, error: error)
                    connection.cancel()
                }
            }
        }
    }

    private func send(_ message: String, to connection: NWConnection) {
        connection.send(content: Data((message + "\n").utf8), completion: .idempotent)
    }

    private func sendVolumeLevel(to connection: NWConnection) {
        if let level = SystemVolume.level {
            let muted = SystemVolume.isMuted ? 1 : 0
            send("VOLUME_LEVEL:\(String(format: "%.3f", level)):\(muted)", to: connection)
        } else {
            send("VOLUME_LEVEL:NONE", to: connection)
        }
    }

    // MARK: - Messages

    func handleMessage(_ message: String, from connection: NWConnection) {
        let parts = message.components(separatedBy: ":")

        switch parts[0] {
        case "MOVE":
            if parts.count == 3, let dx = Double(parts[1]), let dy = Double(parts[2]) {
                moveMouseBy(dx: dx, dy: dy)
            }

        case "SCROLL":
            // SCROLL:dy or SCROLL:dy:dx
            if parts.count >= 2, let dy = Double(parts[1]) {
                let dx = parts.count >= 3 ? Double(parts[2]) ?? 0 : 0
                scrollBy(dx: dx, dy: dy)
            }

        case "CLICK":
            leftClick()

        case "DOUBLECLICK":
            leftClick(clickState: 2)

        case "RIGHTCLICK":
            rightClick()

        case "MOUSEDOWN":
            leftMouseDown()

        case "MOUSEUP":
            leftMouseUp()

        case "KEY":
            typeText(String(message.dropFirst(4)))

        case "BACKSPACE":
            pressKey(51)

        case "ENTER":
            pressKey(36)

        case "COMBO":
            // COMBO:<modifiers>:<key>; the key itself may be ":".
            if parts.count >= 3 {
                KeyCombo.press(modifiers: parts[1], key: parts[2...].joined(separator: ":"))
            }

        case "MISSIONCONTROL":
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Mission Control.app"))

        case "APPEXPOSE":
            KeyCombo.press(modifiers: "ctrl", key: "down")

        case "VOLUME":
            handleVolume(parts, from: connection)

        case "MEDIA":
            switch parts.count >= 2 ? parts[1] : "" {
            case "PLAYPAUSE": pressMediaKey(NX_KEYTYPE_PLAY)
            case "NEXT": pressMediaKey(NX_KEYTYPE_FAST)
            case "PREVIOUS": pressMediaKey(NX_KEYTYPE_REWIND)
            default: break
            }

        default:
            break
        }
    }

    private func handleVolume(_ parts: [String], from connection: NWConnection) {
        guard parts.count >= 2 else { return }

        switch parts[1] {
        case "UP": pressMediaKey(NX_KEYTYPE_SOUND_UP)
        case "DOWN": pressMediaKey(NX_KEYTYPE_SOUND_DOWN)
        case "MUTE": pressMediaKey(NX_KEYTYPE_MUTE)

        case "SET":
            if parts.count >= 3, let level = Double(parts[2]) {
                SystemVolume.setLevel(level)
            }
            // The phone's slider already shows the value it sent.
            return

        default:
            return
        }

        // Let the key event take effect, then tell the phone the new level
        // so its slider follows the buttons.
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            self?.sendVolumeLevel(to: connection)
        }
    }

    // MARK: - Keyboard

    // Posts the same system-defined event a keyboard volume key produces,
    // so the native volume HUD appears and mute state is handled by macOS.
    func pressMediaKey(_ key: Int32) {
        func post(down: Bool) {
            let keyState: Int = down ? 0x0A : 0x0B

            let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(keyState << 8)),
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: (Int(key) << 16) | (keyState << 8),
                data2: -1
            )

            event?.cgEvent?.post(tap: .cghidEventTap)
        }

        post(down: true)
        post(down: false)
    }

    func pressKey(_ keyCode: CGKeyCode) {
        let source = CGEventSource(stateID: .hidSystemState)

        CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)?
            .post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)?
            .post(tap: .cghidEventTap)
    }

    func typeText(_ text: String) {
        for character in text {
            typeCharacter(character)
        }
    }

    func typeCharacter(_ character: Character) {
        let source = CGEventSource(stateID: .hidSystemState)
        let utf16 = Array(String(character).utf16)

        utf16.withUnsafeBufferPointer { buffer in
            let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: 0,
                keyDown: true
            )

            keyDown?.keyboardSetUnicodeString(
                stringLength: buffer.count,
                unicodeString: buffer.baseAddress
            )

            let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: 0,
                keyDown: false
            )

            keyUp?.keyboardSetUnicodeString(
                stringLength: buffer.count,
                unicodeString: buffer.baseAddress
            )

            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Mouse

    func scrollBy(dx: Double, dy: Double) {
        // CGEvent only takes whole pixels; carry the fractional part over
        // so slow scrolls aren't truncated to zero.
        let totalY = -dy + scrollRemainder.y
        let totalX = -dx + scrollRemainder.x
        let pixelsY = totalY.rounded(.towardZero)
        let pixelsX = totalX.rounded(.towardZero)
        scrollRemainder = CGPoint(x: totalX - pixelsX, y: totalY - pixelsY)

        guard pixelsY != 0 || pixelsX != 0 else { return }

        let scrollEvent = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: Int32(pixelsY),
            wheel2: Int32(pixelsX),
            wheel3: 0
        )

        scrollEvent?.post(tap: .cghidEventTap)
    }

    func moveMouseBy(dx: Double, dy: Double) {
        let currentLocation = CGEvent(source: nil)?.location ?? .zero

        // Move in whole pixels and carry the fraction forward, so slow,
        // precise finger movements (well under a pixel per message) still
        // add up instead of being lost.
        let totalX = dx + moveRemainder.x
        let totalY = dy + moveRemainder.y
        let stepX = totalX.rounded(.towardZero)
        let stepY = totalY.rounded(.towardZero)
        moveRemainder = CGPoint(x: totalX - stepX, y: totalY - stepY)

        guard stepX != 0 || stepY != 0 else { return }

        var newLocation = CGPoint(
            x: currentLocation.x + stepX,
            y: currentLocation.y + stepY
        )

        // Clamp to the screen before posting. Posting an off-screen
        // position pins the visible cursor at the edge while the tracked
        // location keeps the overshoot, so the cursor stays "stuck" until
        // opposite movement pays the overshoot back.
        let bounds = displayBounds(containing: currentLocation)
        let clampedX = min(max(newLocation.x, bounds.minX), bounds.maxX - 1)
        let clampedY = min(max(newLocation.y, bounds.minY), bounds.maxY - 1)

        if clampedX != newLocation.x { moveRemainder.x = 0 }
        if clampedY != newLocation.y { moveRemainder.y = 0 }

        newLocation = CGPoint(x: clampedX, y: clampedY)

        // While the button is held, apps only see movement as a drag if
        // it arrives as leftMouseDragged rather than mouseMoved.
        let moveEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: isLeftButtonDown ? .leftMouseDragged : .mouseMoved,
            mouseCursorPosition: newLocation,
            mouseButton: .left
        )

        moveEvent?.post(tap: .cghidEventTap)
    }

    func displayBounds(containing point: CGPoint) -> CGRect {
        var displayID: CGDirectDisplayID = 0
        var count: UInt32 = 0

        let result = CGGetDisplaysWithPoint(point, 1, &displayID, &count)

        if result != .success || count == 0 {
            displayID = CGMainDisplayID()
        }

        return CGDisplayBounds(displayID)
    }

    func leftMouseDown() {
        postMouseEvent(.leftMouseDown, button: .left)
        isLeftButtonDown = true
    }

    func leftMouseUp() {
        postMouseEvent(.leftMouseUp, button: .left)
        isLeftButtonDown = false
    }

    // clickState 1 is a normal click; 2 marks the click as the second of a
    // pair, which is how macOS recognizes a double-click (the phone sends
    // CLICK for the first tap and DOUBLECLICK for the quick second tap).
    func leftClick(clickState: Int64 = 1) {
        postMouseEvent(.leftMouseDown, button: .left, clickState: clickState)
        postMouseEvent(.leftMouseUp, button: .left, clickState: clickState)
    }

    func rightClick() {
        postMouseEvent(.rightMouseDown, button: .right)
        postMouseEvent(.rightMouseUp, button: .right)
    }

    private func postMouseEvent(_ type: CGEventType, button: CGMouseButton, clickState: Int64 = 1) {
        let location = CGEvent(source: nil)?.location ?? .zero

        let event = CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: location,
            mouseButton: button
        )

        event?.setIntegerValueField(.mouseEventClickState, value: clickState)
        event?.post(tap: .cghidEventTap)
    }
}
