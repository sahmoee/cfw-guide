import Foundation

struct ContentSnapshot: Codable {
    var guide: GuideBundle
    var data: CFWData
}

// MARK: - Guide pages (from ios.cfw.guide)

struct GuideBundle: Codable {
    var generated: String
    var pages: [GuidePage]
    var sections: [GuideSection]
}

struct GuidePage: Codable, Identifiable, Hashable {
    var path: String
    var title: String
    var html: String
    var text: String
    var description: String
    var prev: PageLink?
    var next: PageLink?
    var id: String { path }
}

struct PageLink: Codable, Hashable {
    var path: String
    var title: String
}

struct GuideSection: Codable, Identifiable, Hashable {
    var title: String
    var links: [PageLink]
    var id: String { title }
}

// MARK: - Device, firmware and jailbreak data (from AppleDB, which powers the site's charts)

struct CFWData: Codable {
    var generated: String
    var devices: [String: Device]
    var groups: [DeviceGroup]
    var firmwares: [Firmware]
    var jailbreaks: [Jailbreak]
    var bypasses: [BypassApp]
}

struct Device: Codable, Hashable {
    var name: String
    var type: String
    var soc: String?
    var arch: String?
    var released: String?
    var identifiers: [String]
    var models: [String]
    var image: String?
    var group: Bool

    var imageURL: URL? {
        guard let image else { return nil }
        let encoded = image.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? image
        return URL(string: "https://img.appledb.dev/device@preview/\(encoded).webp")
    }
}

struct DeviceGroup: Codable, Hashable, Identifiable {
    var name: String
    var type: String
    var devices: [String]
    var id: String { name + "|" + type }
}

enum SignedState: Codable, Hashable {
    case all
    case devices([String])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let flag = try? container.decode(Bool.self) {
            self = flag ? .all : .devices([])
        } else {
            self = .devices((try? container.decode([String].self)) ?? [])
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .all: try container.encode(true)
        case .devices(let list): try container.encode(list)
        }
    }

    func isSigned(for keys: Set<String>) -> Bool {
        switch self {
        case .all: return true
        case .devices(let list): return list.contains { keys.contains($0) }
        }
    }
}

struct Firmware: Codable, Hashable, Identifiable {
    var osStr: String
    var version: String
    var build: String
    var released: String?
    var devices: [String]
    var signed: SignedState
    var id: String { osStr + build }
    var displayName: String { "\(osStr) \(version)" }
}

struct Jailbreak: Codable, Hashable, Identifiable {
    var name: String
    var priority: Int
    var hideFromGuide: Bool
    var type: String?
    var notes: String?
    var latestVersion: String?
    var icon: String?
    var website: WebLink?
    var firmwareRange: [String]?
    var guides: [JailbreakGuide]
    var compatibility: [Compatibility]
    var id: String { name }

    var iconPath: String? { icon }
}

struct WebLink: Codable, Hashable {
    var name: String
    var url: String
}

struct JailbreakGuide: Codable, Hashable {
    var text: String?
    var name: String?
    var url: String?
    var pkgman: String?
    var firmwares: [String]?
    var devices: [String]?
    var updateLinks: [UpdateLink]?
}

struct UpdateLink: Codable, Hashable {
    var text: String
    var link: String
}

struct Compatibility: Codable, Hashable {
    var devices: [String]
    var firmwares: [String]
}

struct BypassApp: Codable, Hashable, Identifiable {
    var name: String
    var bundleId: String
    var uri: String?
    var icon: String?
    var notes: String?
    var bypasses: [Bypass]
    var id: String { bundleId + name }
}

struct Bypass: Codable, Hashable {
    var name: String?
    var guide: String?
    var repository: String?
    var notes: String?
    var appNotes: String?
    var version: String?
}

// MARK: - Version helpers

enum VersionSort {
    /// Numeric parts of "17.0.1" or "4.2.1 (8C148)" for ordering.
    static func key(_ version: String) -> [Int] {
        let head = version.split(separator: " ").first.map(String.init) ?? version
        var parts = head.split(separator: ".").compactMap { Int($0.filter(\.isNumber)) }
        while parts.count < 4 { parts.append(0) }
        return Array(parts.prefix(4))
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        key(a).lexicographicallyPrecedes(key(b)) == false && key(a) != key(b)
    }
}
