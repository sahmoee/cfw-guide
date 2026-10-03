import Foundation

/// Rebuilds guide.json and data.json on device from the same public sources the bundled copy
/// was made from: the ios.cfw.guide pages and the AppleDB API.
enum Refresher {
    typealias Progress = @Sendable (String) -> Void

    static let site = "https://ios.cfw.guide"
    static let api = "https://api.appledb.dev"
    static let allowedOS: Set<String> = ["iOS", "iPhone Software", "iPhone OS", "iPadOS", "tvOS", "Apple TV Software"]
    static let allowedTypes: Set<String> = ["iPhone", "iPad", "iPad Pro", "iPad mini", "iPad Air", "iPod touch", "Apple TV"]

    enum RefreshError: LocalizedError {
        case badResponse(String)
        var errorDescription: String? {
            switch self { case .badResponse(let what): return "Could not download \(what)" }
        }
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.httpAdditionalHeaders = ["User-Agent": "CFWGuide-iOS/1.0"]
        return URLSession(configuration: config)
    }()

    static func fetch(_ urlString: String) async throws -> Data {
        guard let url = URL(string: urlString) else { throw RefreshError.badResponse(urlString) }
        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw RefreshError.badResponse(url.lastPathComponent) }
        return data
    }

    private static func json(_ path: String) async throws -> Any {
        try JSONSerialization.jsonObject(with: try await fetch(api + path))
    }

    // MARK: Data

    static func downloadData(progress: @escaping Progress) async throws -> CFWData {
        progress("Downloading devices…")
        let devicesRaw = try await json("/device/main.json") as? [[String: Any]] ?? []
        let groupsRaw = try await json("/group/main.json") as? [[String: Any]] ?? []
        let imagesData = try await fetch("https://img.appledb.dev/main.json")
        let imagesRaw = (try JSONSerialization.jsonObject(with: imagesData)) as? [[String: Any]] ?? []
        progress("Downloading jailbreaks…")
        let jailbreaksRaw = try await json("/jailbreak/main.json") as? [[String: Any]] ?? []
        let bypassRaw = try await json("/bypass/main.json") as? [[String: Any]] ?? []
        progress("Downloading iOS versions (about 25 MB)…")
        let iosRaw = try await json("/ios/iOS/main.json") as? [[String: Any]] ?? []
        progress("Downloading tvOS versions…")
        let tvRaw = try await json("/ios/tvOS/main.json") as? [[String: Any]] ?? []
        progress("Building charts…")

        var imageIndex: [String: String] = [:]
        for item in imagesRaw {
            if let key = item["key"] as? String, let first = (item["index"] as? [[String: Any]])?.first?["id"] as? String {
                imageIndex[key] = first
            }
        }

        var devices: [String: Device] = [:]
        for raw in devicesRaw {
            guard let type = raw["type"] as? String, allowedTypes.contains(type), let name = raw["name"] as? String else { continue }
            let identifiers = raw["identifier"] as? [String] ?? []
            let key = raw["key"] as? String ?? identifiers.first ?? name
            let imageKey = raw["imageKey"] as? String ?? key
            let released = (raw["released"] as? [String]) ?? ((raw["released"] as? String).map { [$0] } ?? [])
            devices[key] = Device(
                name: name, type: type,
                soc: first(raw["soc"]), arch: first(raw["arch"]),
                released: released.sorted().first,
                identifiers: identifiers, models: raw["model"] as? [String] ?? [],
                image: imageIndex[imageKey].map { "\(imageKey)/\($0)" },
                group: (raw["group"] as? Bool) != false
            )
        }

        var groups: [DeviceGroup] = []
        var grouped = Set<String>()
        for raw in groupsRaw {
            guard let type = raw["type"] as? String, allowedTypes.contains(type), let name = raw["name"] as? String else { continue }
            let all = raw["devices"] as? [String] ?? []
            let keys = all.filter { devices[$0] != nil }
            guard !keys.isEmpty else { continue }
            grouped.formUnion(all)
            groups.append(DeviceGroup(name: name, type: type, devices: keys))
        }
        for (key, device) in devices where !grouped.contains(key) && device.group {
            groups.append(DeviceGroup(name: device.name, type: device.type, devices: [key]))
        }

        var firmwares: [Firmware] = []
        for raw in iosRaw + tvRaw {
            guard let osStr = raw["osStr"] as? String, allowedOS.contains(osStr),
                  let version = raw["version"] as? String, let build = raw["build"] as? String else { continue }
            if raw["internal"] as? Bool == true || raw["sdk"] as? Bool == true || raw["beta"] as? Bool == true || raw["rc"] as? Bool == true { continue }
            let map = (raw["deviceMap"] as? [String] ?? []).filter { devices[$0] != nil }
            guard !map.isEmpty else { continue }
            let signed: SignedState
            if raw["signed"] as? Bool == true { signed = .all }
            else { signed = .devices((raw["signed"] as? [String] ?? []).filter { devices[$0] != nil }) }
            firmwares.append(Firmware(osStr: osStr, version: version, build: build,
                                      released: raw["released"] as? String, devices: map, signed: signed))
        }
        firmwares.sort { lhs, rhs in
            let l = VersionSort.key(lhs.version), r = VersionSort.key(rhs.version)
            return l != r ? r.lexicographicallyPrecedes(l) : lhs.build > rhs.build
        }

        let jailbreaks: [Jailbreak] = jailbreaksRaw.compactMap { raw in
            guard let name = raw["name"] as? String else { return nil }
            let info = raw["info"] as? [String: Any] ?? [:]
            let guides: [JailbreakGuide] = (info["guide"] as? [[String: Any]] ?? []).map { g in
                JailbreakGuide(
                    text: g["text"] as? String, name: g["name"] as? String, url: g["url"] as? String,
                    pkgman: g["pkgman"] as? String, firmwares: g["firmwares"] as? [String], devices: g["devices"] as? [String],
                    updateLinks: (g["updateLink"] as? [[String: Any]])?.map { UpdateLink(text: $0["text"] as? String ?? "", link: $0["link"] as? String ?? "") }
                )
            }
            let website = info["website"] as? [String: Any]
            return Jailbreak(
                name: name, priority: raw["priority"] as? Int ?? 9999, hideFromGuide: raw["hideFromGuide"] as? Bool ?? false,
                type: info["type"] as? String, notes: info["notes"] as? String, latestVersion: info["latestVer"] as? String,
                icon: info["icon"] as? String,
                website: (website?["url"] as? String).map { WebLink(name: website?["name"] as? String ?? $0, url: $0) },
                firmwareRange: info["firmwares"] as? [String], guides: guides,
                compatibility: (raw["compatibility"] as? [[String: Any]] ?? []).map {
                    Compatibility(devices: $0["devices"] as? [String] ?? [], firmwares: $0["firmwares"] as? [String] ?? [])
                }
            )
        }

        let bypasses: [BypassApp] = bypassRaw.map { raw in
            BypassApp(
                name: raw["name"] as? String ?? "", bundleId: raw["bundleId"] as? String ?? "",
                uri: raw["uri"] as? String, icon: raw["icon"] as? String, notes: raw["notes"] as? String,
                bypasses: (raw["bypasses"] as? [[String: Any]] ?? []).map {
                    Bypass(name: $0["name"] as? String, guide: $0["guide"] as? String,
                           repository: ($0["repository"] as? [String: Any])?["uri"] as? String,
                           notes: $0["notes"] as? String, appNotes: $0["appNotes"] as? String, version: $0["version"] as? String)
                }
            )
        }

        guard !devices.isEmpty, !firmwares.isEmpty, !jailbreaks.isEmpty else { throw RefreshError.badResponse("AppleDB data") }
        return CFWData(generated: ISO8601DateFormatter().string(from: Date()), devices: devices, groups: groups,
                       firmwares: firmwares, jailbreaks: jailbreaks, bypasses: bypasses)
    }

    private static func first(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        return (value as? [String])?.first
    }

    // MARK: Guide pages

    static func downloadGuide(known: [String], progress: @escaping Progress) async throws -> GuideBundle {
        var queue = ["/", "/site-navigation/"] + known
        var seen = Set<String>()
        var pages: [GuidePage] = []
        var navigationHTML: String?
        let required = Set(known + ["/", "/site-navigation/"])
        var failures: [String] = []

        while !queue.isEmpty, seen.count < 500 {
            var batch: [String] = []
            while let next = queue.first, batch.count < 8 {
                queue.removeFirst()
                if seen.insert(next).inserted { batch.append(next) }
            }
            if batch.isEmpty { continue }
            let results = await withTaskGroup(of: (String, String?).self) { group in
                for path in batch {
                    group.addTask {
                        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
                        guard let data = try? await fetch(site + encoded) else { return (path, nil) }
                        return (path, String(decoding: data, as: UTF8.self))
                    }
                }
                var collected: [(String, String?)] = []
                for await item in group { collected.append(item) }
                return collected
            }
            for (path, body) in results {
                guard let body else { if required.contains(path) { failures.append(path) }; continue }
                if path == "/site-navigation/" { navigationHTML = body }
                if !path.hasPrefix("/get-started"), let page = PageExtractor.extract(body, path: path) { pages.append(page) }
                for link in PageExtractor.internalLinks(in: body) where !seen.contains(link) && !queue.contains(link) {
                    queue.append(link)
                }
            }
            progress("Downloaded \(pages.count) guide pages…")
        }

        guard failures.isEmpty, required.isSubset(of: Set(pages.map(\.path))), queue.isEmpty else { throw URLError(.cannotParseResponse) }
        guard pages.count > 50 else { throw RefreshError.badResponse("guide pages") }
        let sections = navigationHTML.map { PageExtractor.sections(from: $0) } ?? []
        await AssetCache.prefetch(pages: pages)
        return GuideBundle(generated: ISO8601DateFormatter().string(from: Date()),
                           pages: pages.sorted { $0.path < $1.path }, sections: sections)
    }
}

/// Pulls the article body out of a rendered ios.cfw.guide page.
enum PageExtractor {
    private static func replace(_ text: String, _ pattern: String, with template: String = "", options: NSRegularExpression.Options = []) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return text }
        return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    private static func firstMatch(_ text: String, _ pattern: String, group: Int = 1) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: group), in: text) else { return nil }
        return String(text[range])
    }

    static func decodeEntities(_ text: String) -> String {
        var value = text
        let map = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&nbsp;": " "]
        for (entity, char) in map { value = value.replacingOccurrences(of: entity, with: char) }
        return value
    }

    static func plainText(_ html: String) -> String {
        let stripped = replace(html, "<[^>]+>", with: " ")
        return decodeEntities(replace(stripped, "\\s+", with: " ")).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func extract(_ html: String, path: String) -> GuidePage? {
        guard let open = html.range(of: "<div class=\"theme-default-content\"[^>]*>", options: .regularExpression) else { return nil }
        let rest = html[open.upperBound...]
        let end = rest.range(of: "<footer class=\"page-meta\"")?.lowerBound ?? rest.range(of: "</main>")?.lowerBound ?? rest.endIndex
        var content = String(rest[..<end])
        let navArea = String(rest[end...].prefix(4000))

        content = replace(content, "<!--.*?-->", options: .dotMatchesLineSeparators)
        content = replace(content, "<svg.*?</svg>", options: .dotMatchesLineSeparators)
        content = replace(content, "<span class=\"external-link-icon-sr-only\">.*?</span>")
        content = replace(content, "<span>\\s*</span>")
        content = replace(content, "<div id=\"waldo-tag-\\d+\"[^>]*></div>")
        content = replace(content, "<a class=\"header-anchor\"[^>]*>#</a>\\s*")
        content = replace(content, "\\sdata-v-[0-9a-f]+(=\"[^\"]*\")?")
        content = content.replacingOccurrences(of: "src=\"/assets/", with: "src=\"cfwasset:///assets/")

        var title = firstMatch(content, "<h1[^>]*>(.*?)</h1>").map { decodeEntities(replace($0, "<[^>]+>")).trimmingCharacters(in: .whitespaces) } ?? ""
        content = replace(content, "<h1[^>]*>.*?</h1>", options: .dotMatchesLineSeparators)
        content = replace(content, "<div class=\"custom-container (none|tip)\">(<p class=\"custom-container-title\">TIP</p>)?<p>(<p>)?For support in English.*?</p>\\s*(</p>)?</div>", options: .dotMatchesLineSeparators)
        if title.isEmpty { title = path == "/" ? "Home" : path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).replacingOccurrences(of: "-", with: " ").capitalized }

        func navLink(_ kind: String) -> PageLink? {
            guard let href = firstMatch(navArea, "<span class=\"\(kind)\"><a href=\"([^\"]+)\""),
                  let label = firstMatch(navArea, "<span class=\"\(kind)\"><a href=\"[^\"]+\"[^>]*aria-label=\"([^\"]*)\"") else { return nil }
            return PageLink(path: href, title: decodeEntities(label))
        }
        let description = firstMatch(html, "<meta name=\"description\" content=\"([^\"]*)\"").map(decodeEntities) ?? ""
        let text = String(plainText(content).prefix(20000))
        return GuidePage(path: path, title: title, html: content.trimmingCharacters(in: .whitespacesAndNewlines),
                         text: text, description: description, prev: navLink("prev"), next: navLink("next"))
    }

    static func internalLinks(in html: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "href=\"(/[^\"#?]*)") else { return [] }
        var links: [String] = []
        for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let range = Range(match.range(at: 1), in: html) else { continue }
            var link = String(html[range])
            if link.hasPrefix("//") || link.hasPrefix("/assets") || link.hasPrefix("/cdn-cgi") { continue }
            if link.range(of: "^/[a-z]{2}_[A-Z]{2}/", options: .regularExpression) != nil { continue }
            if link.range(of: "\\.(png|jpe?g|svg|gif|webp|ico|css|js|json|xml|zip|ipa|deb|pdf|mobileconfig)$", options: [.regularExpression, .caseInsensitive]) != nil { continue }
            if !link.hasSuffix("/") && !link.hasSuffix(".html") { link += "/" }
            links.append(link.removingPercentEncoding ?? link)
        }
        return links
    }

    static func sections(from html: String) -> [GuideSection] {
        guard let regex = try? NSRegularExpression(pattern: "<h2 id=\"[^\"]+\"[^>]*>(.*?)</h2>\\s*<ul>(.*?)</ul>", options: .dotMatchesLineSeparators),
              let linkRegex = try? NSRegularExpression(pattern: "<a href=\"(/[^\"]*)\"[^>]*>(.*?)</a>") else { return [] }
        return regex.matches(in: html, range: NSRange(html.startIndex..., in: html)).compactMap { match in
            guard let titleRange = Range(match.range(at: 1), in: html), let listRange = Range(match.range(at: 2), in: html) else { return nil }
            let title = plainText(String(html[titleRange])).replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces)
            let list = String(html[listRange])
            let links: [PageLink] = linkRegex.matches(in: list, range: NSRange(list.startIndex..., in: list)).compactMap { link in
                guard let p = Range(link.range(at: 1), in: list), let n = Range(link.range(at: 2), in: list) else { return nil }
                var path = String(list[p])
                if !path.hasSuffix("/") && !path.hasSuffix(".html") { path += "/" }
                return PageLink(path: path, title: plainText(String(list[n])))
            }
            return links.isEmpty ? nil : GuideSection(title: title, links: links)
        }
    }
}
