import SwiftUI

struct MoreView: View {
    @EnvironmentObject private var store: ContentStore
    @AppStorage("cfw.textScale") private var textScale = 1.0
    @State private var confirmReset = false

    var body: some View {
        List {
            Section {
                LabeledContent("Saved copy from", value: store.lastUpdatedText)
                LabeledContent("Guide pages", value: "\(store.guide.pages.count)")
                LabeledContent("Firmware versions", value: "\(store.data.firmwares.count)")
                Button {
                    Task { await store.refresh() }
                } label: {
                    HStack {
                        Label("Refresh from ios.cfw.guide", systemImage: "arrow.clockwise")
                        if case .running = store.refreshState { Spacer(); ProgressView() }
                    }
                }
                .disabled({ if case .running = store.refreshState { return true }; return false }())
                switch store.refreshState {
                case .idle: EmptyView()
                case .running(let message): Text(message).font(.caption).foregroundStyle(.secondary)
                case .finished(let message): Label(message, systemImage: "checkmark.circle").font(.caption).foregroundStyle(.green)
                case .failed(let message): Label(message, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                }
                Button("Restore the copy that shipped with the app", role: .destructive) { confirmReset = true }
            } header: {
                Text("Content")
            } footer: {
                Text("Everything works offline. Refreshing downloads about 30 MB from ios.cfw.guide and AppleDB, so use Wi-Fi.")
            }

            Section("Reading") {
                NavigationLink(value: Route.bookmarks) { Label("Bookmarks and history", systemImage: "bookmark") }
                VStack(alignment: .leading) {
                    Text("Guide text size: \(Int(textScale * 100))%")
                    Slider(value: $textScale, in: 0.8...1.6, step: 0.1)
                }
            }

            Section("Get help") {
                Button { ExternalLink.open(URL(string: "https://discord.gg/jb")!) } label: {
                    Label("r/Jailbreak Discord (English support)", systemImage: "bubble.left.and.bubble.right")
                }
                NavigationLink(value: Route.page("/troubleshooting/")) { Label("Troubleshooting", systemImage: "stethoscope") }
                NavigationLink(value: Route.page("/faq/")) { Label("FAQ", systemImage: "questionmark.circle") }
            }

            Section("ios.cfw.guide") {
                NavigationLink(value: Route.page("/credits/")) { Label("Credits", systemImage: "person.3") }
                NavigationLink(value: Route.page("/donations/")) { Label("Donations", systemImage: "heart") }
                Button { ExternalLink.open(URL(string: "https://ios.cfw.guide")!) } label: { Label("Open the website", systemImage: "safari") }
            }

            Section {
                NavigationLink { AboutView() } label: { Label("About and licenses", systemImage: "info.circle") }
            } footer: {
                Text("CFW Guide is an unofficial reader for ios.cfw.guide. It isn't affiliated with Apple or the guide's authors. Jailbreaking is at your own risk.")
            }
        }
        .navigationTitle("More")
        .confirmationDialog("Restore the bundled copy?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Restore", role: .destructive) { store.resetToBundled() }
        } message: {
            Text("This removes refreshed pages and data. Bookmarks are kept.")
        }
    }
}

struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("CFW Guide \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
                    .font(.title2.weight(.bold))
                Text("This app packages the content of ios.cfw.guide for offline reading, and rebuilds its device and version charts natively from AppleDB data.")
                Text("Sources").font(.headline)
                Text("• Guide text and images: ios.cfw.guide by the cfw-guide contributors (github.com/cfw-guide/ios.cfw.guide), MIT License.\n• Device, firmware, jailbreak and bypass data: AppleDB by littlebyteorg (github.com/littlebyteorg/appledb), MIT License.\n• Device images: img.appledb.dev.")
                Text("MIT License").font(.headline)
                Text(Self.mit).font(.caption.monospaced())
            }
            .padding()
        }
        .navigationTitle("About")
    }

    static let mit = """
    Copyright (c) 2021 Emma (ios.cfw.guide)
    Copyright (c) 2022 emiyl (AppleDB)

    Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
    """
}
