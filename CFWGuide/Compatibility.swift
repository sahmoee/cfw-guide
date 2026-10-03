import Foundation

/// One row of the "which jailbreak for which version" chart, mirroring the site's device page.
struct ChartRow: Identifiable, Hashable {
    var from: String
    var to: String
    var title: String
    var guidePath: String?
    var externalURL: String?
    var jailbreakName: String?
    var builds: [String]
    var id: String { from + to + title }
    var isAvailable: Bool { jailbreakName != nil }
}

struct GroupSummary: Hashable {
    var latestFirmware: Firmware?
    var latestJailbreakable: Firmware?
    var released: String?
    var socs: [String]
    var archs: [String]
}

/// The same rules the site's chart components use, applied to the bundled AppleDB data.
struct CompatibilityEngine {
    let data: CFWData
    private let jailbreaks: [Jailbreak]
    /// Compatibility entries as sets, so chart lookups stay fast.
    private let index: [(jailbreak: Jailbreak, entries: [(devices: Set<String>, firmwares: Set<String>)])]

    static let typeOrder = ["iPhone", "iPad", "iPad Air", "iPad Pro", "iPad mini", "iPod touch", "Apple TV"]

    init(data: CFWData) {
        self.data = data
        let sorted = data.jailbreaks.filter { !$0.hideFromGuide }.sorted { $0.priority < $1.priority }
        jailbreaks = sorted
        index = sorted.map { jb in (jb, jb.compatibility.map { (Set($0.devices), Set($0.firmwares)) }) }
    }

    func firmwares(for group: DeviceGroup) -> [Firmware] {
        let keys = Set(group.devices)
        return data.firmwares.filter { $0.devices.contains(where: keys.contains) }
    }

    /// The best jailbreak for one build on one set of devices, or nil when none is known.
    func jailbreak(for build: String, devices keys: Set<String>) -> Jailbreak? {
        index.first { item in
            item.entries.contains { $0.firmwares.contains(build) && !$0.devices.isDisjoint(with: keys) }
        }?.jailbreak
    }

    /// The guide page to follow for that jailbreak, preferring entries scoped to both devices and firmwares.
    func guide(for jailbreak: Jailbreak, build: String, devices keys: Set<String>) -> JailbreakGuide? {
        let matching = jailbreak.guides.filter { guide in
            let fwOK = guide.firmwares.map { $0.contains(build) } ?? true
            let devOK = guide.devices.map { $0.contains(where: keys.contains) } ?? true
            return fwOK && devOK
        }
        let scored = matching.enumerated().sorted { lhs, rhs in
            let l = lhs.element.firmwares != nil && lhs.element.devices != nil
            let r = rhs.element.firmwares != nil && rhs.element.devices != nil
            if l != r { return l }
            return lhs.offset < rhs.offset
        }
        return scored.first?.element
    }

    func chart(for group: DeviceGroup) -> [ChartRow] {
        let keys = Set(group.devices)
        var rows: [ChartRow] = []
        for fw in firmwares(for: group) {
            var row = ChartRow(from: fw.version, to: fw.version, title: "No jailbreak available", builds: [fw.build])
            if let jb = jailbreak(for: fw.build, devices: keys) {
                row.jailbreakName = jb.name
                row.title = jb.name
                row.externalURL = "https://appledb.dev/jailbreak/\(jb.name.replacingOccurrences(of: " ", with: "-"))"
                if let guide = guide(for: jb, build: fw.build, devices: keys), let name = guide.name, let url = guide.url {
                    row.title = name
                    row.guidePath = url
                    row.externalURL = nil
                }
            }
            if let last = rows.last, last.title == row.title, last.guidePath == row.guidePath, last.externalURL == row.externalURL, last.jailbreakName == row.jailbreakName {
                rows[rows.count - 1].from = fw.version
                rows[rows.count - 1].builds.append(fw.build)
            } else {
                rows.append(row)
            }
        }
        return rows
    }

    func summary(for group: DeviceGroup) -> GroupSummary {
        let fws = firmwares(for: group)
        let keys = Set(group.devices)
        let devices = group.devices.compactMap { data.devices[$0] }
        return GroupSummary(
            latestFirmware: fws.first,
            latestJailbreakable: fws.first { jailbreak(for: $0.build, devices: keys) != nil },
            released: devices.compactMap(\.released).sorted().first,
            socs: Array(Set(devices.compactMap(\.soc))).sorted(),
            archs: Array(Set(devices.compactMap(\.arch))).sorted()
        )
    }

    /// Groups shown in Get Started: only those with at least one jailbreak, newest first per type.
    func jailbreakableGroups() -> [DeviceGroup] {
        data.groups.filter { summary(for: $0).latestJailbreakable != nil }
            .sorted { lhs, rhs in
                if lhs.type != rhs.type {
                    return (Self.typeOrder.firstIndex(of: lhs.type) ?? 99) < (Self.typeOrder.firstIndex(of: rhs.type) ?? 99)
                }
                let l = lhs.devices.first.flatMap { data.devices[$0]?.released } ?? ""
                let r = rhs.devices.first.flatMap { data.devices[$0]?.released } ?? ""
                return l > r
            }
    }

    func group(containing key: String) -> DeviceGroup? {
        data.groups.first { $0.devices.contains(key) }
    }

    func supportedDevices(of jailbreak: Jailbreak) -> [DeviceGroup] {
        let keys = Set(jailbreak.compatibility.flatMap(\.devices))
        return data.groups.filter { $0.devices.contains(where: keys.contains) }
    }

    func versionRange(of jailbreak: Jailbreak) -> (min: String, max: String)? {
        let builds = Set(jailbreak.compatibility.flatMap(\.firmwares))
        let versions = data.firmwares.filter { builds.contains($0.build) }.map(\.version)
        guard let low = versions.min(by: { VersionSort.key($0).lexicographicallyPrecedes(VersionSort.key($1)) }),
              let high = versions.max(by: { VersionSort.key($0).lexicographicallyPrecedes(VersionSort.key($1)) }) else { return nil }
        return (low, high)
    }

    func signedFirmwares(for keys: Set<String>) -> [Firmware] {
        data.firmwares.filter { $0.devices.contains(where: keys.contains) && $0.signed.isSigned(for: keys) }
    }
}

/// What this iPhone or iPad is running, read on device.
struct CurrentDevice {
    let identifier: String
    let systemName: String
    let version: String
    let build: String

    static var current: CurrentDevice {
        var info = utsname()
        uname(&info)
        var machine = withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { machine = simulated }
        var size = 0
        sysctlbyname("kern.osversion", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("kern.osversion", &buffer, &size, nil, 0)
        let build = String(cString: buffer)
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let version = os.patchVersion > 0 ? "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)" : "\(os.majorVersion).\(os.minorVersion)"
        let systemName = machine.hasPrefix("iPad") ? "iPadOS" : machine.hasPrefix("AppleTV") ? "tvOS" : "iOS"
        return CurrentDevice(identifier: machine, systemName: systemName, version: version, build: build)
    }
}
