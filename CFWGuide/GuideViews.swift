import SwiftUI

struct GuidesView: View {
    @EnvironmentObject private var store: ContentStore
    @State private var query = ""

    private static let coreGuides: [PageLink] = [
        PageLink(path: "/saving-blobs/", title: "Saving Blobs"),
        PageLink(path: "/sideloading-apps/", title: "Sideloading Apps"),
        PageLink(path: "/blocking-jailbreak-detection/", title: "Jailbreak Detection"),
        PageLink(path: "/installing-trollstore/", title: "Installing TrollStore"),
        PageLink(path: "/updating-blobless/", title: "Updating (Blobless)"),
        PageLink(path: "/blocking-updates/", title: "Blocking Updates"),
    ]
    private static let helpPages: [PageLink] = [
        PageLink(path: "/faq/", title: "FAQ"),
        PageLink(path: "/troubleshooting/", title: "Troubleshooting"),
        PageLink(path: "/recommended-repos/", title: "Recommended Repos"),
        PageLink(path: "/types-of-jailbreak/", title: "Jailbreak Types"),
        PageLink(path: "/package-managers/", title: "Package Managers"),
    ]

    var body: some View {
        List {
            if query.isEmpty {
                section("Guides", Self.coreGuides, icon: "book.closed")
                section("Help", Self.helpPages, icon: "lifepreserver")
                ForEach(store.guide.sections.filter { $0.title != "ios.cfw.guide" }) { section in
                    self.section(section.title.replacingOccurrences(of: "'", with: ""), section.links, icon: "doc.text")
                }
                Section("Everything") {
                    NavigationLink {
                        AllPagesView()
                    } label: {
                        Label("All \(store.guide.pages.count) pages", systemImage: "list.bullet.rectangle")
                    }
                }
            } else {
                let results = store.search(query)
                if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    ForEach(results) { page in
                        NavigationLink(value: Route.page(page.path)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(page.title).font(.headline)
                                Text(ContentStore.snippet(for: page, query: query))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(3)
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Search every guide")
        .navigationTitle("Guides")
    }

    @ViewBuilder
    private func section(_ title: String, _ links: [PageLink], icon: String) -> some View {
        Section(title) {
            ForEach(links, id: \.path) { link in
                NavigationLink(value: Route.page(link.path)) {
                    HStack {
                        Label(link.title, systemImage: icon)
                        if store.page(at: link.path) == nil {
                            Spacer()
                            Image(systemName: "globe").font(.caption).foregroundStyle(.secondary)
                                .accessibilityLabel("Opens on the web")
                        }
                    }
                }
            }
        }
    }
}

struct AllPagesView: View {
    @EnvironmentObject private var store: ContentStore
    @State private var query = ""

    var body: some View {
        let pages = store.guide.pages
            .filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        List(pages) { page in
            NavigationLink(value: Route.page(page.path)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(page.title)
                    Text(page.path).font(.caption2.monospaced()).foregroundStyle(.secondary)
                }
            }
        }
        .searchable(text: $query, prompt: "Filter by title")
        .navigationTitle("All Pages")
    }
}

struct ReaderView: View {
    @EnvironmentObject private var store: ContentStore
    @EnvironmentObject private var router: Router
    let path: String
    @AppStorage("cfw.textScale") private var textScale = 1.0

    private var webURL: URL {
        URL(string: Refresher.site + (path.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? path)) ?? URL(string: Refresher.site)!
    }

    var body: some View {
        Group {
            if let page = store.page(at: path) {
                PageWebView(page: page, textScale: textScale) { link in router.openLink(link) }
                    .ignoresSafeArea(edges: .bottom)
                    .safeAreaInset(edge: .bottom) { pager(page) }
                    .navigationTitle(page.title)
                    .onAppear { store.recordVisit(page.path) }
            } else {
                ContentUnavailableView {
                    Label("Not in the offline copy", systemImage: "wifi.exclamationmark")
                } description: {
                    Text("This page isn't saved in the app. It may be new, or the site may have removed it.")
                } actions: {
                    Button("Open on ios.cfw.guide") { ExternalLink.open(webURL) }
                        .buttonStyle(.borderedProminent)
                }
                .navigationTitle("Page")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if store.page(at: path) != nil {
                    Button {
                        store.toggleBookmark(path)
                    } label: {
                        Image(systemName: store.isBookmarked(path) ? "bookmark.fill" : "bookmark")
                    }
                    .accessibilityLabel(store.isBookmarked(path) ? "Remove bookmark" : "Bookmark")
                }
                Menu {
                    ShareLink(item: webURL) { Label("Share link", systemImage: "square.and.arrow.up") }
                    Button { ExternalLink.open(webURL) } label: { Label("Open on the web", systemImage: "safari") }
                    Divider()
                    Button { textScale = min(1.6, textScale + 0.1) } label: { Label("Larger text", systemImage: "textformat.size.larger") }
                    Button { textScale = max(0.8, textScale - 0.1) } label: { Label("Smaller text", systemImage: "textformat.size.smaller") }
                    Button { textScale = 1.0 } label: { Label("Default text size", systemImage: "textformat") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Page options")
            }
        }
    }

    @ViewBuilder
    private func pager(_ page: GuidePage) -> some View {
        if page.prev != nil || page.next != nil {
            HStack {
                if let prev = page.prev {
                    Button { router.openLink(resolve(prev.path, from: page.path)) } label: {
                        Label(prev.title, systemImage: "chevron.left").lineLimit(1)
                    }
                }
                Spacer()
                if let next = page.next {
                    Button { router.openLink(resolve(next.path, from: page.path)) } label: {
                        HStack(spacing: 4) { Text(next.title).lineLimit(1); Image(systemName: "chevron.right") }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }

    /// Next/previous links can be relative ("using-sileo.html").
    private func resolve(_ link: String, from current: String) -> String {
        if link.hasPrefix("/") { return link }
        let base = current.hasSuffix("/") ? current : (current as NSString).deletingLastPathComponent + "/"
        return base + link
    }
}

struct BookmarksView: View {
    @EnvironmentObject private var store: ContentStore

    var body: some View {
        List {
            Section("Bookmarks") {
                if store.bookmarks.isEmpty {
                    Text("Tap the bookmark button on any guide to keep it here.").foregroundStyle(.secondary)
                }
                ForEach(store.bookmarks, id: \.self) { path in
                    NavigationLink(value: Route.page(path)) { Text(store.page(at: path)?.title ?? path) }
                }
                .onDelete { store.bookmarks.remove(atOffsets: $0) }
                .onMove { store.bookmarks.move(fromOffsets: $0, toOffset: $1) }
            }
            Section {
                ForEach(store.recents, id: \.self) { path in
                    NavigationLink(value: Route.page(path)) { Text(store.page(at: path)?.title ?? path) }
                }
            } header: {
                HStack {
                    Text("Recently read")
                    Spacer()
                    if !store.recents.isEmpty { Button("Clear") { store.clearRecents() }.font(.caption) }
                }
            }
        }
        .toolbar { EditButton() }
        .navigationTitle("Saved")
    }
}
