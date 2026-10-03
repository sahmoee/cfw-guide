import SwiftUI
import UIKit

struct JailbreakIcon: View {
    let jailbreak: Jailbreak
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let icon = jailbreak.iconPath, let file = AssetCache.localFile(for: icon), let image = UIImage(contentsOfFile: file.path) {
                Image(uiImage: image).resizable().scaledToFit()
            } else if let icon = jailbreak.iconPath, icon.hasPrefix("/") {
                AsyncImage(url: URL(string: Refresher.site + icon)) { phase in
                    if let image = phase.image { image.resizable().scaledToFit() } else { placeholder }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
            .fill(Color.accentColor.opacity(0.15))
            .overlay(Text(String(jailbreak.name.prefix(1))).font(.system(size: size * 0.45, weight: .bold)).foregroundStyle(Color.accentColor))
    }
}

struct JailbreakListView: View {
    @EnvironmentObject private var store: ContentStore
    @State private var query = ""
    @State private var filter = "Guided"

    private var filters: [String] { ["Guided", "All"] + Array(Set(store.data.jailbreaks.compactMap(\.type))).sorted() }

    private var list: [Jailbreak] {
        store.data.jailbreaks
            .filter { jb in
                switch filter {
                case "Guided": return !jb.hideFromGuide && jb.guides.contains { $0.url != nil }
                case "All": return true
                default: return jb.type == filter
                }
            }
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || ($0.notes ?? "").localizedCaseInsensitiveContains(query) }
            .sorted { lhs, rhs in
                let l = store.range(of: lhs)?.max ?? "0", r = store.range(of: rhs)?.max ?? "0"
                if VersionSort.key(l) != VersionSort.key(r) { return VersionSort.key(r).lexicographicallyPrecedes(VersionSort.key(l)) }
                return lhs.name < rhs.name
            }
    }

    var body: some View {
        List {
            Section {
                Picker("Show", selection: $filter) {
                    ForEach(filters, id: \.self) { Text($0).tag($0) }
                }
            }
            ForEach(list) { jb in
                NavigationLink(value: Route.jailbreak(jb.name)) {
                    HStack(spacing: 12) {
                        JailbreakIcon(jailbreak: jb)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(jb.name).font(.headline)
                            if let range = store.range(of: jb) {
                                Text("\(range.min) – \(range.max)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            if let type = jb.type { Text(type).font(.caption2).foregroundStyle(Color.accentColor) }
                        }
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Search jailbreaks")
        .navigationTitle("Jailbreaks")
    }
}

struct JailbreakDetailView: View {
    @EnvironmentObject private var store: ContentStore
    @EnvironmentObject private var router: Router
    let name: String

    var body: some View {
        if let jb = store.data.jailbreaks.first(where: { $0.name == name }) {
            detail(jb)
        } else {
            ContentUnavailableView("Jailbreak not found", systemImage: "questionmark.diamond")
        }
    }

    private func detail(_ jb: Jailbreak) -> some View {
        let groups = store.engine.supportedDevices(of: jb)
        let types = CompatibilityEngine.typeOrder.filter { type in groups.contains { $0.type == type } }
        return List {
            Section {
                HStack(spacing: 16) {
                    JailbreakIcon(jailbreak: jb, size: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(jb.name).font(.title2.weight(.bold))
                        if let type = jb.type { Text(type).font(.subheadline).foregroundStyle(Color.accentColor) }
                        if let version = jb.latestVersion { Text("Latest release \(version)").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                if let notes = jb.notes { Text(notes).font(.subheadline) }
                if let range = store.range(of: jb) {
                    LabeledContent("Supported versions", value: "\(range.min) – \(range.max)")
                }
                if let website = jb.website, let url = URL(string: website.url) {
                    Button { ExternalLink.open(url) } label: { Label(website.name, systemImage: "safari") }
                }
                if let type = jb.type, store.page(at: "/types-of-jailbreak/") != nil {
                    NavigationLink(value: Route.page("/types-of-jailbreak/")) {
                        Label("What \"\(type)\" means", systemImage: "info.circle")
                    }
                }
            }
            if !jb.guides.isEmpty {
                Section("Guides") {
                    ForEach(Array(jb.guides.enumerated()), id: \.offset) { _, guide in
                        if let url = guide.url {
                            Button { router.openLink(url) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(guide.name ?? guide.text ?? url).font(.subheadline.weight(.semibold))
                                    if let text = guide.text, text != guide.name { Text(text).font(.caption).foregroundStyle(.secondary) }
                                    if let pkg = guide.pkgman { Text("Package manager: \(pkg.capitalized)").font(.caption2).foregroundStyle(.secondary) }
                                }
                            }
                        }
                        ForEach(guide.updateLinks ?? [], id: \.link) { link in
                            Button { router.openLink(link.link) } label: {
                                Label(link.text, systemImage: "arrow.up.circle").font(.subheadline)
                            }
                        }
                    }
                }
            }
            ForEach(types, id: \.self) { type in
                Section("Supported \(type) models") {
                    ForEach(groups.filter { $0.type == type }) { group in
                        NavigationLink(value: Route.group(group.id)) { Text(group.name) }
                    }
                }
            }
        }
        .navigationTitle(jb.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
