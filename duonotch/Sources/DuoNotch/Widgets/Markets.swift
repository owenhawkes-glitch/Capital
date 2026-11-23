import SwiftUI
import Combine

/// A market symbol. Prices come from Yahoo Finance's public chart feed;
/// clicking opens the TradingView chart.
struct Ticker: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    /// Yahoo-style symbol: EURUSD=X, GBPUSD=X, GC=F, ^GSPC, AAPL, BTC-USD.
    var symbol: String
    /// TradingView symbol, e.g. FX:EURUSD. Empty = worked out from `symbol`.
    var tradingView: String = ""

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
                    if let updated = store.updatedAt {
                        Text(updated.formatted(date: .omitted, time: .shortened)).font(.system(size: 8)).foregroundStyle(.secondary)
                    }
                }
                ForEach(store.tickers) { ticker in
                    let quote = store.quotes[ticker.symbol]
                    let up = (quote?.change ?? 0) >= 0
                    Button { store.open(ticker) } label: {
                        HStack(spacing: 8) {
                            Text(ticker.name).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                                .frame(width: 64, alignment: .leading)
                            Sparkline(values: quote?.closes ?? [], color: up ? .green : .red)
                                .frame(height: 16)
                            Text(quote.map { MarketStore.format($0.price) } ?? "–")
                                .font(.system(size: 10, weight: .medium, design: .rounded)).monospacedDigit()
                                .frame(width: 66, alignment: .trailing)
                            Text(quote.map { String(format: "%+.2f%%", $0.change) } ?? "")
                                .font(.system(size: 9, weight: .semibold, design: .rounded)).monospacedDigit()
                                .foregroundStyle(up ? Color.green : Color.red)
                                .frame(width: 50, alignment: .trailing)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Open \(ticker.tradingViewSymbol) on TradingView")
                    .reorderSource(id: ticker.id.uuidString)
                    .reorderTarget(id: ticker.id.uuidString) { store.move(dragged: $0, onto: $1) }
                }
            }
        }
    }
}
