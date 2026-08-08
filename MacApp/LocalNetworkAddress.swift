import Darwin
import Foundation

enum LocalNetworkAddress {
    static var ipv4: String? {
        var firstAddress: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&firstAddress) == 0, let firstAddress else { return nil }
        defer { freeifaddrs(firstAddress) }

        var candidates: [(priority: Int, address: String)] = []
        var current: UnsafeMutablePointer<ifaddrs>? = firstAddress

        while let interface = current {
            defer { current = interface.pointee.ifa_next }
            guard let socketAddress = interface.pointee.ifa_addr,
                  socketAddress.pointee.sa_family == UInt8(AF_INET)
            else { continue }

            let flags = Int32(interface.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }

            let name = String(cString: interface.pointee.ifa_name)
            guard !name.hasPrefix("utun"), !name.hasPrefix("awdl"), !name.hasPrefix("llw") else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(
                socketAddress,
                socklen_t(socketAddress.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            ) == 0 else { continue }

            let address = String(cString: host)
            guard !address.hasPrefix("169.254.") else { continue }
            let priority = name == "en0" ? 0 : name.hasPrefix("en") ? 1 : 2
            candidates.append((priority, address))
        }

        return candidates.sorted { $0.priority < $1.priority }.first?.address
    }
}
