import SwiftUI
import Combine

/// Weather from Open-Meteo (free, no account). The city is looked up once
/// with Open-Meteo's geocoder; no location permission is used.
@MainActor
final class WeatherStore: ObservableObject {
    static let shared = WeatherStore()

    struct Hour: Identifiable { let id = UUID(); let time: Date; let temp: Double; let code: Int; let isDay: Bool }
    struct Day: Identifiable { let id = UUID(); let date: Date; let high: Double; let low: Double; let code: Int }

    @Published var city: String {
        didSet { UserDefaults.standard.set(city, forKey: "weather.city"); latitude = nil; Task { await refresh() } }
    }
    @Published var fahrenheit: Bool {
        didSet { UserDefaults.standard.set(fahrenheit, forKey: "weather.fahrenheit"); Task { await refresh() } }
    }
    @Published private(set) var temperature: Double?
    @Published private(set) var code: Int = 0
    @Published private(set) var isDay = true
    @Published private(set) var hours: [Hour] = []
    @Published private(set) var days: [Day] = []
    @Published private(set) var resolvedName = ""
    @Published private(set) var error: String?

    private var latitude: Double?
    private var longitude: Double?
    private var zone = "auto"
    private var lastFetch: Date?

    private init() {
        city = UserDefaults.standard.string(forKey: "weather.city") ?? "London"
        fahrenheit = UserDefaults.standard.bool(forKey: "weather.fahrenheit")
    }

    /// Fetches if the last reading is older than 15 minutes.
    func refreshIfStale() {
        if let lastFetch, Date().timeIntervalSince(lastFetch) < 900 { return }
        Task { await refresh() }
    }

    func refresh() async {
        if latitude == nil { await geocode() }
        guard let latitude, let longitude else { return }
        let unit = fahrenheit ? "&temperature_unit=fahrenheit" : ""
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(latitude)&longitude=\(longitude)&current=temperature_2m,weather_code,is_day&hourly=temperature_2m,weather_code,is_day&daily=temperature_2m_max,temperature_2m_min,weather_code&forecast_days=6&timezone=\(zone)\(unit)"
        guard let url = URL(string: urlString),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            error = "Weather unavailable"
            return
        }
        lastFetch = Date()
        error = nil
        if let current = json["current"] as? [String: Any] {
            temperature = current["temperature_2m"] as? Double
            code = current["weather_code"] as? Int ?? 0
            isDay = (current["is_day"] as? Int ?? 1) == 1
        }
        let iso = DateFormatter()
        iso.dateFormat = "yyyy-MM-dd'T'HH:mm"
        iso.timeZone = TimeZone(identifier: (json["timezone"] as? String) ?? "") ?? .current
        if let hourly = json["hourly"] as? [String: Any],
           let times = hourly["time"] as? [String], let temps = hourly["temperature_2m"] as? [Double],
           let codes = hourly["weather_code"] as? [Int] {
            let dayFlags = hourly["is_day"] as? [Int] ?? []
            let now = Date().addingTimeInterval(-3600)
            hours = zip(times.indices, times).compactMap { i, t in
                guard let d = iso.date(from: t), d > now, i < temps.count, i < codes.count else { return nil }
                return Hour(time: d, temp: temps[i], code: codes[i], isDay: i < dayFlags.count ? dayFlags[i] == 1 : true)
            }.prefix(12).map { $0 }
        }
        let dayFormat = DateFormatter()
        dayFormat.dateFormat = "yyyy-MM-dd"
        dayFormat.timeZone = iso.timeZone
        if let daily = json["daily"] as? [String: Any],
           let times = daily["time"] as? [String], let highs = daily["temperature_2m_max"] as? [Double],
           let lows = daily["temperature_2m_min"] as? [Double], let codes = daily["weather_code"] as? [Int] {
            days = times.indices.compactMap { i in
                guard let d = dayFormat.date(from: times[i]), i < highs.count, i < lows.count, i < codes.count else { return nil }
                return Day(date: d, high: highs[i], low: lows[i], code: codes[i])
            }
        }
    }

    private func geocode() async {
        let query = city.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? city
        guard let url = URL(string: "https://geocoding-api.open-meteo.com/v1/search?name=\(query)&count=1"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let first = (json["results"] as? [[String: Any]])?.first,
              let lat = first["latitude"] as? Double, let lon = first["longitude"] as? Double else {
            error = "Couldn't find \(city)"
            return
        }
        latitude = lat
        longitude = lon
        zone = (first["timezone"] as? String) ?? "auto"
        resolvedName = [first["name"] as? String, first["country_code"] as? String].compactMap { $0 }.joined(separator: ", ")
    }

    /// WMO weather code → SF Symbol (shown in its own colours).
    static func symbol(_ code: Int, day: Bool = true) -> String {
        switch code {
        case 0: return day ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: return day ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...57: return "cloud.drizzle.fill"
        case 61...67, 80...82: return "cloud.rain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    func temp(_ value: Double?) -> String {
        guard let value else { return "–" }
        return "\(Int(value.rounded()))°"
    }
}

struct WeatherCard: View {
    @ObservedObject private var weather = WeatherStore.shared

    var body: some View {
        card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: WeatherStore.symbol(weather.code, day: weather.isDay))
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 28))
                        .animatedSymbol(WeatherStore.animation(for: weather.code, day: weather.isDay))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(weather.temp(weather.temperature)).font(.system(size: 22, weight: .semibold, design: .rounded))
                        Text(weather.error ?? (weather.resolvedName.isEmpty ? weather.city : weather.resolvedName))
                            .font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(weather.hours) { hour in
                            VStack(spacing: 3) {
                                Text(hour.time.formatted(.dateTime.hour()))
                                    .font(.system(size: 8)).foregroundStyle(.secondary)
                                Image(systemName: WeatherStore.symbol(hour.code, day: hour.isDay))
                                    .symbolRenderingMode(.multicolor).font(.system(size: 12))
                                Text(weather.temp(hour.temp)).font(.system(size: 9, weight: .medium))
                            }
                        }
                    }
                }
                HStack(spacing: 0) {
                    ForEach(weather.days.prefix(5)) { day in
                        VStack(spacing: 2) {
                            Text(day.date.formatted(.dateTime.weekday(.abbreviated)))
                                .font(.system(size: 8)).foregroundStyle(.secondary)
                            Image(systemName: WeatherStore.symbol(day.code))
                                .symbolRenderingMode(.multicolor).font(.system(size: 11))
                            Text("\(weather.temp(day.high)) \(weather.temp(day.low))")
                                .font(.system(size: 8)).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .onAppear { weather.refreshIfStale() }
    }
}
