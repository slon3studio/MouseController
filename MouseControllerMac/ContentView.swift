//
//  ContentView.swift
//  MouseController
//
//  Created by Ivo Peterka on 6. 5. 2026.
//

import Network
import SwiftUI
import CoreGraphics
import ApplicationServices

struct ContentView: View {

    let networkManager = NetworkManager()
    var body: some View {
        
        VStack {
            Text("Connect your iPhone to the same Wi-Fi or hotspot and enter the IP address below.")
            Text("Mac IP: \(getLocalIPAddress())")
        }
    }
}
