import SwiftUI
import Network

struct ContentView: View {

    @AppStorage("lastIPAddress") private var ipAddress = ""
    @State private var target: ConnectionTarget?
    @State private var isShowingManualEntry = false

    @StateObject private var discovery = MacDiscovery()

    var body: some View {
        Group {
            if let target {
                MousePadView(
                    target: target,
                    onDisconect: {
                        self.target = nil
                    }
                )
            } else {
                connectScreen
                    .onAppear {
                        discovery.start()
                    }
                    .onDisappear {
                        discovery.stop()
                    }
            }
        }
        .preferredColorScheme(.dark)
    }

    var connectScreen: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("MouseController")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundColor(.white)

                        Text("Choose a Mac to control")
                            .font(.subheadline)
                            .foregroundColor(Theme.secondaryText)
                    }
                    .padding(.top, 32)

                    RadarView(isSearching: discovery.macs.isEmpty)
                        .frame(maxWidth: .infinity)

                    discoveredMacsSection

                    manualConnectSection
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }

    var discoveredMacsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(discovery.macs.isEmpty ? "Looking for Macs nearby..." : "Found nearby")
                .font(.footnote.weight(.medium))
                .foregroundColor(Theme.secondaryText)

            if discovery.macs.isEmpty {
                Text("Open MouseController on your Mac and make sure both devices are on the same Wi-Fi or hotspot.")
                    .font(.footnote)
                    .foregroundColor(Theme.mutedText)
            }

            ForEach(discovery.macs) { mac in
                Button {
                    target = mac
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "desktopcomputer")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(Theme.accent)
                            .frame(width: 40, height: 40)
                            .background(Theme.accent.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(mac.name)
                                .font(.headline)
                                .foregroundColor(.white)
                                .lineLimit(1)

                            Text("Ready")
                                .font(.caption)
                                .foregroundColor(Theme.success)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(Theme.mutedText)
                    }
                    .padding(12)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Theme.stroke)
                    )
                }
            }
        }
    }

    var manualConnectSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    isShowingManualEntry.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Text("Enter IP address manually")
                    Image(systemName: isShowingManualEntry ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                }
                .font(.subheadline)
                .foregroundColor(Theme.accent)
            }
            .frame(maxWidth: .infinity)

            if isShowingManualEntry {
                HStack(spacing: 10) {
                    TextField("", text: $ipAddress, prompt: Text("172.20.10.2").foregroundColor(Theme.mutedText))
                        .keyboardType(.numbersAndPunctuation)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .submitLabel(.go)
                        .onSubmit(connectManually)
                        .padding(.horizontal, 14)
                        .frame(height: 48)
                        .background(Theme.surface)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    Button(action: connectManually) {
                        Text("Connect")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .frame(height: 48)
                            .background(Theme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .disabled(trimmedIPAddress.isEmpty)
                    .opacity(trimmedIPAddress.isEmpty ? 0.5 : 1)
                }

                Text("The IP is shown in the MouseController window on your Mac.")
                    .font(.footnote)
                    .foregroundColor(Theme.mutedText)
            }
        }
    }

    var trimmedIPAddress: String {
        ipAddress.trimmingCharacters(in: .whitespaces)
    }

    func connectManually() {
        let host = trimmedIPAddress
        guard !host.isEmpty else { return }

        ipAddress = host
        target = ConnectionTarget(
            name: host,
            endpoint: .hostPort(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: MacDiscovery.port) ?? 5555
            )
        )
    }
}

private struct RadarView: View {

    let isSearching: Bool

    var body: some View {
        TimelineView(.animation(paused: !isSearching)) { context in
            let time = context.date.timeIntervalSinceReferenceDate

            ZStack {
                ForEach(0..<3, id: \.self) { ring in
                    let phase = (time / 2.4 + Double(ring) / 3).truncatingRemainder(dividingBy: 1)

                    Circle()
                        .stroke(
                            Theme.accent.opacity(isSearching ? (1 - phase) * 0.6 : 0.2),
                            lineWidth: 1.5
                        )
                        .scaleEffect(isSearching ? 0.35 + phase * 0.65 : 0.55 + Double(ring) * 0.22)
                }

                Circle()
                    .fill(Theme.accent)
                    .frame(width: 56, height: 56)

                Image(systemName: isSearching ? "wifi" : "checkmark")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
            }
            .frame(width: 160, height: 160)
        }
        .accessibilityHidden(true)
    }
}
