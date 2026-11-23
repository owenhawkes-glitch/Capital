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
                                    .overlay(Image(systemName: theme.symbol).font(.system(size: 13)).foregroundStyle(.white.opacity(0.85)))
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(look.theme == theme ? Color.accentColor : Color.clear, lineWidth: 2))
                                Text(theme.name).font(.caption)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                if look.theme == .custom {
                    HStack {
                        Text("Custom colours")
                        ForEach(0..<3, id: \.self) { i in
                            ColorPicker("", selection: hexColorBinding(Binding(
                                get: { look.customHexes[i] },
                                set: { var h = look.customHexes; h[i] = $0; look.customHexes = h })), supportsOpacity: false)
                                .labelsHidden()
                        }
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
                Picker("Open style", selection: $look.openStyle) {
                    ForEach(OpenStyle.allCases) { Text($0.name).tag($0) }
                }
                .pickerStyle(.segmented)
                HStack {
                    Text("Speed")
                    Slider(value: $look.animationSpeed, in: 0.5...2, step: 0.25) {
                        EmptyView()
                    } minimumValueLabel: { Text("Slow").font(.caption) } maximumValueLabel: { Text("Fast").font(.caption) }
                    Text(String(format: "%.2g×", look.animationSpeed)).monospacedDigit().frame(width: 36)
                }
                Text("Speed applies to opening and closing, the theme's movement and the glow.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Animated icons (music bars while playing, weather, chats, clipboard, notch icon)", isOn: $look.animatedIcons)
                Text("Icons stay still when \"Reduce motion\" is on in macOS Accessibility settings.")
                    .font(.caption).foregroundStyle(.secondary)
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
                Toggle("Match the theme (its own icon, colours and movement)", isOn: $look.logoFollowsTheme)
                Picker("Icon animation", selection: $look.logoAnimation) {
                    ForEach(IconAnimation.allCases) { Text($0.name).tag($0) }
                }
                .disabled(look.logoFollowsTheme)
                HStack(spacing: 16) {
                    Text("Preview").font(.caption).foregroundStyle(.secondary)
                    Group {
                        if look.logoFollowsTheme {
                            Image(systemName: look.effectiveLogoSymbol)
                                .font(.system(size: 22))
                                .modifier(ThemeGradientFill())
                        } else {
                            Image(systemName: look.logoSymbol)
                                .font(.system(size: 22))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .animatedSymbol(look.effectiveLogoAnimation)
                    .id(look.effectiveLogoAnimation.rawValue + look.effectiveLogoSymbol)
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
    @EnvironmentObject private var state: AppState
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
                    HStack {
                        Toggle("Show in the closed notch", isOn: Binding(
                            get: { state.notchItemEnabled(.clock(clock.id)) },
                            set: { state.setNotchItem(.clock(clock.id), enabled: $0) }))
                            .toggleStyle(.checkbox)
                        Picker("Notch style", selection: $clock.notchStyle) {
                            Text("Same as panel").tag(ClockStyle?.none)
                            ForEach(ClockStyle.allCases) { Text($0.name).tag(Optional($0)) }
                        }
                        .frame(width: 260)
                        Spacer()
                        ClockFace(clock: clock.forNotch, size: 16).frame(minWidth: 40)
                    }
                    .font(.caption)
                    .padding(.leading, 4)
                }
                Menu("Add clock") {
                    Button("Local time") { clocks.add(label: "", zone: TimeZone.current.identifier, style: .analog) }
                    Divider()
                    ForEach(ClockStore.worldPresets, id: \.1) { preset in
                        Button(preset.0) { clocks.add(label: preset.0, zone: preset.1) }
                    }
                }
                .fixedSize()
                Text("Each clock can show in the panel and in the closed notch, in different styles (e.g. a flip clock in the notch). Position and colour it in Notch items.").font(.caption).foregroundStyle(.secondary)
            }

            Section("Weather") {
                HStack {
                    TextField("City", text: $cityDraft, prompt: Text(weather.city))
                        .onSubmit { if !cityDraft.isEmpty { weather.city = cityDraft } }
                    Button("Set") { if !cityDraft.isEmpty { weather.city = cityDraft } }
                    Toggle("°F", isOn: $weather.fahrenheit).toggleStyle(.checkbox)
                }
                Toggle("Show in the closed notch (icon and temperature)", isOn: Binding(
                    get: { state.notchItemEnabled(.weather) },
                    set: { state.setNotchItem(.weather, enabled: $0) }))
                Text(weather.error ?? "Showing \(weather.resolvedName.isEmpty ? weather.city : weather.resolvedName). From Open-Meteo, no account or location permission needed.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Markets") {
                HStack {
                    Text("Rising")
                    ColorPicker("", selection: hexColorBinding($markets.upHex), supportsOpacity: false).labelsHidden()
                    Text("Falling")
                    ColorPicker("", selection: hexColorBinding($markets.downHex), supportsOpacity: false).labelsHidden()
                    Button("Swap") { swap(&markets.upHex, &markets.downHex) }
                    Spacer()
                    Toggle("Show TradingView's live widget in the Markets card", isOn: $markets.useTradingViewWidget)
                }
                ForEach($markets.tickers) { $ticker in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            ColorPicker("", selection: hexColorBinding(Binding(
                                get: { ticker.colorHex ?? "#E6E6E6" }, set: { ticker.colorHex = $0 })), supportsOpacity: false)
                                .labelsHidden()
                            Picker("", selection: Binding(get: { ticker.colorHex ?? "" }, set: { ticker.colorHex = $0.isEmpty ? nil : $0 })) {
                                Text("Item colour").tag("")
                                Text("Match notch glow").tag(NotchItem.glowColor)
                                if let hex = ticker.colorHex, hex != NotchItem.glowColor { Text("Custom").tag(hex) }
                            }
                            .labelsHidden().frame(width: 140)
                            TextField("Name", text: $ticker.name).frame(width: 90)
                            TextField("Yahoo symbol", text: $ticker.symbol).frame(width: 100)
                            TextField("TradingView symbol", text: $ticker.tradingView, prompt: Text(ticker.tradingViewSymbol))
                                .help("The symbol used for TradingView links and the TradingView widget, e.g. FX:EURUSD, OANDA:XAUUSD, BINANCE:BTCUSDT")
                            Text(markets.quotes[ticker.symbol].map { MarketStore.format($0.price) } ?? "–")
                                .monospacedDigit().frame(width: 70, alignment: .trailing)
                            Button { markets.tickers.removeAll { $0.id == ticker.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain)
                        }
                        HStack {
                            Picker("In the notch", selection: Binding(get: { ticker.display ?? .price }, set: { ticker.display = $0 })) {
                                ForEach(TickerDisplay.allCases) { Text($0.name).tag($0) }
                            }
                            .frame(width: 270)
                            Toggle("Position", isOn: Binding(
                                get: { ticker.position != nil },
                                set: { ticker.position = $0 ? Ticker.Position(entry: markets.quotes[ticker.symbol]?.price ?? 0) : nil }))
                                .toggleStyle(.checkbox)
                            if ticker.position != nil {
                                Picker("", selection: Binding(get: { ticker.position?.long ?? true }, set: { ticker.position?.long = $0 })) {
                                    Text("Long").tag(true)
                                    Text("Short").tag(false)
                                }
                                .pickerStyle(.segmented).labelsHidden().frame(width: 110)
                                TextField("Entry", value: Binding(get: { ticker.position?.entry ?? 0 }, set: { ticker.position?.entry = $0 }),
                                          format: .number.precision(.fractionLength(0...5)))
                                    .frame(width: 80)
                                TextField("Size", value: Binding(get: { ticker.position?.size ?? 0 }, set: { ticker.position?.size = $0 }),
                                          format: .number)
                                    .frame(width: 90)
                                    .help("Units, e.g. 100000 for one standard FX lot")
                                if let q = markets.quotes[ticker.symbol], let pl = ticker.profit(at: q.price) {
                                    Text(MarketStore.formatProfit(pl, currency: ticker.quoteCurrency))
                                        .monospacedDigit()
                                        .foregroundStyle(pl >= 0 ? markets.upColor : markets.downColor)
                                }
                            }
                            Spacer()
                        }
                        .font(.caption)
                    }
                    .padding(.vertical, 2)
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
                Text("Built-in prices come from Yahoo Finance (EURUSD=X, GC=F, ^GSPC, AAPL, BTC-USD), refreshed every minute and delayed for some markets. TradingView doesn't sell its prices to other apps, but its free widget can show its live quotes in the Markets card using each ticker's TradingView symbol. P/L is in the pair's quote currency (e.g. USD for EUR/USD).")
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
                Text("Turn on \"Live window\" in Panel layout, then click Spotify, Parsec or Other… in that section and pick the window in macOS's picker. Using the system picker means DuoNotch needs no Screen Recording permission and only ever sees the window you picked. macOS forgets the pick when DuoNotch quits, so you pick again after a restart.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
