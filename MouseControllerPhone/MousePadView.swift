import SwiftUI
import Network

struct MousePadView: View {

    let host: String
    let onDisconect: () -> Void
    let port: UInt16 = 5555

    @State private var connection: NWConnection?
    @State private var keyboardText = ""
    @State private var connectionStatus = "Connecting..."
    @State private var isReady = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.black,
                    Color(red: 0.08, green: 0.09, blue: 0.12)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                headerView

                touchPadCard

                keyboardField

                if !isReady {
                    reconnectButton
                }

                Text("Tap to click • Drag to move • Two fingers to scroll")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.45))
                    .padding(.bottom, 12)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
        }
        .onAppear {
            connect()
        }
        .onDisappear {
            disconnect()
        }
    }

    var headerView: some View {
        HStack(spacing: 12) {
            Button {
                disconnect()
                onDisconect()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(width: 42, height: 42)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Circle())
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Remote Mouse")
                    .font(.headline)
                    .foregroundColor(.white)

                Text(host)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.45))
            }

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(isReady ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)

                Text(isReady ? "Connected" : connectionStatus)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.08))
            .cornerRadius(20)
        }
        .padding(.top, 8)
    }

    var touchPadCard: some View {
        TouchPadView(
            onMove: { dx, dy in
                sendMove(dx: dx * 3, dy: dy * 3)
            },
            onClick: {
                sendClick()
            },
            onScroll: { dy in
                sendScroll(dy: dy)
            }
        )
        .frame(maxWidth: .infinity)
        .frame(height: 470)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(Color.white.opacity(0.12))
        )
        .overlay(
            VStack(spacing: 10) {
                Image(systemName: "cursorarrow")
                    .font(.system(size: 34, weight: .semibold))

                Text("Touchpad")
                    .font(.headline)

                Text("Tap, drag or scroll")
                    .font(.caption)
                    .opacity(0.55)
            }
            .foregroundColor(.white.opacity(0.28))
        )
        .opacity(isReady ? 1 : 0.4)
        .disabled(!isReady)
    }

    var keyboardField: some View {
        TextField("Type here", text: $keyboardText)
            .keyboardType(.default)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .padding()
            .background(Color.white.opacity(0.1))
            .foregroundColor(.white)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.12))
            )
            .disabled(!isReady)
            .onChange(of: keyboardText) { oldValue, newValue in
                if newValue.count > oldValue.count {
                    let addedText = String(newValue.dropFirst(oldValue.count))
                    sendKey(addedText)
                }

                if newValue.count < oldValue.count {
                    send("BACKSPACE")
                }
            }
    }

    var reconnectButton: some View {
        Button {
            connect()
        } label: {
            Text("Reconnect")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.white)
                .foregroundColor(.black)
                .cornerRadius(16)
        }
    }

    func connect() {
        disconnect()

        connectionStatus = "Connecting..."
        isReady = false

        let newConnection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(integerLiteral: port),
            using: .tcp
        )

        connection = newConnection

        newConnection.stateUpdateHandler = { state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    connectionStatus = "Connected"
                    isReady = true

                case .failed:
                    connectionStatus = "Failed"
                    isReady = false

                case .waiting:
                    connectionStatus = "Waiting"
                    isReady = false

                case .cancelled:
                    connectionStatus = "Disconnected"
                    isReady = false

                default:
                    connectionStatus = "Connecting..."
                    isReady = false
                }
            }
        }

        newConnection.start(queue: .main)

        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            if !isReady {
                connectionStatus = "Failed"
                newConnection.cancel()
            }
        }
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        isReady = false
    }

    func sendMove(dx: CGFloat, dy: CGFloat) {
        send("MOVE:\(dx):\(dy)")
    }

    func sendClick() {
        send("CLICK")
    }

    func sendScroll(dy: CGFloat) {
        send("SCROLL:\(dy)")
    }

    func sendKey(_ text: String) {
        guard !text.isEmpty else { return }
        send("KEY:\(text)")
    }

    func send(_ string: String) {
        guard isReady else { return }
        guard let data = string.data(using: .utf8) else { return }

        connection?.send(
            content: data,
            completion: .contentProcessed { error in
                if let error = error {
                    print("Send error: \(error)")

                    DispatchQueue.main.async {
                        connectionStatus = "Failed"
                        isReady = false
                    }
                }
            }
        )
    }
}
