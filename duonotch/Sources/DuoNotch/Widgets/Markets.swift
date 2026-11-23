import SwiftUI
import Combine

/// A market symbol. Prices come from Yahoo Finance's public chart feed;
/// clicking opens the TradingView chart.
enum TickerDisplay: String, Codable, CaseIterable, Identifiable {
    case price, change, priceAndChange, profit
    var id: String { rawValue }
    var name: String {
        switch self {
        case .price: return "Price"
        case .change: return "% change"
        case .priceAndChange: return "Price and % change"
        case .profit: return "P/L of my position"
        }
    }
}

struct Ticker: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    /// Yahoo-style symbol: EURUSD=X, GBPUSD=X, GC=F, ^GSPC, AAPL, BTC-USD.
    var symbol: String
    /// TradingView symbol, e.g. FX:EURUSD. Empty = worked out from `symbol`.
    var tradingView: String = ""
    /// Name colour; nil = the notch item's colour.
    var colorHex: String?
    /// What the closed notch shows for this ticker.
    var display: TickerDisplay?
    /// An open position, for live P/L.
    var position: Position?

    struct Position: Codable, Equatable {
        var long: Bool = true
        var entry: Double = 0
        var size: Double = 0
    }

    /// Quote currency for P/L (FX pairs only; otherwise empty).
    var quoteCurrency: String {
        let s = symbol.uppercased()
        if s.hasSuffix("=X") {
            let pair = s.replacingOccurrences(of: "=X", with: "")
            return pair.count == 6 ? String(pair.suffix(3)) : ""
        }
        if s.hasSuffix("-USD") { return "USD" }
        return ""
    }

    func profit(at price: Double) -> Double? {
        guard let p = position, p.size != 0, p.entry != 0 else { return nil }
        return (price - p.entry) * p.size * (p.long ? 1 : -1)
    }

    var tradingViewSymbol: String {
        if !tradingView.isEmpty { return tradingView }
        let s = symbol.uppercased()
        if s.hasSuffix("=X") { return "FX:" + s.replacingOccurrences(of: "=X", with: "") }
        if s.hasSuffix("-USD") { return "COINBASE:" + s.replacingOccurrences(of: "-", with: "") }
        switch s {
        case "^GSPC": return "SP:SPX"
        case "^IXIC": return "NASDAQ:IXIC"
        case "^DJI": return "DJ:DJI"
        case "^FTSE": return "FTSE:UKX"
        case "GC=F": return "COMEX:GC1!"
        case "CL=F": return "NYMEX:CL1!"
        default: return s
        }
    }
}

@MainActor
final class MarketStore: ObservableObject {
    static let shared = MarketStore()

    struct Quote: Equatable {
        var price: Double
        var previousClose: Double
        var closes: [Double]
        var change: Double { previousClose == 0 ? 0 : (price - previousClose) / previousClose * 100 }
    }

    @Published var tickers: [Ticker] {
        didSet {
            if let data = try? JSONEncoder().encode(tickers) { UserDefaults.standard.set(data, forKey: "tickers.v1") }
            Task { await refresh() }
        }
    }
    @Published private(set) var quotes: [String: Quote] = [:]
    /// Colours for rising and falling prices.
    @Published var upHex: String = UserDefaults.standard.string(forKey: "markets.up") ?? "#3FD08A" {
        didSet { UserDefaults.standard.set(upHex, forKey: "markets.up") }
    }
    @Published var downHex: String = UserDefaults.standard.string(forKey: "markets.down") ?? "#FF5A5F" {
        didSet { UserDefaults.standard.set(downHex, forKey: "markets.down") }
    }
    /// Show TradingView's own live widget in the Markets card.
    @Published var useTradingViewWidget: Bool = UserDefaults.standard.bool(forKey: "markets.tvWidget") {
        didSet { UserDefaults.standard.set(useTradingViewWidget, forKey: "markets.tvWidget") }
    }

    var upColor: Color { Color(hex: upHex) }
    var downColor: Color { Color(hex: downHex) }
    @Published private(set) var updatedAt: Date?

    static let presets: [Ticker] = [
        Ticker(name: "EUR/USD", symbol: "EURUSD=X"),
        Ticker(name: "GBP/USD", symbol: "GBPUSD=X"),
        Ticker(name: "USD/JPY", symbol: "USDJPY=X"),
        Ticker(name: "Gold", symbol: "GC=F"),
        Ticker(name: "S&P 500", symbol: "^GSPC"),
        Ticker(name: "Nasdaq", symbol: "^IXIC"),
        Ticker(name: "Bitcoin", symbol: "BTC-USD"),
    ]

    private var timer: Timer?

    private init() {
        if let data = UserDefaults.standard.data(forKey: "tickers.v1"),
           let decoded = try? JSONDecoder().decode([Ticker].self, from: data) {
            tickers = decoded
        } else {
            tickers = Array(Self.presets.prefix(4))
        }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in await MarketStore.shared.refresh() }
        }
        Task { await refresh() }
    }

    func move(dragged: String, onto target: String) {
        guard let from = tickers.firstIndex(where: { $0.id.uuidString == dragged }),
              let to = tickers.firstIndex(where: { $0.id.uuidString == target }) else { return }
        let item = tickers.remove(at: from)
        tickers.insert(item, at: to)
    }

    func open(_ ticker: Ticker) {
        let symbol = ticker.tradingViewSymbol.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ticker.tradingViewSymbol
        if let url = URL(string: "https://www.tradingview.com/chart/?symbol=\(symbol)") {
            NSWorkspace.shared.open(url)
        }
    }

    func refresh() async {
        for ticker in tickers {
            if let quote = await fetch(ticker.symbol) { quotes[ticker.symbol] = quote }
        }
        updatedAt = Date()
    }

    private func fetch(_ symbol: String) async -> Quote? {
        let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? symbol
        guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)?range=1d&interval=15m") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = ((json["chart"] as? [String: Any])?["result"] as? [[String: Any]])?.first,
              let meta = result["meta"] as? [String: Any],
              let price = meta["regularMarketPrice"] as? Double else { return nil }
        let previous = (meta["chartPreviousClose"] as? Double) ?? (meta["previousClose"] as? Double) ?? price
        let closes = ((((result["indicators"] as? [String: Any])?["quote"] as? [[String: Any]])?.first)?["close"] as? [Any])?
            .compactMap { $0 as? Double } ?? []
        return Quote(price: price, previousClose: previous, closes: closes)
    }

    static func formatProfit(_ value: Double, currency: String) -> String {
        let text = value.formatted(.number.precision(.fractionLength(abs(value) >= 1000 ? 0 : 2)).sign(strategy: .always()))
        return currency.isEmpty ? text : "\(text) \(currency)"
    }

    static func format(_ price: Double) -> String {
        let digits = price < 10 ? 4 : (price < 1000 ? 2 : 0)
        return price.formatted(.number.precision(.fractionLength(digits)))
    }
}

/// Little line chart of today's prices.
struct Sparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        Canvas { ctx, size in
            guard values.count > 1, let lo = values.min(), let hi = values.max() else { return }
            let range = max(hi - lo, .ulpOfOne)
            var path = Path()
            for (i, v) in values.enumerated() {
                let point = CGPoint(x: size.width * CGFloat(i) / CGFloat(values.count - 1),
                                    y: size.height * (1 - CGFloat((v - lo) / range)))
                i == 0 ? path.move(to: point) : path.addLine(to: point)
            }
            ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
        }
    }
}

struct MarketsCard: View {
    @ObservedObject private var store = MarketStore.shared

    var body: some View {
        card {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Markets").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Button(store.useTradingViewWidget ? "TradingView" : "Built-in") { store.useTradingViewWidget.toggle() }
                        .buttonStyle(.plain).font(.system(size: 8)).foregroundStyle(.secondary)
                        .help("Switch between TradingView's live widget and the built-in list")
                    if !store.useTradingViewWidget, let updated = store.updatedAt {
                        Text(updated.formatted(date: .omitted, time: .shortened)).font(.system(size: 8)).foregroundStyle(.secondary)
                    }
                }
                if store.useTradingViewWidget {
                    TradingViewWidget(symbols: store.tickers.map { ($0.tradingViewSymbol, $0.name) })
                        .frame(height: CGFloat(max(store.tickers.count, 1)) * 38 + 34)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    ForEach(store.tickers) { ticker in
                        row(ticker)
                    }
                }
            }
        }
    }

    private func row(_ ticker: Ticker) -> some View {
        let quote = store.quotes[ticker.symbol]
        let up = (quote?.change ?? 0) >= 0
        let trend = up ? store.upColor : store.downColor
        return Button { store.open(ticker) } label: {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 8) {
                    Text(ticker.name).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                        .foregroundStyle(ticker.colorHex.map { Color(hex: $0) } ?? Color.white)
                        .frame(width: 64, alignment: .leading)
                    Sparkline(values: quote?.closes ?? [], color: trend)
                        .frame(height: 16)
                    Text(quote.map { MarketStore.format($0.price) } ?? "–")
                        .font(.system(size: 10, weight: .medium, design: .rounded)).monospacedDigit()
                        .frame(width: 66, alignment: .trailing)
                    Text(quote.map { String(format: "%+.2f%%", $0.change) } ?? "")
                        .font(.system(size: 9, weight: .semibold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(trend)
                        .frame(width: 50, alignment: .trailing)
                }
                if let quote, let pl = ticker.profit(at: quote.price), let pos = ticker.position {
                    HStack(spacing: 6) {
                        Text("\(pos.long ? "Long" : "Short") \(pos.size.formatted()) @ \(MarketStore.format(pos.entry))")
                            .font(.system(size: 8)).foregroundStyle(.secondary)
                        Spacer()
                        Text("P/L " + MarketStore.formatProfit(pl, currency: ticker.quoteCurrency))
                            .font(.system(size: 9, weight: .bold, design: .rounded)).monospacedDigit()
                            .foregroundStyle(pl >= 0 ? store.upColor : store.downColor)
                    }
                    .padding(.leading, 72)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open \(ticker.tradingViewSymbol) on TradingView")
        .reorderSource(id: ticker.id.uuidString)
        .reorderTarget(id: ticker.id.uuidString) { store.move(dragged: $0, onto: $1) }
    }
}
