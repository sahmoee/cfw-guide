import SwiftUI

struct ToolsView: View {
    var body: some View {
        List {
            Section {
                NavigationLink(value: Route.myDevice) {
                    ToolRow(icon: "iphone.radiowaves.left.and.right", title: "This device", detail: "Your model, version, build, the matching guide and signed versions.")
                }
                NavigationLink(value: Route.signed) {
                    ToolRow(icon: "checkmark.seal", title: "Signed versions", detail: "Which versions Apple still signs for any device.")
                }
                NavigationLink(value: Route.bypass) {
                    ToolRow(icon: "eye.slash", title: "Jailbreak detection bypasses", detail: "Look up an app and the tweaks known to hide a jailbreak from it.")
                }
                NavigationLink(value: Route.bookmarks) {
                    ToolRow(icon: "bookmark", title: "Bookmarks and history", detail: "Pages you saved or read recently.")
                }
            }
            Section("Before you jailbreak") {
                NavigationLink(value: Route.page("/saving-blobs/")) { Label("Save your blobs", systemImage: "externaldrive.badge.checkmark") }
                NavigationLink(value: Route.page("/blocking-updates/")) { Label("Block OTA updates", systemImage: "hand.raised") }
                NavigationLink(value: Route.page("/sideloading-apps/")) { Label("Sideload apps", systemImage: "arrow.down.app") }
                NavigationLink(value: Route.page("/futurerestore/")) { Label("FutureRestore", systemImage: "clock.arrow.circlepath") }
            }
            Section("If something goes wrong") {
                NavigationLink(value: Route.page("/troubleshooting/")) { Label("Troubleshooting", systemImage: "stethoscope") }
                NavigationLink(value: Route.page("/restoring-rootfs/")) { Label("Restoring RootFS", systemImage: "arrow.uturn.backward") }
            }
        }
        .navigationTitle("Tools")
    }
}

struct ToolRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.title3).foregroundStyle(Color.accentColor).frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct SignedFirmwareView: View {
    @EnvironmentObject private var store: ContentStore
    @State private var selectedID: String?
    @State private var query = ""

    private var groups: [DeviceGroup] {
        store.data.groups
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
            .sorted { lhs, rhs in
                let l = CompatibilityEngine.typeOrder.firstIndex(of: lhs.type) ?? 99
                let r = CompatibilityEngine.typeOrder.firstIndex(of: rhs.type) ?? 99
                if l != r { return l < r }
                let ld = lhs.devices.first.flatMap { store.data.devices[$0]?.released } ?? ""
                let rd = rhs.devices.first.flatMap { store.data.devices[$0]?.released } ?? ""
                return ld > rd
            }
    }

    var body: some View {
        List {
            Section {
                Text("Apple only lets you restore or update to versions it is signing, unless you saved blobs earlier. Status is from AppleDB as of the last refresh (\(store.lastUpdatedText)).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(groups) { group in
                DisclosureGroup(isExpanded: Binding(get: { selectedID == group.id }, set: { selectedID = $0 ? group.id : nil })) {
                    let signed = store.engine.signedFirmwares(for: Set(group.devices))
                    if signed.isEmpty {
                        Text("Nothing signed").foregroundStyle(.secondary)
                    }
                    ForEach(signed) { fw in
                        HStack {
                            Text(fw.displayName)
                            Spacer()
                            Text(fw.build).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                } label: {
                    HStack(spacing: 10) {
                        DeviceImage(url: group.devices.first.flatMap { store.data.devices[$0]?.imageURL }, size: 32)
                        Text(group.name)
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Search devices")
        .navigationTitle("Signed Versions")
    }
}

struct BypassListView: View {
    @EnvironmentObject private var store: ContentStore
    @State private var query = ""
    @State private var selected: BypassApp?

    private var apps: [BypassApp] {
        store.data.bypasses
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.bundleId.localizedCaseInsensitiveContains(query) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        List {
            Section {
                NavigationLink(value: Route.page("/blocking-jailbreak-detection/")) {
                    Label("How to block jailbreak detection", systemImage: "book")
                }
            } footer: {
                Text("\(store.data.bypasses.count) apps from the AppleDB bypass list. A bypass that worked before can stop working after an app update.")
            }
            ForEach(apps) { app in
                Button { selected = app } label: {
                    HStack(spacing: 12) {
                        AsyncImage(url: app.icon.flatMap(URL.init(string:))) { phase in
                            if let image = phase.image { image.resizable() } else { Color.secondary.opacity(0.15) }
                        }
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.name).font(.headline).foregroundStyle(.primary)
                            Text(app.bypasses.isEmpty ? "No known bypass" : app.bypasses.compactMap(\.name).joined(separator: ", "))
                                .font(.caption).foregroundStyle(app.bypasses.isEmpty ? Color.secondary : Color.accentColor).lineLimit(2)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .searchable(text: $query, prompt: "Search apps or bundle IDs")
        .navigationTitle("Detection Bypasses")
        .sheet(item: $selected) { app in
            NavigationStack { BypassDetailView(app: app) }
                .presentationDetents([.medium, .large])
        }
    }
}

struct BypassDetailView: View {
    let app: BypassApp
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                LabeledContent("Bundle ID", value: app.bundleId).textSelection(.enabled)
                if let uri = app.uri, let url = URL(string: uri) {
                    Link(destination: url) { Label("View on the App Store", systemImage: "app.badge") }
                }
                if let notes = app.notes { Text(markdown(notes)).font(.subheadline) }
            }
            if app.bypasses.isEmpty {
                Section { Text("No bypass is listed for this app.").foregroundStyle(.secondary) }
            }
            ForEach(Array(app.bypasses.enumerated()), id: \.offset) { _, bypass in
                Section(bypass.name ?? "Bypass") {
                    if let version = bypass.version { LabeledContent("Version", value: version) }
                    if let notes = bypass.notes { Label { Text(markdown(notes)) } icon: { Image(systemName: "exclamationmark.triangle") } }
                    if let appNotes = bypass.appNotes { Text(markdown(appNotes)).font(.subheadline) }
                    if let repo = bypass.repository, let url = URL(string: repo) {
                        Button { ExternalLink.open(url) } label: { Label("Add repository", systemImage: "plus.square.on.square") }
                    }
                    if let guide = bypass.guide, let url = URL(string: guide) {
                        Button { ExternalLink.open(url) } label: { Label("Setup guide", systemImage: "book") }
                    }
                }
            }
        }
        .navigationTitle(app.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }

    private func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}
