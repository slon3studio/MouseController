//
//  MouseControllerApp.swift
//  MouseController
//
//  Created by Ivo Peterka on 6. 5. 2026.
//

import SwiftUI

@main
struct MouseControllerApp: App {

    @StateObject private var networkManager = NetworkManager()

    var body: some Scene {

        WindowGroup {
            ContentView()
                .environmentObject(networkManager)
        }

        MenuBarExtra("MouseController", systemImage: "cursorarrow.rays") {

            Text("Server Running")
            Text("Pairing code: \(Pairing.formatted(networkManager.pairingCode))")

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
