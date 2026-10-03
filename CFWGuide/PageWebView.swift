import CryptoKit
import SafariServices
import SwiftUI
import WebKit

/// Serves guide images offline: refreshed cache first, then the bundled copy, then the live site.
enum AssetCache {
    static var directory: URL {
        let url = ContentStore.cacheDirectory.appendingPathComponent("SiteAssets", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func safePath(_ path: String) -> String? {
        guard let decoded = path.removingPercentEncoding else { return nil }
        let clean = decoded.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let components = clean.split(separator: "/", omittingEmptySubsequences: false)
        guard clean.hasPrefix("assets/"), !clean.contains("\\"),
              !components.contains(where: { $0 == ".." || $0 == "." || $0.isEmpty }),
              ["png", "jpg", "jpeg", "gif", "svg", "webp"].contains((clean as NSString).pathExtension.lowercased()) else { return nil }
        return clean
    }

    static func localFile(for path: String) -> URL? {
        guard let clean = safePath(path) else { return nil }
        let cached = directory.appendingPathComponent(clean)
        if FileManager.default.fileExists(atPath: cached.path) { return cached }
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("SiteAssets").appendingPathComponent(clean),
           FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        return nil
    }

    static func data(for path: String) async -> Data? {
        guard let path = safePath(path) else { return nil }
        if let file = localFile(for: path), let data = try? Data(contentsOf: file) { return data }
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        guard let data = try? await Refresher.fetch(Refresher.site + "/" + encoded.trimmingCharacters(in: CharacterSet(charactersIn: "/"))) else { return nil }
        guard data.count <= 12 * 1024 * 1024 else { return nil }
        let target = directory.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: target, options: .atomic)
        return data
    }

    static func prefetch(pages: [GuidePage]) async {
        guard let regex = try? NSRegularExpression(pattern: "cfwasset:///([^\"]+)") else { return }
        var paths = Set<String>()
        for page in pages {
            for match in regex.matches(in: page.html, range: NSRange(page.html.startIndex..., in: page.html)) {
                if let range = Range(match.range(at: 1), in: page.html) { paths.insert(String(page.html[range])) }
            }
        }
        for path in paths where localFile(for: path) == nil { _ = await data(for: path) }
    }

    static func mimeType(for path: String) -> String {
        switch (path as NSString).pathExtension.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "svg": return "image/svg+xml"
        case "webp": return "image/webp"
        default: return "application/octet-stream"
        }
    }
}

final class AssetSchemeHandler: NSObject, WKURLSchemeHandler {
    private var active = Set<ObjectIdentifier>()

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        let id = ObjectIdentifier(task)
        active.insert(id)
        Task { @MainActor in
            let data = await AssetCache.data(for: url.path)
            guard self.active.contains(id) else { return }
            self.active.remove(id)
            guard let data else {
                task.didFailWithError(URLError(.fileDoesNotExist))
                return
            }
            task.didReceive(URLResponse(url: url, mimeType: AssetCache.mimeType(for: url.path), expectedContentLength: data.count, textEncodingName: nil))
            task.didReceive(data)
            task.didFinish()
        }
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {
        active.remove(ObjectIdentifier(task))
    }
}

/// Renders a guide page and turns its links into in-app navigation.
struct PageWebView: UIViewRepresentable {
    let page: GuidePage
    let textScale: Double
    let onInternalLink: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onInternalLink: onInternalLink) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(AssetSchemeHandler(), forURLScheme: "cfwasset")
        config.dataDetectorTypes = []
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.allowsLinkPreview = false
        load(webView, context: context)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onInternalLink = onInternalLink
        if context.coordinator.loadedKey != key { load(webView, context: context) }
    }

    private var key: String { page.path + "|\(textScale)|" + SHA256.hash(data: Data(page.html.utf8)).map { String(format: "%02x", $0) }.joined() }

    private func load(_ webView: WKWebView, context: Context) {
        context.coordinator.loadedKey = key
        context.coordinator.currentPath = page.path
        let base = URL(string: Refresher.site + (page.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? page.path))
        webView.loadHTMLString(Self.document(for: page, textScale: textScale), baseURL: base)
    }

    static func document(for page: GuidePage, textScale: Double) -> String {
        let nonce = UUID().uuidString
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src cfwasset: https: data:; style-src 'unsafe-inline'; script-src 'nonce-\(nonce)';">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=5">
        <style>\(css(textScale: textScale))</style></head>
        <body><article>\(page.html)</article>
        <script nonce="\(nonce)">\(script)</script></body></html>
        """
    }

    static let script = """
    document.querySelectorAll('.tab-container').forEach(function(c, ci){
      var name = 'tabgroup-' + ci;
      c.querySelectorAll('input[type=radio]').forEach(function(r, ri){
        var oldId = r.id, newId = name + '-' + ri;
        r.name = name; r.id = newId;
        var label = c.querySelector('label[for="' + oldId + '"]');
        if (label) label.setAttribute('for', newId);
      });
      var first = c.querySelector('input[type=radio]'); if (first) first.checked = true;
    });
    document.querySelectorAll('pre').forEach(function(pre){
      var b = document.createElement('button'); b.className = 'copy'; b.textContent = 'Copy';
      b.onclick = function(){ navigator.clipboard.writeText(pre.innerText.replace(/Copy$/, '')).then(function(){ b.textContent = 'Copied'; setTimeout(function(){ b.textContent = 'Copy'; }, 1200); }); };
      pre.style.position = 'relative'; pre.appendChild(b);
    });
    document.querySelectorAll('table').forEach(function(t){
      if (t.parentElement.classList.contains('table-wrap')) return;
      var w = document.createElement('div'); w.className = 'table-wrap'; t.parentNode.insertBefore(w, t); w.appendChild(t);
    });
    """

    static func css(textScale: Double) -> String {
        """
        :root { color-scheme: light dark; --text:#1c1c1e; --muted:#6b6b70; --bg:transparent; --card:#f2f2f7; --line:#d1d1d6;
          --accent:#0a84ff; --tip:#1f9d55; --tipbg:rgba(31,157,85,.10); --warn:#b7791f; --warnbg:rgba(214,158,46,.13);
          --danger:#d64545; --dangerbg:rgba(214,69,69,.11); --code:#ececf1; }
        @media (prefers-color-scheme: dark) { :root { --text:#f2f2f7; --muted:#a1a1a8; --card:#1c1c1e; --line:#38383a;
          --accent:#64a8ff; --tip:#4cd38a; --tipbg:rgba(76,211,138,.12); --warn:#f0c05a; --warnbg:rgba(240,192,90,.12);
          --danger:#ff7a7a; --dangerbg:rgba(255,122,122,.12); --code:#2c2c2e; } }
        html { -webkit-text-size-adjust: \(Int(textScale * 100))%; }
        body { margin:0; padding:4px 18px 40px; font:-apple-system-body; font-family:-apple-system, system-ui; color:var(--text); background:var(--bg); line-height:1.55; word-wrap:break-word; }
        h2 { font-size:1.3em; margin:1.6em 0 .5em; } h3 { font-size:1.1em; margin:1.3em 0 .4em; }
        a { color:var(--accent); text-decoration:none; } p, li { margin:.45em 0; }
        ol, ul { padding-left:1.4em; } li::marker { color:var(--muted); }
        img { max-width:100%; height:auto; border-radius:10px; }
        code { font-family:ui-monospace, Menlo, monospace; font-size:.88em; background:var(--code); padding:.12em .35em; border-radius:6px; }
        pre { background:var(--code); padding:12px 12px 12px 12px; border-radius:12px; overflow-x:auto; }
        pre code { background:none; padding:0; }
        button.copy { position:absolute; top:6px; right:6px; font:600 12px -apple-system; border:0; border-radius:8px; padding:4px 8px; background:var(--accent); color:#fff; }
        .table-wrap { overflow-x:auto; } table { border-collapse:collapse; width:100%; font-size:.92em; }
        th, td { border:1px solid var(--line); padding:6px 8px; text-align:left; vertical-align:top; }
        hr { border:0; border-top:1px solid var(--line); }
        .custom-container { border-radius:12px; padding:10px 14px; margin:1em 0; border-left:4px solid var(--line); background:var(--card); }
        .custom-container.none { border:0; }
        .custom-container.tip { border-color:var(--tip); background:var(--tipbg); }
        .custom-container.warning { border-color:var(--warn); background:var(--warnbg); }
        .custom-container.danger { border-color:var(--danger); background:var(--dangerbg); }
        .custom-container-title { font-weight:700; font-size:.8em; letter-spacing:.06em; margin:0 0 .3em; }
        .tip .custom-container-title { color:var(--tip); } .warning .custom-container-title { color:var(--warn); } .danger .custom-container-title { color:var(--danger); }
        details.custom-container { border-left-color:var(--accent); }
        details summary { font-weight:600; cursor:pointer; }
        .tab-container { margin:1em 0; display:flex; flex-wrap:wrap; gap:6px; }
        .tab-container > section { display:contents; }
        .tab-container input[type=radio] { display:none; }
        .tab-container label.tab-link { order:0; padding:6px 12px; border-radius:16px; background:var(--card); font-weight:600; font-size:.9em; }
        .tab-container .tab { order:1; display:none; width:100%; }
        .tab-container input:checked + label.tab-link { background:var(--accent); color:#fff; }
        .tab-container input:checked + label + .tab { display:block; }
        .credits img, .user img { width:48px; height:48px; border-radius:24px; }
        """
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var onInternalLink: (String) -> Void
        var loadedKey = ""
        var currentPath = ""

        init(onInternalLink: @escaping (String) -> Void) { self.onInternalLink = onInternalLink }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard action.navigationType == .linkActivated, let url = action.request.url else {
                return .allow
            }
            if url.host == "ios.cfw.guide" {
                let samePage = ContentStore.normalize(url.path) == ContentStore.normalize(currentPath)
                if samePage, let fragment = url.fragment {
                    if let encoded = try? JSONEncoder().encode(fragment), let argument = String(data: encoded, encoding: .utf8) {
                        _ = try? await webView.evaluateJavaScript("var e=document.getElementById(\(argument));if(e){e.scrollIntoView({behavior:'smooth'});}")
                    }
                } else {
                    onInternalLink(url.path + (url.fragment.map { "#" + $0 } ?? ""))
                }
            } else if ["http", "https"].contains(url.scheme ?? "") {
                ExternalLink.open(url)
            } else {
                await UIApplication.shared.open(url)
            }
            return .cancel
        }
    }
}

enum ExternalLink {
    @MainActor
    static func open(_ url: URL) {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              var top = scene.windows.first(where: \.isKeyWindow)?.rootViewController else {
            UIApplication.shared.open(url)
            return
        }
        while let presented = top.presentedViewController { top = presented }
        top.present(SFSafariViewController(url: url), animated: true)
    }
}
