//
//  IPAddress.swift
//  MouseController
//
//  Created by Ivo Peterka on 14. 5. 2026.
//

import Foundation

func getLocalIPAddress() -> String {
    var address = "IP not found"

    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0 else { return address }
    guard let firstAddr = ifaddr else { return address }

    for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
        let interface = ptr.pointee
        let addrFamily = interface.ifa_addr.pointee.sa_family

        if addrFamily == UInt8(AF_INET) {
            let name = String(cString: interface.ifa_name)

            if name == "en0" || name == "en1" {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))

                getnameinfo(
                    interface.ifa_addr,
                    socklen_t(interface.ifa_addr.pointee.sa_len),
                    &hostname,
                    socklen_t(hostname.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                )

                let ip = String(cString: hostname)

                if !ip.starts(with: "127.") {
                    address = ip
                    break
                }
            }
        }
    }

    freeifaddrs(ifaddr)
    return address
}
