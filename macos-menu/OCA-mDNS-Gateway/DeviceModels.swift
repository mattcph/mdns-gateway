import Foundation

struct DevicesEnvelope: Codable, Equatable {
    var instances: [DeviceInstance]
}

struct DeviceInstance: Codable, Equatable, Identifiable, Hashable {
    var id: String
    var service: String
    var domain: String
    var name: String
    var host: String
    var addresses: [String]
    var port: Int
    var txt: [String: String]
    var interface: String
    var state: String
    var stale: Bool
    var ttlSeconds: Int
    var firstSeen: String
    var lastSeen: String

    var addressesDisplay: String {
        addresses.isEmpty ? "—" : addresses.joined(separator: ", ")
    }

    var staleDisplay: String {
        stale ? "Yes" : "No"
    }

    var txtDisplayLines: [(key: String, value: String)] {
        txt.keys.sorted().map { ($0, txt[$0] ?? "") }
    }
}
