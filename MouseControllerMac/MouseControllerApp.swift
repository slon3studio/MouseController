//
//  MouseControllerApp.swift
//  MouseController
//
//  Created by Ivo Peterka on 6. 5. 2026.
//

import SwiftUI

@main
struct MouseControllerApp: App {

    let networkManager = NetworkManager()

    var body: some Scene {
        
        WindowGroup {
            ContentView()
        }

        MenuBarExtra("Remote Mouse", systemImage: "cursorarrow.rays") {

            Text("Server Running")

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
