import SwiftUI

@main
struct CFWGuideApp: App {
    @StateObject private var store = ContentStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
        }
    }
}

enum Route: Hashable {
    case page(String)
    case deviceType(String)
    case group(String)
    case jailbreak(String)
    case getStarted
    case myDevice
    case signed
    case bypass
    case bookmarks
}

/// One navigation stack per tab; pages push onto whichever tab opened them.
@MainActor
final class Router: ObservableObject {
    @Published var path: [Route] = []

    func open(_ route: Route) { path.append(route) }

    /// Turns a link inside a guide page into the matching native screen.
    func openLink(_ link: String) {
        let clean = ContentStore.normalize(link)
        if clean == "/get-started/" {
            open(.getStarted)
        } else if clean.hasPrefix("/get-started/select-") {
            let slug = clean.replacingOccurrences(of: "/get-started/select-", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let type = CompatibilityEngine.typeOrder.first { $0.lowercased().replacingOccurrences(of: " ", with: "-") == slug }
            open(type.map(Route.deviceType) ?? .getStarted)
        } else {
            open(.page(link))
        }
    }
}

enum AppTab: Hashable { case start, guides, jailbreaks, tools, more }

struct RootView: View {
    @State private var tab: AppTab = .start

    var body: some View {
        TabView(selection: $tab) {
            TabStack { GetStartedView() }
                .tabItem { Label("Get Started", systemImage: "iphone.gen3") }
                .tag(AppTab.start)
            TabStack { GuidesView() }
                .tabItem { Label("Guides", systemImage: "book") }
                .tag(AppTab.guides)
            TabStack { JailbreakListView() }
                .tabItem { Label("Jailbreaks", systemImage: "lock.open") }
                .tag(AppTab.jailbreaks)
            TabStack { ToolsView() }
                .tabItem { Label("Tools", systemImage: "wrench.and.screwdriver") }
                .tag(AppTab.tools)
            TabStack { MoreView() }
                .tabItem { Label("More", systemImage: "ellipsis.circle") }
                .tag(AppTab.more)
        }
    }
}

struct TabStack<Content: View>: View {
    @StateObject private var router = Router()
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        NavigationStack(path: $router.path) {
            content
                .navigationDestination(for: Route.self) { route in
                    destination(route)
                }
        }
        .environmentObject(router)
    }

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case .page(let path): ReaderView(path: path)
        case .deviceType(let type): DeviceTypeView(type: type)
        case .group(let id): GroupChartView(groupID: id)
        case .jailbreak(let name): JailbreakDetailView(name: name)
        case .getStarted: GetStartedView()
        case .myDevice: MyDeviceView()
        case .signed: SignedFirmwareView()
        case .bypass: BypassListView()
        case .bookmarks: BookmarksView()
        }
    }
}
