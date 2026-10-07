//
//  ContentView.swift
//  MouseController
//
//  Created by Ivo Peterka on 6. 5. 2026.
//

import Network
import SwiftUI

struct ContentView: View {

    @EnvironmentObject private var networkManager: NetworkManager

    @State private var ipAddress = getLocalIPAddress()
    @State private var pathMonitor: NWPathMonitor?

    private let macName = Host.current().localizedName ?? "this Mac"

    var body: some View {

        VStack(spacing: 12) {
            Text("In the iPhone app, choose “\(macName)” and enter this pairing code:")
                .multilineTextAlignment(.center)

            Text(Pairing.formatted(networkManager.pairingCode))
                .font(.system(size: 32, weight: .semibold, design: .monospaced))
                .textSelection(.enabled)

            Button("New code") {
                networkManager.resetPairingCode()
            }
            .help("Disconnects paired iPhones; they'll need the new code.")

            Divider()

            Text("Mac IP: \(ipAddress)")
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .onAppear {
            // The hotspot or router can hand out a new address on reconnect.
            // A cancelled monitor can't be restarted, so make a fresh one.
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { _ in
                MainActor.assumeIsolated {
                    ipAddress = getLocalIPAddress()
                }
            }
            monitor.start(queue: .main)
            pathMonitor = monitor
        }
        .onDisappear {
            pathMonitor?.cancel()
            pathMonitor = nil
        }
    }
}
