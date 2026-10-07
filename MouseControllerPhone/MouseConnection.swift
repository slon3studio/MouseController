import Combine
import Foundation
import Network
import Security

final class MouseConnection: ObservableObject {

    enum Status {
        case needsCode
        case wrongCode
        case connecting
        case connected
        case reconnecting
        case disconnected
    }

    @Published private(set) var status: Status = .disconnected

    /// The Mac's output volume (0...1), or nil when it hasn't reported one
    /// or its output device has no software volume (e.g. HDMI).
    @Published private(set) var volumeLevel: Double?
    @Published private(set) var isMuted = false

    var isReady: Bool { status == .connected }

    private let target: ConnectionTarget
    private var code: String?
    private var connection: NWConnection?
    private var resolver: NWConnection?
    private var retryTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var retryAttempt = 0
    private var isStopped = true

    init(target: ConnectionTarget) {
        self.target = target
        self.code = PairingStore.code(for: target.id)
    }

    func start() {
        isStopped = false
        retryAttempt = 0

        guard code != nil else {
            status = .needsCode
            return
        }

        openConnection()
    }

    func pair(with code: String) {
        let code = Pairing.normalized(code)
        self.code = code
        PairingStore.save(code, for: target.id)
        start()
    }

    func stop() {
        isStopped = true
        retryTask?.cancel()
        tearDown()
        status = .disconnected
    }

    /// Skips the backoff wait, e.g. when the app returns to the foreground.
    func reconnectNow() {
        guard !isStopped, code != nil, status != .connected else { return }
        retryAttempt = 0
        openConnection()
    }

    func send(_ message: String) {
        guard isReady, let connection else { return }

        // Newline-delimited framing: TCP is a stream, so without a
        // delimiter rapid messages coalesce and the Mac drops them.
        let data = Data((message + "\n").utf8)

        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            guard error != nil else { return }

            MainActor.assumeIsolated {
                guard let self, self.connection === connection else { return }
                self.connectionLost()
            }
        })
    }

    func setVolume(_ level: Double) {
        volumeLevel = level
        if level > 0 {
            isMuted = false
        }
        send("VOLUME:SET:\(String(format: "%.3f", level))")
    }

    private func openConnection() {
        retryTask?.cancel()
        tearDown()

        guard let code else {
            status = .needsCode
            return
        }

        status = retryAttempt == 0 ? .connecting : .reconnecting

        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, let self, self.status != .connected else { return }
            self.connectionLost()
        }

        guard case .service = target.endpoint else {
            connect(to: target.endpoint, code: code)
            return
        }

        // Connecting TLS straight to a Bonjour name hides handshake errors:
        // the connection keeps retrying internally, so a wrong code would
        // look like a timeout (and every retry counts as a guess on the
        // Mac). Resolve to an address with plain TCP first, then connect
        // TLS to that address, which reports a wrong code immediately.
        let newResolver = NWConnection(to: target.endpoint, using: .tcp)
        resolver = newResolver

        newResolver.stateUpdateHandler = { [weak self] state in
            guard case .ready = state else { return }

            MainActor.assumeIsolated {
                guard let self, self.resolver === newResolver else { return }

                let address = newResolver.currentPath?.remoteEndpoint
                newResolver.cancel()
                self.resolver = nil

                if let address {
                    self.connect(to: address, code: code)
                }
            }
        }

        newResolver.start(queue: .main)
    }

    private func connect(to endpoint: NWEndpoint, code: String) {
        let newConnection = NWConnection(to: endpoint, using: Pairing.parameters(code: code))
        connection = newConnection

        newConnection.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                guard let self, self.connection === newConnection else { return }
                self.handle(state)
            }
        }

        newConnection.start(queue: .main)
        receiveLoop(on: newConnection)
    }

    private func handle(_ state: NWConnection.State) {
        switch state {
        case .ready:
            timeoutTask?.cancel()
            retryAttempt = 0
            status = .connected

        // .waiting covers "connection refused", e.g. the Mac app isn't running.
        case .failed(let error), .waiting(let error):
            if Self.isWrongCode(error) {
                wrongCode()
            } else {
                connectionLost()
            }

        default:
            break
        }
    }

    // A wrong code fails the TLS handshake with a MAC/decrypt error. Other
    // failures (Mac app quit, Mac locked out after too many attempts, which
    // resets the connection) are worth retrying with the same code.
    private static func isWrongCode(_ error: NWError) -> Bool {
        guard case .tls(let status) = error else { return false }
        return ![errSSLClosedAbort, errSSLClosedGraceful, errSSLClosedNoNotify].contains(status)
    }

    private func wrongCode() {
        tearDown()
        retryTask?.cancel()
        PairingStore.remove(for: target.id)
        code = nil
        status = .wrongCode
    }

    private func receiveLoop(on connection: NWConnection, buffer: Data = Data()) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self, self.connection === connection else { return }

                var buffer = buffer
                if let data {
                    buffer.append(data)
                }

                while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                    let lineData = Data(buffer[buffer.startIndex..<newlineIndex])
                    buffer.removeSubrange(buffer.startIndex...newlineIndex)

                    if let line = String(data: lineData, encoding: .utf8) {
                        self.handleIncoming(line)
                    }
                }

                // A clean close (Mac app quit) is only visible through a
                // pending receive; a send-only socket would never notice.
                if let error, Self.isWrongCode(error) {
                    self.wrongCode()
                } else if isComplete || error != nil {
                    self.connectionLost()
                } else {
                    self.receiveLoop(on: connection, buffer: buffer)
                }
            }
        }
    }

    private func handleIncoming(_ line: String) {
        let parts = line.components(separatedBy: ":")

        // VOLUME_LEVEL:<0...1>:<muted 0/1> or VOLUME_LEVEL:NONE
        if parts.first == "VOLUME_LEVEL", parts.count >= 2 {
            volumeLevel = Double(parts[1])
            isMuted = parts.count >= 3 && parts[2] == "1"
        }
    }

    private func connectionLost() {
        guard !isStopped else { return }

        tearDown()
        status = .reconnecting

        // 0.5s, 1s, 2s, 4s, then every 5s.
        let delay = min(0.5 * pow(2, Double(retryAttempt)), 5)
        retryAttempt += 1

        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.openConnection()
        }
    }

    private func tearDown() {
        timeoutTask?.cancel()
        resolver?.stateUpdateHandler = nil
        resolver?.cancel()
        resolver = nil
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
    }
}
