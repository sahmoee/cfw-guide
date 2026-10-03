import SwiftUI

struct DeviceImage: View {
    let url: URL?
    var size: CGFloat = 56

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFit()
            } else {
                Image(systemName: "iphone").font(.system(size: size * 0.45)).foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct GetStartedView: View {
    @EnvironmentObject private var store: ContentStore
    @EnvironmentObject private var router: Router

    private var types: [String] {
        CompatibilityEngine.typeOrder.filter { type in store.jailbreakableGroups.contains { $0.type == type } }
    }

    var body: some View {
        List {
            Section {
                Button { router.open(.myDevice) } label: {
                    MyDeviceSummaryRow()
                }
                .buttonStyle(.plain)
            } header: {
                Text("This device")
            }
            Section {
                Text("Different devices need different steps to jailbreak. Pick what kind of device you have, then its model, then your version.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ForEach(types, id: \.self) { type in
                    NavigationLink(value: Route.deviceType(type)) {
                        HStack(spacing: 14) {
                            let sample = store.jailbreakableGroups.first { $0.type == type }
                            DeviceImage(url: sample?.devices.first.flatMap { store.data.devices[$0]?.imageURL }, size: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(type).font(.headline)
                                Text("\(store.jailbreakableGroups.filter { $0.type == type }.count) models")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("Choose your device")
            }
            Section {
                NavigationLink(value: Route.page("/")) { Label("Read the introduction", systemImage: "info.circle") }
                NavigationLink(value: Route.page("/faq/")) { Label("FAQ", systemImage: "questionmark.circle") }
                NavigationLink(value: Route.page("/types-of-jailbreak/")) { Label("Types of jailbreak", systemImage: "square.stack.3d.up") }
            } header: {
                Text("Required reading")
            } footer: {
                Text("Jailbreaking can void warranties and break apps. Read every introductory page before you start.")
            }
        }
        .navigationTitle("Get Started")
    }
}

struct MyDeviceSummaryRow: View {
    @EnvironmentObject private var store: ContentStore
    private let device = CurrentDevice.current

    var body: some View {
        let group = store.engine.group(containing: device.identifier)
        let name = store.data.devices[device.identifier]?.name ?? device.identifier
        HStack(spacing: 14) {
            DeviceImage(url: store.data.devices[device.identifier]?.imageURL, size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.headline)
                Text("\(device.systemName) \(device.version) (\(device.build))").font(.subheadline).foregroundStyle(.secondary)
                if let group {
                    let rows = store.engine.chart(for: group)
                    let match = rows.first { $0.builds.contains(device.build) }
                    Text(match.map { $0.isAvailable ? "Recommended: \($0.title)" : "No jailbreak for this version yet" } ?? "Tap for details")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(match?.isAvailable == true ? Color.accentColor : .secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

struct DeviceTypeView: View {
    @EnvironmentObject private var store: ContentStore
    let type: String
    @State private var query = ""

    private var groups: [DeviceGroup] {
        store.jailbreakableGroups.filter { $0.type == type && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)) }
    }

    var body: some View {
        List {
            Section {
                ForEach(groups) { group in
                    NavigationLink(value: Route.group(group.id)) {
                        GroupRow(group: group)
                    }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if type == "iPhone" {
                        Text("All \"Plus\", \"Max\" and \"mini\" iPhones are functionally identical to the regular models.")
                    }
                    Text("If your \(type) is not listed, it cannot be jailbroken at all.")
                }
            }
        }
        .searchable(text: $query, prompt: "Search \(type) models")
        .navigationTitle(type)
    }
}

struct GroupRow: View {
    @EnvironmentObject private var store: ContentStore
    let group: DeviceGroup

    var body: some View {
        let summary = store.groupSummaries[group.id]
        HStack(spacing: 14) {
            DeviceImage(url: group.devices.first.flatMap { store.data.devices[$0]?.imageURL }, size: 50)
            VStack(alignment: .leading, spacing: 3) {
                Text(group.name).font(.headline)
                if let latest = summary?.latestFirmware {
                    Text("Latest: \(latest.displayName)").font(.caption).foregroundStyle(.secondary)
                }
                if let jb = summary?.latestJailbreakable {
                    Text("Jailbreakable up to \(jb.displayName)").font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor)
                }
            }
        }
    }
}

struct GroupChartView: View {
    @EnvironmentObject private var store: ContentStore
    let groupID: String
    @State private var versionQuery = ""

    var body: some View {
        if let group = store.data.groups.first(where: { $0.id == groupID }) {
            content(group)
        } else {
            ContentUnavailableView("Device not found", systemImage: "iphone.slash")
        }
    }

    private func content(_ group: DeviceGroup) -> some View {
        let rows = store.engine.chart(for: group)
        let summary = store.groupSummaries[group.id]
        let osStr = summary?.latestFirmware?.osStr ?? "iOS"
        let filtered = versionQuery.isEmpty ? rows : rows.filter { row in
            let fws = store.data.firmwares.filter { row.builds.contains($0.build) }
            return fws.contains { $0.version.hasPrefix(versionQuery) || $0.build.localizedCaseInsensitiveContains(versionQuery) }
        }
        return List {
            Section {
                HStack(spacing: 16) {
                    DeviceImage(url: group.devices.first.flatMap { store.data.devices[$0]?.imageURL }, size: 72)
                    VStack(alignment: .leading, spacing: 4) {
                        if let socs = summary?.socs, !socs.isEmpty { Text("SoC: \(socs.joined(separator: ", "))") }
                        if let archs = summary?.archs, !archs.isEmpty { Text("Architecture: \(archs.joined(separator: ", "))") }
                        if let released = summary?.released { Text("Released: \(released)") }
                        if let latest = summary?.latestFirmware { Text("Latest version: \(latest.displayName)") }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            Section {
                ForEach(filtered) { row in
                    ChartRowView(row: row)
                }
            } header: {
                Text("Choose your version")
            } footer: {
                Text("\"From\" and \"to\" are inclusive: a row from 15.0 to 16.6.1 covers both of those versions and everything in between.")
            }
            Section("Finding your \(osStr) version") {
                Label("Open Settings, then General → About → \(group.type == "Apple TV" ? "tvOS" : "Software Version").", systemImage: "gear")
                    .font(.subheadline)
                if let url = URL(string: "https://appledb.dev/device/" + (group.name.replacingOccurrences(of: " ", with: "-").addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "") + ".html") {
                    Button { ExternalLink.open(url) } label: { Label("Show every version on AppleDB", systemImage: "safari") }
                }
            }
        }
        .searchable(text: $versionQuery, prompt: "Filter by version, e.g. 16.5")
        .navigationTitle(group.name)
    }
}

struct ChartRowView: View {
    @EnvironmentObject private var router: Router
    let row: ChartRow

    var body: some View {
        Button {
            if let path = row.guidePath { router.openLink(path) }
            else if let external = row.externalURL, let url = URL(string: external) { ExternalLink.open(url) }
        } label: {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.from == row.to ? row.from : "\(row.from) – \(row.to)")
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                    Text(row.title)
                        .font(.subheadline)
                        .foregroundStyle(row.isAvailable ? Color.accentColor : .secondary)
                }
                Spacer()
                if row.guidePath != nil { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary) }
                else if row.externalURL != nil { Image(systemName: "arrow.up.right.square").font(.caption).foregroundStyle(.tertiary) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!row.isAvailable)
        .accessibilityElement(children: .combine)
    }
}

struct MyDeviceView: View {
    @EnvironmentObject private var store: ContentStore
    @EnvironmentObject private var router: Router
    private let device = CurrentDevice.current

    var body: some View {
        let known = store.data.devices[device.identifier]
        let group = store.engine.group(containing: device.identifier)
        let rows = group.map { store.engine.chart(for: $0) } ?? []
        let match = rows.first { $0.builds.contains(device.build) }
        let signed = store.engine.signedFirmwares(for: [device.identifier])
        List {
            Section {
                HStack(spacing: 16) {
                    DeviceImage(url: known?.imageURL, size: 72)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(known?.name ?? device.identifier).font(.title3.weight(.semibold))
                        Text("\(device.systemName) \(device.version) · build \(device.build)").font(.subheadline)
                        Text(device.identifier + (known?.soc.map { " · \($0)" } ?? "")).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Recommendation") {
                if let match {
                    if match.isAvailable {
                        ChartRowView(row: match)
                        Text("This matches the chart for your exact build. Read the whole guide before you start.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Label("There's no jailbreak for \(device.systemName) \(device.version) on this device yet.", systemImage: "xmark.octagon")
                        Text("Don't update if you're waiting for one. Saving blobs keeps future options open.")
                            .font(.caption).foregroundStyle(.secondary)
                        NavigationLink(value: Route.page("/saving-blobs/")) { Label("Saving blobs", systemImage: "externaldrive") }
                        NavigationLink(value: Route.page("/blocking-updates/")) { Label("Blocking updates", systemImage: "hand.raised") }
                    }
                } else if group == nil {
                    Text("This device isn't in the jailbreak chart. It may be too new, or it may not be jailbreakable.")
                } else {
                    Text("Build \(device.build) isn't in the saved data yet. Refresh the guide in More, or pick your version manually.")
                }
                if let group {
                    NavigationLink(value: Route.group(group.id)) { Label("See every version for \(group.name)", systemImage: "list.bullet") }
                }
            }
            Section {
                if signed.isEmpty {
                    Text("No signed versions found in the saved data.").foregroundStyle(.secondary)
                } else {
                    ForEach(signed) { fw in
                        HStack {
                            Text(fw.displayName)
                            Spacer()
                            Text(fw.build).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Versions Apple is signing")
            } footer: {
                Text("You can only restore or update to signed versions without saved blobs. Signing status comes from AppleDB as of the last refresh.")
            }
        }
        .navigationTitle("This Device")
    }
}
