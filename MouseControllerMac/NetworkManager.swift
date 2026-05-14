import Foundation
import Network
import CoreGraphics

class NetworkManager {

    private var listener: NWListener?

    init() {
        startServer()
    }

    func startServer() {
        do {
            listener = try NWListener(using: .tcp, on: 5555)

            listener?.newConnectionHandler = { connection in
                self.handleConnection(connection)
            }

            listener?.start(queue: .main)

            print("Server started on port 5555")

        } catch {
            print("Failed to start server")
        }
    }

    func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .main)
        receive(on: connection)
    }

    func receive(on connection: NWConnection) {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 1024
        ) { data, _, isComplete, error in

            if let data = data,
               let message = String(data: data, encoding: .utf8) {

                print("Received: \(message)")
                self.handleMessage(message)
            }

            if error == nil && !isComplete {
                self.receive(on: connection)
            }
        }
    }

    func handleMessage(_ message: String) {

        if message.starts(with: "MOVE") {
            let parts = message.components(separatedBy: ":")

            if parts.count == 3,
               let dx = Double(parts[1]),
               let dy = Double(parts[2]) {

                moveMouseBy(dx: dx, dy: dy)
            }
        }

        if message == "CLICK" {
            leftClick()
        }

        if message.starts(with: "KEY:") {
            let text = String(message.dropFirst(4))
            typeText(text)
        }

        if message == "BACKSPACE" {
            pressBackspace()
        }
        
        if message.starts(with: "SCROLL:") {
            let parts = message.components(separatedBy: ":")

            if parts.count == 2,
               let dy = Double(parts[1]) {
                scrollBy(dy: dy)
            }
        }
    }
    
    func scrollBy(dy: Double) {
        let scrollEvent = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 1,
            wheel1: Int32(-dy),
            wheel2: 0,
            wheel3: 0
        )

        scrollEvent?.post(tap: .cghidEventTap)
    }

    func moveMouseBy(dx: Double, dy: Double) {
        let currentLocation = CGEvent(source: nil)?.location ?? .zero

        let newLocation = CGPoint(
            x: currentLocation.x + dx,
            y: currentLocation.y + dy
        )

        let moveEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: newLocation,
            mouseButton: .left
        )

        moveEvent?.post(tap: .cghidEventTap)
    }

    func leftClick() {
        let location = CGEvent(source: nil)?.location ?? .zero

        let mouseDown = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: location,
            mouseButton: .left
        )

        let mouseUp = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseUp,
            mouseCursorPosition: location,
            mouseButton: .left
        )

        mouseDown?.post(tap: .cghidEventTap)
        mouseUp?.post(tap: .cghidEventTap)
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

    func pressBackspace() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyCode: CGKeyCode = 51

        let keyDown = CGEvent(
            keyboardEventSource: source,
            virtualKey: keyCode,
            keyDown: true
        )

        let keyUp = CGEvent(
            keyboardEventSource: source,
            virtualKey: keyCode,
            keyDown: false
        )

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
