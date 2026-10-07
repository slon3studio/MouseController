import SwiftUI
import Network

struct MousePadView: View {

    enum Panel: CaseIterable {
        case pad, keys, sound, media

        var title: String {
            switch self {
            case .pad: return "Pad"
            case .keys: return "Keys"
            case .sound: return "Sound"
            case .media: return "Media"
            }
        }

        var icon: String {
            switch self {
            case .pad: return "cursorarrow"
            case .keys: return "keyboard"
            case .sound: return "speaker.wave.2"
            case .media: return "play"
            }
        }
    }

    private struct Shortcut: Identifiable {
        let label: String
        let message: String
        var id: String { label }
    }

    private let shortcuts = [
        Shortcut(label: "⌘C", message: "COMBO:cmd:c"),
        Shortcut(label: "⌘V", message: "COMBO:cmd:v"),
        Shortcut(label: "⌘Z", message: "COMBO:cmd:z"),
        Shortcut(label: "⌘Tab", message: "COMBO:cmd:tab"),
        Shortcut(label: "Spotlight", message: "COMBO:cmd:space"),
        Shortcut(label: "Mission Control", message: "MISSIONCONTROL"),
        Shortcut(label: "esc", message: "COMBO::esc")
    ]

    let target: ConnectionTarget
    let onDisconect: () -> Void

    @StateObject private var connection: MouseConnection

    @State private var panel: Panel = .pad
    @State private var keyboardText = ""
    @State private var isClearingText = false
    @State private var isDragging = false
    @State private var isShowingSettings = false

    @AppStorage("pointerSensitivity") private var sensitivity = 2.5
    @AppStorage("pointerAcceleration") private var accelerationEnabled = true
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @FocusState private var isKeyboardFocused: Bool

    init(target: ConnectionTarget, onDisconect: @escaping () -> Void) {
        self.target = target
        self.onDisconect = onDisconect
        _connection = StateObject(wrappedValue: MouseConnection(target: target))
    }

    private var isReady: Bool { connection.isReady }

    private var isLandscape: Bool { verticalSizeClass == .compact }

    private var needsPairing: Bool {
        connection.status == .needsCode || connection.status == .wrongCode
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 10) {
                topBar

                touchPad

                if !isLandscape || panel != .pad {
                    panelContent
                }

                tabBar
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .padding(.bottom, 4)
            .sheet(isPresented: $isShowingSettings) {
                settingsSheet
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: .constant(needsPairing)) {
            pairingSheet
        }
        .onAppear {
            connection.start()
        }
        .onDisappear {
            connection.stop()
        }
        .onChange(of: scenePhase) { _, newPhase in
            // iOS drops the socket while the app is suspended.
            if newPhase == .active {
                connection.reconnectNow()
            }
        }
        .onChange(of: isKeyboardFocused) { _, isFocused in
            if !isFocused && panel == .keys {
                panel = .pad
            }
        }
    }

    // MARK: - Top bar

    private var statusText: String {
        switch connection.status {
        case .connected: return "Connected"
        case .connecting: return "Connecting..."
        case .reconnecting: return "Reconnecting..."
        case .needsCode, .wrongCode: return "Not paired"
        case .disconnected: return "Disconnected"
        }
    }

    private var statusColor: Color {
        isReady ? Theme.success : Theme.warning
    }

    var topBar: some View {
        HStack(spacing: 10) {
            Menu {
                Section(statusText) {
                    if !isReady && !needsPairing {
                        Button("Reconnect now", systemImage: "arrow.clockwise") {
                            connection.reconnectNow()
                        }
                    }

                    Button("Disconnect", systemImage: "xmark.circle", role: .destructive) {
                        connection.stop()
                        onDisconect()
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(target.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        if !isReady {
                            Text(statusText)
                                .font(.caption2)
                                .foregroundColor(Theme.secondaryText)
                        }
                    }

                    Spacer(minLength: 4)

                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Theme.mutedText)
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(Theme.surface)
                .clipShape(Capsule())
            }

            Button {
                isShowingSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Theme.surface)
                    .clipShape(Circle())
            }
            .accessibilityLabel("Trackpad settings")
        }
    }

    // MARK: - Touchpad

    // Gain multiplier for a finger moving at `speed` points per second.
    // Without acceleration it's a flat multiplier. With it, the curve is
    // normalized to 1 at a typical 500 pt/s, so the slider means the same
    // thing either way: slow moves drop to 0.4x for precision, fast swipes
    // rise to 2.2x.
    func pointerGain(speed: CGFloat) -> CGFloat {
        guard accelerationEnabled else { return sensitivity }

        let curve = 0.4 + 1.2 * min(speed, 1500) / 1000
        return sensitivity * curve
    }

    var touchPad: some View {
        TouchPadView(
            onMove: { dx, dy, speed in
                let gain = pointerGain(speed: speed)
                connection.send("MOVE:\(dx * gain):\(dy * gain)")
            },
            onClick: {
                Haptics.click()
                connection.send("CLICK")
            },
            onDoubleClick: {
                Haptics.doubleClick()
                connection.send("DOUBLECLICK")
            },
            onRightClick: {
                Haptics.rightClick()
                connection.send("RIGHTCLICK")
            },
            onScroll: { dx, dy in
                connection.send("SCROLL:\(dy):\(dx)")
            },
            onDragStart: {
                Haptics.dragStart()
                isDragging = true
                connection.send("MOUSEDOWN")
            },
            onDragEnd: {
                isDragging = false
                connection.send("MOUSEUP")
            },
            onThreeFingerSwipe: { direction in
                Haptics.gesture()
                switch direction {
                case .up: connection.send("MISSIONCONTROL")
                case .down: connection.send("APPEXPOSE")
                case .left: connection.send("COMBO:ctrl:right")
                case .right: connection.send("COMBO:ctrl:left")
                }
            },
            onPinch: { zoomIn in
                Haptics.selection()
                connection.send(zoomIn ? "COMBO:cmd:+" : "COMBO:cmd:-")
            }
        )
        .background(Theme.pad)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(isDragging ? Theme.accent : Theme.stroke, lineWidth: isDragging ? 2 : 1)
        )
        .overlay(alignment: .bottom) {
            Text(isDragging ? "Dragging · lift to drop" : "Hold to drag · two fingers to scroll")
                .font(.caption)
                .foregroundColor(isDragging ? Theme.accent : Theme.mutedText)
                .padding(.bottom, 12)
                .allowsHitTesting(false)
        }
        .overlay {
            if !isReady {
                VStack(spacing: 10) {
                    if needsPairing {
                        Image(systemName: "lock.fill")
                            .font(.title2)
                            .foregroundColor(Theme.secondaryText)
                    } else {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(statusText)
                        .font(.subheadline)
                        .foregroundColor(Theme.secondaryText)
                }
                .allowsHitTesting(false)
            }
        }
        .opacity(isReady ? 1 : 0.5)
        .disabled(!isReady)
        .frame(maxHeight: .infinity)
    }

    // MARK: - Panels

    @ViewBuilder
    var panelContent: some View {
        switch panel {
        case .pad:
            shortcutBar
        case .keys:
            keysPanel
        case .sound:
            soundPanel
        case .media:
            mediaPanel
        }
    }

    var shortcutBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(shortcuts) { shortcut in
                    chip(shortcut.label) {
                        connection.send(shortcut.message)
                    }
                }
            }
        }
        .disabled(!isReady)
    }

    func chip(_ label: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .frame(height: 38)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    var keysPanel: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                keyButton("esc", message: "COMBO::esc")
                keyButton("tab", message: "COMBO::tab")
                keyButton(icon: "arrow.left", message: "COMBO::left")
                keyButton(icon: "arrow.up", message: "COMBO::up")
                keyButton(icon: "arrow.down", message: "COMBO::down")
                keyButton(icon: "arrow.right", message: "COMBO::right")
            }

            keyboardField
        }
        .disabled(!isReady)
    }

    func keyButton(_ label: String? = nil, icon: String? = nil, message: String) -> some View {
        Button {
            Haptics.selection()
            connection.send(message)
        } label: {
            Group {
                if let icon {
                    Image(systemName: icon)
                } else if let label {
                    Text(label)
                }
            }
            .font(.subheadline.weight(.medium))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    var keyboardField: some View {
        TextField("", text: $keyboardText, prompt: Text("Type on your Mac").foregroundColor(Theme.mutedText))
            .focused($isKeyboardFocused)
            .onAppear {
                isKeyboardFocused = true
            }
            .keyboardType(.default)
            .submitLabel(.go)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background(Theme.surface)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .onSubmit {
                connection.send("ENTER")

                // Clear for the next input; the flag stops onChange from
                // interpreting the clear as deletions to send to the Mac.
                isClearingText = true
                keyboardText = ""
                isKeyboardFocused = false
            }
            .onChange(of: keyboardText) { oldValue, newValue in
                if isClearingText {
                    isClearingText = false
                    return
                }

                if newValue.count > oldValue.count {
                    let addedText = String(newValue.dropFirst(oldValue.count))
                    if !addedText.isEmpty {
                        connection.send("KEY:\(addedText)")
                    }
                }

                if newValue.count < oldValue.count {
                    for _ in 0..<(oldValue.count - newValue.count) {
                        connection.send("BACKSPACE")
                    }
                }
            }
    }

    var volumeBinding: Binding<Double> {
        Binding(
            get: { connection.volumeLevel ?? 0 },
            set: { connection.setVolume($0) }
        )
    }

    var soundPanel: some View {
        VStack(spacing: 10) {
            if connection.volumeLevel != nil {
                HStack(spacing: 12) {
                    Image(systemName: "speaker.fill")
                        .foregroundColor(Theme.secondaryText)

                    Slider(value: volumeBinding, in: 0...1)
                        .tint(Theme.accent)

                    Image(systemName: "speaker.wave.3.fill")
                        .foregroundColor(Theme.secondaryText)
                }
                .padding(.horizontal, 16)
                .frame(height: 50)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            HStack(spacing: 8) {
                panelButton(icon: connection.isMuted ? "speaker.slash.fill" : "speaker.slash", isActive: connection.isMuted) {
                    connection.send("VOLUME:MUTE")
                }
                panelButton(icon: "minus") {
                    connection.send("VOLUME:DOWN")
                }
                panelButton(icon: "plus") {
                    connection.send("VOLUME:UP")
                }
            }
        }
        .disabled(!isReady)
    }

    var mediaPanel: some View {
        HStack(spacing: 8) {
            panelButton(icon: "backward.fill") {
                connection.send("MEDIA:PREVIOUS")
            }
            panelButton(icon: "playpause.fill") {
                connection.send("MEDIA:PLAYPAUSE")
            }
            panelButton(icon: "forward.fill") {
                connection.send("MEDIA:NEXT")
            }
        }
        .disabled(!isReady)
    }

    func panelButton(icon: String, isActive: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(isActive ? Theme.accent : .white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // MARK: - Tab bar

    var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(Panel.allCases, id: \.self) { item in
                Button {
                    select(item)
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.icon)
                            .font(.system(size: 18, weight: .medium))
                        Text(item.title)
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundColor(panel == item ? Theme.accent : Theme.secondaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .contentShape(Rectangle())
                }
            }
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    func select(_ item: Panel) {
        Haptics.selection()

        // Tapping the open panel again closes it back to the plain pad.
        let newPanel = (panel == item && item != .pad) ? .pad : item

        withAnimation(.easeOut(duration: 0.2)) {
            panel = newPanel
        }

        if newPanel != .keys {
            isKeyboardFocused = false
        }
    }

    // MARK: - Sheets

    var pairingSheet: some View {
        PairingSheet(
            macName: target.name,
            showsWrongCode: connection.status == .wrongCode,
            onPair: { code in
                connection.pair(with: code)
            },
            onCancel: {
                connection.stop()
                onDisconect()
            }
        )
    }

    var settingsSheet: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Pointer speed")
                            Spacer()
                            Text(String(format: "%.1f", sensitivity))
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }

                        Slider(value: $sensitivity, in: 1...5, step: 0.1)
                    }

                    Toggle("Acceleration", isOn: $accelerationEnabled)
                } footer: {
                    Text("With acceleration, slow finger movements move the cursor precisely and fast swipes cover more of the screen.")
                }

                Section {
                    Toggle("Haptic feedback", isOn: $hapticsEnabled)
                }

                Section("Gestures") {
                    gestureRow("Tap", "Click")
                    gestureRow("Two-finger tap", "Right-click")
                    gestureRow("Hold, then move", "Drag")
                    gestureRow("Two-finger swipe", "Scroll")
                    gestureRow("Pinch", "Zoom in or out")
                    gestureRow("Three-finger swipe up", "Mission Control")
                    gestureRow("Three-finger swipe left/right", "Switch desktop")
                }
            }
            .navigationTitle("Trackpad")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        isShowingSettings = false
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
    }

    func gestureRow(_ gesture: String, _ result: String) -> some View {
        HStack {
            Text(gesture)
            Spacer()
            Text(result)
                .foregroundColor(.secondary)
        }
        .font(.subheadline)
    }
}

// Its own view so typing only re-renders this sheet, not the whole
// trackpad screen; re-rendering the parent on every keystroke dropped
// characters while typing fast.
private struct PairingSheet: View {

    let macName: String
    let showsWrongCode: Bool
    let onPair: (String) -> Void
    let onCancel: () -> Void

    @State private var code = ""
    @FocusState private var isFocused: Bool

    private var isComplete: Bool {
        Pairing.normalized(code).count == Pairing.codeLength
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield")
                .font(.system(size: 44, weight: .semibold))
                .foregroundColor(Theme.accent)
                .padding(.top, 28)

            VStack(spacing: 8) {
                Text("Enter pairing code")
                    .font(.title2.weight(.semibold))

                Text("You'll find it in the MouseController window on “\(macName)”.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            TextField("XXXX-XXXX", text: $code)
                .focused($isFocused)
                .font(.system(size: 28, weight: .semibold, design: .monospaced))
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit(submit)
                .padding(.vertical, 14)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            if showsWrongCode {
                Text("That code didn't work. Check it on your Mac and try again.")
                    .font(.footnote)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }

            Button(action: submit) {
                Text("Pair")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(!isComplete)
            .opacity(isComplete ? 1 : 0.5)

            Button("Cancel", action: onCancel)
                .foregroundColor(Theme.secondaryText)

            Spacer()
        }
        .padding(.horizontal, 24)
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .interactiveDismissDisabled()
        .onAppear {
            isFocused = true
        }
    }

    private func submit() {
        guard isComplete else { return }
        onPair(code)
        code = ""
    }
}
