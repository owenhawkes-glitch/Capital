import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Settings → Appearance: theme, glow, animation and the notch icon.
struct AppearanceSettings: View {
    @ObservedObject private var look = AppearanceStore.shared

    var body: some View {
        Form {
            Section("Theme") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                    ForEach(NotchTheme.allCases) { theme in
                        Button { look.theme = theme } label: {
                            VStack(spacing: 4) {
                                ThemeSwatch(theme: theme)
                                    .frame(height: 34)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(look.theme == theme ? Color.accentColor : Color.clear, lineWidth: 2))
                                Text(theme.name).font(.caption)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                Toggle("Keep the closed notch black; use the theme only when it opens", isOn: $look.blackWhenClosed)
                Toggle("Glowing edge that slowly travels around the notch", isOn: $look.glowBorder)
            }
            Section("Animation") {
                Picker("Open and close", selection: $look.openAnimation) {
                    ForEach(OpenAnimation.allCases) { Text($0.name).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section("Notch icon") {
                Text("Show it by switching on \"Notch icon\" in Settings → Notch, and colour it there.")
                    .font(.caption).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 34), spacing: 8)], spacing: 8) {
                    ForEach(AppearanceStore.logoChoices, id: \.self) { symbol in
                        Button {
                            look.logoSymbol = symbol
                            look.logoImagePath = nil
                        } label: {
                            Image(systemName: symbol)
                                .font(.system(size: 16))
                                .frame(width: 32, height: 32)
                                .background(RoundedRectangle(cornerRadius: 6)
                                    .fill(look.logoSymbol == symbol && look.logoImagePath == nil ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.1)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack {
                    Button("Use an image…") { chooseImage() }
                    if look.logoImagePath != nil {
                        Text((look.logoImagePath! as NSString).lastPathComponent).font(.caption)
                        Button("Remove") { look.logoImagePath = nil }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.prompt = "Use"
        if panel.runModal() == .OK, let url = panel.url { look.logoImagePath = url.path }
    }
}

/// A still preview of a theme.
private struct ThemeSwatch: View {
    let theme: NotchTheme
    var body: some View {
        if theme == .black {
            Color.black
        } else if #available(macOS 15.0, *) {
            MeshGradient(width: 3, height: 3, points: [[0, 0], [0.5, 0], [1, 0], [0, 0.5], [0.55, 0.45], [1, 0.5], [0, 1], [0.5, 1], [1, 1]],
                         colors: theme.colors)
        } else {
            LinearGradient(colors: Array(theme.colors[3...5]), startPoint: .leading, endPoint: .trailing)
        }
    }
}

/// Settings → Widgets: clocks, weather, markets, links and the live window.
struct WidgetsSettings: View {
    @ObservedObject private var clocks = ClockStore.shared
    @ObservedObject private var weather = WeatherStore.shared
    @ObservedObject private var markets = MarketStore.shared
    @ObservedObject private var links = LinkStore.shared
    @ObservedObject private var mirror = WindowMirror.shared
    @State private var cityDraft = ""
    @State private var newTicker = Ticker(name: "", symbol: "")
    @State private var newLink = QuickLink(title: "", url: "")

    var body: some View {
        Form {
            Section("Clocks") {
                ForEach($clocks.clocks) { $clock in
                    HStack {
                        TextField("Label", text: $clock.label).frame(width: 110)
                        Picker("", selection: $clock.timeZoneID) {
                            Text("Local (\(TimeZone.current.identifier))").tag(TimeZone.current.identifier)
                            ForEach(ClockStore.worldPresets, id: \.1) { Text($0.0).tag($0.1) }
                            if !ClockStore.worldPresets.contains(where: { $0.1 == clock.timeZoneID }) && clock.timeZoneID != TimeZone.current.identifier {
                                Text(clock.timeZoneID).tag(clock.timeZoneID)
                            }
                        }
                        .labelsHidden().frame(width: 170)
                        Picker("", selection: $clock.style) {
                            ForEach(ClockStyle.allCases) { Text($0.name).tag($0) }
                        }
                        .labelsHidden().frame(width: 160)
                        Toggle("Seconds", isOn: $clock.showSeconds).toggleStyle(.checkbox)
                        Spacer()
                        ClockFace(clock: clock, size: 18).frame(minWidth: 40)
                        Button { clocks.remove(clock) } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain)
                    }
                }
                Menu("Add clock") {
                    Button("Local time") { clocks.add(label: "", zone: TimeZone.current.identifier, style: .analog) }
                    Divider()
                    ForEach(ClockStore.worldPresets, id: \.1) { preset in
                        Button(preset.0) { clocks.add(label: preset.0, zone: preset.1) }
                    }
                }
                .fixedSize()
                Text("Each clock is also a notch item. Switch it on in Settings → Notch.").font(.caption).foregroundStyle(.secondary)
            }

            Section("Weather") {
                HStack {
                    TextField("City", text: $cityDraft, prompt: Text(weather.city))
                        .onSubmit { if !cityDraft.isEmpty { weather.city = cityDraft } }
                    Button("Set") { if !cityDraft.isEmpty { weather.city = cityDraft } }
                    Toggle("°F", isOn: $weather.fahrenheit).toggleStyle(.checkbox)
                }
                Text(weather.error ?? "Showing \(weather.resolvedName.isEmpty ? weather.city : weather.resolvedName). From Open-Meteo, no account or location permission needed.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Markets") {
                ForEach($markets.tickers) { $ticker in
                    HStack {
                        TextField("Name", text: $ticker.name).frame(width: 100)
                        TextField("Symbol", text: $ticker.symbol).frame(width: 110)
                        TextField("TradingView (optional)", text: $ticker.tradingView, prompt: Text(ticker.tradingViewSymbol))
                        Text(markets.quotes[ticker.symbol].map { MarketStore.format($0.price) } ?? "–")
                            .monospacedDigit().frame(width: 70, alignment: .trailing)
                        Button { markets.tickers.removeAll { $0.id == ticker.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain)
                    }
                }
                HStack {
                    TextField("Name", text: $newTicker.name).frame(width: 100)
                    TextField("Symbol e.g. AUDUSD=X, AAPL, ^FTSE", text: $newTicker.symbol)
                    Button("Add") {
                        guard !newTicker.symbol.isEmpty else { return }
                        var t = newTicker
                        if t.name.isEmpty { t.name = t.symbol }
                        t.id = UUID()
                        markets.tickers.append(t)
                        newTicker = Ticker(name: "", symbol: "")
                    }
                    Menu("Presets") {
                        ForEach(MarketStore.presets) { preset in
                            Button(preset.name) {
                                if !markets.tickers.contains(where: { $0.symbol == preset.symbol }) {
                                    var t = preset; t.id = UUID(); markets.tickers.append(t)
                                }
                            }
                        }
                    }
                    .fixedSize()
                }
                Text("Prices from Yahoo Finance's public feed (FX like EURUSD=X, futures like GC=F, indices like ^GSPC, crypto like BTC-USD), refreshed every minute and delayed for some markets. Clicking a ticker opens its TradingView chart.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Quick links") {
                ForEach($links.links) { $link in
                    HStack {
                        TextField("Title", text: $link.title).frame(width: 120)
                        TextField("URL", text: $link.url)
                        Button { links.remove(link) } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain)
                    }
                }
                HStack {
                    TextField("Title", text: $newLink.title).frame(width: 120)
                    TextField("https://…", text: $newLink.url)
                    Button("Add") {
                        guard !newLink.url.isEmpty else { return }
                        var l = newLink
                        if l.title.isEmpty { l.title = l.resolvedURL?.host ?? l.url }
                        l.id = UUID()
                        links.add(l)
                        newLink = QuickLink(title: "", url: "")
                    }
                    Button("Add Google links") { links.addGooglePresets() }
                }
            }

            Section("Live window") {
                HStack {
                    Text("Mirror")
                    Picker("", selection: $mirror.targetBundleID) {
                        Text("Spotify").tag("com.spotify.client")
                        Text("Parsec").tag("tv.parsec.www")
                        ForEach(mirror.candidates.filter { !["com.spotify.client", "tv.parsec.www"].contains($0.bundleID) }) { c in
                            Text(c.appName).tag(c.bundleID)
                        }
                    }
                    .labelsHidden()
                    Button("Refresh list") { Task { await mirror.refreshCandidates() } }
                }
                Text("Turn on \"Live window\" in Settings → Panel. It shows that app's window live, e.g. a Spotify video podcast or a Parsec session, and needs Screen Recording permission. The app's window must be open (it can be behind others, not minimised). Rebuilding DuoNotch can make macOS ask for the permission again.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { await mirror.refreshCandidates() }
    }
}
