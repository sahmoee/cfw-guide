import Foundation
import SwiftUI

/// Loads the guide and chart data (bundled snapshot, or a newer refreshed copy) and keeps the
/// reader's bookmarks and history.
@MainActor
final class ContentStore: ObservableObject {
    @Published private(set) var guide: GuideBundle
    @Published private(set) var data: CFWData
    @Published private(set) var engine: CompatibilityEngine
    @Published private(set) var groupSummaries: [String: GroupSummary] = [:]
    @Published private(set) var jailbreakableGroups: [DeviceGroup] = []
    private var jailbreakRanges: [String: VersionRange] = [:]
    @Published var bookmarks: [String] { didSet { defaults.set(bookmarks, forKey: Keys.bookmarks) } }
    @Published private(set) var recents: [String]
    @Published var refreshState: RefreshState = .idle

    enum RefreshState: Equatable {
        case idle
        case running(String)
        case finished(String)
        case failed(String)
    }

    private let defaults = UserDefaults.standard
    private var pagesByPath: [String: GuidePage] = [:]

    private enum Keys {
        static let bookmarks = "cfw.bookmarks.v1"
        static let recents = "cfw.recents.v1"
    }

    nonisolated static var cacheDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("CFWGuide", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    init() {
        let cached = try? Data(contentsOf: Self.cacheDirectory.appendingPathComponent("snapshot.json"))
        let snapshot = cached.flatMap { try? JSONDecoder().decode(ContentSnapshot.self, from: $0) }
        let guide = snapshot?.guide ?? Self.load(GuideBundle.self, name: "guide")
        let data = snapshot?.data ?? Self.load(CFWData.self, name: "data")
        self.guide = guide
        self.data = data
        engine = CompatibilityEngine(data: data)
        bookmarks = UserDefaults.standard.stringArray(forKey: Keys.bookmarks) ?? []
        recents = UserDefaults.standard.stringArray(forKey: Keys.recents) ?? []
        rebuildIndexes()
    }

    /// An unreadable cache falls back to the bundled snapshot.
    nonisolated private static func load<T: Decodable>(_ type: T.Type, name: String) -> T {
        let decoder = JSONDecoder()
        let cached = cacheDirectory.appendingPathComponent("\(name).json")
        if let data = try? Data(contentsOf: cached), let value = try? decoder.decode(T.self, from: data) {
            return value
        }
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let value = try? decoder.decode(T.self, from: data) else {
            fatalError("Bundled \(name).json is missing or unreadable")
        }
        return value
    }

    private func rebuildIndexes() {
        pagesByPath = Dictionary(guide.pages.map { (Self.normalize($0.path), $0) }, uniquingKeysWith: { first, _ in first })
        engine = CompatibilityEngine(data: data)
        var summaries: [String: GroupSummary] = [:]
        for group in data.groups { summaries[group.id] = engine.summary(for: group) }
        groupSummaries = summaries
        jailbreakableGroups = engine.jailbreakableGroups()
        var ranges: [String: VersionRange] = [:]
        for jb in data.jailbreaks {
            if let range = engine.versionRange(of: jb) { ranges[jb.name] = VersionRange(min: range.min, max: range.max) }
        }
        jailbreakRanges = ranges
    }

    func range(of jailbreak: Jailbreak) -> VersionRange? { jailbreakRanges[jailbreak.name] }

    // MARK: Pages

    nonisolated static func normalize(_ path: String) -> String {
        var value = path.removingPercentEncoding ?? path
        if let hash = value.firstIndex(of: "#") { value = String(value[..<hash]) }
        if let query = value.firstIndex(of: "?") { value = String(value[..<query]) }
        if value.hasPrefix("https://ios.cfw.guide") { value.removeFirst("https://ios.cfw.guide".count) }
        if !value.hasPrefix("/") { value = "/" + value }
        if !value.hasSuffix("/") && !value.hasSuffix(".html") { value += "/" }
        return value.lowercased()
    }

    func page(at path: String) -> GuidePage? {
        let key = Self.normalize(path)
        if let page = pagesByPath[key] { return page }
        if key.hasSuffix(".html") { return pagesByPath[String(key.dropLast(5)) + "/"] }
        return nil
    }

    func search(_ query: String) -> [GuidePage] {
        let terms = query.lowercased().split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard !terms.isEmpty else { return [] }
        let scored = guide.pages.compactMap { page -> (GuidePage, Int)? in
            let title = page.title.lowercased()
            let text = page.text.lowercased()
            guard terms.allSatisfy({ title.contains($0) || text.contains($0) }) else { return nil }
            let score = terms.reduce(0) { $0 + (title.contains($1) ? 10 : 0) + min(5, text.components(separatedBy: $1).count - 1) }
            return (page, score)
        }
        return scored.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.title < $1.0.title }.map(\.0)
    }

    nonisolated static func snippet(for page: GuidePage, query: String) -> String {
        let text = page.text
        guard let first = query.split(separator: " ").first,
              let range = text.range(of: first, options: .caseInsensitive) else { return page.description }
        let start = text.index(range.lowerBound, offsetBy: -60, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: 100, limitedBy: text.endIndex) ?? text.endIndex
        let prefix = start == text.startIndex ? "" : "…"
        let suffix = end == text.endIndex ? "" : "…"
        return prefix + String(text[start..<end]) + suffix
    }

    // MARK: Library

    func isBookmarked(_ path: String) -> Bool { bookmarks.contains(Self.normalize(path)) }

    func toggleBookmark(_ path: String) {
        let key = Self.normalize(path)
        if let index = bookmarks.firstIndex(of: key) { bookmarks.remove(at: index) } else { bookmarks.insert(key, at: 0) }
    }

    func recordVisit(_ path: String) {
        let key = Self.normalize(path)
        var list = recents.filter { $0 != key }
        list.insert(key, at: 0)
        recents = Array(list.prefix(30))
        defaults.set(recents, forKey: Keys.recents)
    }

    func clearRecents() {
        recents = []
        defaults.removeObject(forKey: Keys.recents)
    }

    // MARK: Refresh

    var lastUpdatedText: String {
        let formatter = ISO8601DateFormatter()
        let dates = [guide.generated, data.generated].compactMap { formatter.date(from: $0) }
        guard let newest = dates.min() else { return "Unknown" }
        return newest.formatted(date: .abbreviated, time: .shortened)
    }

    func refresh() async {
        if case .running = refreshState { return }
        do {
            refreshState = .running("Downloading device and jailbreak data…")
            let newData = try await Refresher.downloadData { [weak self] message in
                Task { @MainActor in self?.refreshState = .running(message) }
            }
            refreshState = .running("Downloading guide pages…")
            let newGuide = try await Refresher.downloadGuide(known: guide.pages.map(\.path)) { [weak self] message in
                Task { @MainActor in self?.refreshState = .running(message) }
            }
            let encoder = JSONEncoder()
            try encoder.encode(ContentSnapshot(guide: newGuide, data: newData)).write(to: Self.cacheDirectory.appendingPathComponent("snapshot.json"), options: .atomic)
            data = newData
            guide = newGuide
            rebuildIndexes()
            refreshState = .finished("Updated \(newGuide.pages.count) pages and \(newData.firmwares.count) firmware versions.")
        } catch {
            refreshState = .failed("Refresh failed: \(error.localizedDescription). Your saved copy is unchanged.")
        }
    }

    func resetToBundled() {
        for name in ["data.json", "guide.json", "snapshot.json"] {
            try? FileManager.default.removeItem(at: Self.cacheDirectory.appendingPathComponent(name))
        }
        guide = Self.load(GuideBundle.self, name: "guide")
        data = Self.load(CFWData.self, name: "data")
        rebuildIndexes()
        refreshState = .finished("Restored the copy that shipped with the app.")
    }
}

struct VersionRange: Hashable {
    var min: String
    var max: String
}
