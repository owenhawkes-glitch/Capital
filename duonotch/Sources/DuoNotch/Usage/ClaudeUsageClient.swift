import Foundation

enum UsageError: Error, LocalizedError {
    case http(Int, String)
    case rateLimited(retryAfter: TimeInterval?)
    case unauthorized
    case decode

    var errorDescription: String? {
        switch self {
        case .http(let code, let body):
            return "HTTP \(code)\(body.isEmpty ? "" : ": \(body.prefix(80))")"
        case .rateLimited:
            return "Rate limited by the usage endpoint"
        case .unauthorized:
            return "Token rejected – run `claude` for this login to refresh it"
        case .decode:
            return "Unexpected response from the usage endpoint"
        }
    }
}

/// Asks the endpoint Claude Code's `/usage` command uses. This is not a
/// documented public API; the URL can be overridden with the
/// `usageEndpoint` default if it moves.
struct ClaudeUsageClient {
    static let defaultEndpoint = "https://api.anthropic.com/api/oauth/usage"

    static var endpoint: URL {
        if let custom = UserDefaults.standard.string(forKey: "usageEndpoint"),
           let url = URL(string: custom), !custom.isEmpty {
            return url
        }
        return URL(string: defaultEndpoint)!
    }

    private struct APIWindow: Decodable {
        let utilization: Double?
        let resets_at: String?
    }

    private struct APIResponse: Decodable {
        let five_hour: APIWindow?
        let seven_day: APIWindow?
        let seven_day_opus: APIWindow?
        let seven_day_sonnet: APIWindow?
    }

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)
    }

    func fetch(accessToken: String) async throws -> UsageReading {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("DuoNotch/0.1", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UsageError.decode }

        switch http.statusCode {
        case 200:
            break
        case 401, 403:
            throw UsageError.unauthorized
        case 429:
            let retry = http.value(forHTTPHeaderField: "Retry-After").flatMap { Double($0) }
            throw UsageError.rateLimited(retryAfter: retry)
        default:
            throw UsageError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        guard let decoded = try? JSONDecoder().decode(APIResponse.self, from: data) else {
            throw UsageError.decode
        }

        return UsageReading(
            fetchedAt: Date(),
            session: Self.window(decoded.five_hour),
            weekly: Self.window(decoded.seven_day),
            weeklyOpus: Self.window(decoded.seven_day_opus),
            weeklySonnet: Self.window(decoded.seven_day_sonnet),
            subscriptionType: nil
        )
    }

    private static func window(_ api: APIWindow?) -> UsageWindow? {
        guard let api, let utilization = api.utilization else { return nil }
        // The endpoint reports percentages (0–100).
        let fraction = min(max(utilization / 100, 0), 1)
        return UsageWindow(fraction: fraction, resetsAt: parseDate(api.resets_at))
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        return isoFractional.date(from: raw) ?? isoPlain.date(from: raw)
    }
}
