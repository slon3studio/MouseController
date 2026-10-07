import Combine
import Foundation
import Network

struct ConnectionTarget: Identifiable, Equatable {
    let name: String
    let endpoint: NWEndpoint

    var id: String { name }
}

final class MacDiscovery: ObservableObject {

    // Must match the Mac's NWListener service type and NSBonjourServices
    // in MouseControllerPhone-Info.plist.
    static let serviceType = "_mousectrl._tcp"
    static let port: UInt16 = 5555

    @Published private(set) var macs: [ConnectionTarget] = []

    private var browser: NWBrowser?
    private var bonjourMacs: [ConnectionTarget] = []
    private var hotspotMacs: [ConnectionTarget] = []
    private var probeTask: Task<Void, Never>?
    private var probeHits: Set<Int> = []

    func start() {
        stop()

        let browser = NWBrowser(
            for: .bonjour(type: Self.serviceType, domain: nil),
            using: .tcp
        )

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            MainActor.assumeIsolated {
                guard let self else { return }

                self.bonjourMacs = results
                    .compactMap { result -> ConnectionTarget? in
                        guard case let .service(name, _, _, _) = result.endpoint else { return nil }
                        return ConnectionTarget(name: name, endpoint: result.endpoint)
                    }
                    .sorted { $0.name < $1.name }

                self.publish()
            }
        }

        browser.start(queue: .main)
        self.browser = browser

        probeTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.probeHotspot()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    func stop() {
        browser?.cancel()
        browser = nil
        probeTask?.cancel()
        probeTask = nil
    }

    private func publish() {
        // Bonjour results follow the Mac across IP changes, so prefer them;
        // the hotspot scan would only list the same Mac a second time.
        macs = bonjourMacs.isEmpty ? hotspotMacs : bonjourMacs
    }

    // Fallback for when Bonjour doesn't get through: an iPhone hosting
    // Personal Hotspot is always 172.20.10.1 and hands clients addresses
    // in 172.20.10.2–14, so trying the Mac's port on each is cheap.
    private func probeHotspot() async {
        guard Self.isHostingHotspot() else {
            hotspotMacs = []
            publish()
            return
        }

        probeHits = []
        var probes: [NWConnection] = []

        for lastOctet in 2...14 {
            let probe = NWConnection(
                host: NWEndpoint.Host("172.20.10.\(lastOctet)"),
                port: NWEndpoint.Port(rawValue: Self.port) ?? 5555,
                using: .tcp
            )

            probe.stateUpdateHandler = { [weak self] state in
                MainActor.assumeIsolated {
                    if case .ready = state {
                        self?.probeHits.insert(lastOctet)
                    }
                }
            }

            probe.start(queue: .main)
            probes.append(probe)
        }

        try? await Task.sleep(for: .seconds(1.5))
        probes.forEach { $0.cancel() }

        guard !Task.isCancelled else { return }

        hotspotMacs = probeHits.sorted().map { lastOctet in
            let ip = "172.20.10.\(lastOctet)"
            return ConnectionTarget(
                name: "Mac (\(ip))",
                endpoint: .hostPort(
                    host: NWEndpoint.Host(ip),
                    port: NWEndpoint.Port(rawValue: Self.port) ?? 5555
                )
            )
        }

        publish()
    }

    private static func isHostingHotspot() -> Bool {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return false }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            guard let addr = ptr.pointee.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_INET) else { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(
                addr,
                socklen_t(addr.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            )

            if String(cString: hostname) == "172.20.10.1" {
                return true
            }
        }

        return false
    }
}
