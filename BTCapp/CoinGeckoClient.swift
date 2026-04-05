import Foundation

// MARK: - CoinGecko Client

struct CoinGeckoClient {
    enum CGError: LocalizedError {
        case http(Int, String)
        case badData

        var errorDescription: String? {
            switch self {
            case let .http(code, details):
                return details.isEmpty ? "HTTP error \(code)" : "HTTP error \(code): \(details)"
            case .badData:
                return "Malformed response data"
            }
        }
    }

    private static func request(_ url: URL) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 10
        let key = AppConfig.coinGeckoApiKey
        if !key.isEmpty {
            req.setValue(key, forHTTPHeaderField: "x-cg-demo-api-key")
        }
        return req
    }

    private static func fetchData(_ url: URL) async throws -> Data {
        let req = request(url)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw CGError.badData }

        if http.statusCode == 429 {
            // Respect Retry-After if present, else 2s; retry once.
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap { Int($0) }
            let waitSec = min(max(retryAfter ?? 2, 1), 10)
            try await Task.sleep(nanoseconds: UInt64(waitSec) * 1_000_000_000)
            let (data2, resp2) = try await URLSession.shared.data(for: req)
            guard let http2 = resp2 as? HTTPURLResponse else { throw CGError.badData }
            if !(200...299).contains(http2.statusCode) {
                throw CGError.http(http2.statusCode, String(data: data2, encoding: .utf8) ?? "")
            }
            return data2
        }

        if !(200...299).contains(http.statusCode) {
            throw CGError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    /// Fetch 2 days of market chart, slice to last ~24h based on timestamps.
    static func fetchBtcPriceHistoryLast24h(vsCurrency: String) async throws -> [Double] {
        let c = vsCurrency.lowercased()
        let url = URL(string: "https://api.coingecko.com/api/v3/coins/bitcoin/market_chart?vs_currency=\(c)&days=2")!
        let data = try await fetchData(url)

        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let prices = obj?["prices"] as? [[Any]] else { throw CGError.badData }

        var points: [(ts: Int64, price: Double)] = []
        points.reserveCapacity(prices.count)
        for row in prices {
            guard row.count >= 2 else { continue }
            let ts = (row[0] as? NSNumber)?.int64Value ?? 0
            let price = (row[1] as? NSNumber)?.doubleValue ?? 0
            points.append((ts, price))
        }
        guard let last = points.last else { return [] }
        let cutoff = last.ts - 24 * 60 * 60 * 1000
        return points.filter { $0.ts >= cutoff }.map { $0.price }
    }

    static func fetchComparisons(vsCurrency: String) async throws -> (btc: Double, eth: Double, paxg: Double) {
        let c = vsCurrency.lowercased()
        let url = URL(string: "https://api.coingecko.com/api/v3/simple/price?ids=bitcoin,ethereum,pax-gold&vs_currencies=\(c)")!
        let data = try await fetchData(url)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard
            let btc = (obj?["bitcoin"] as? [String: Any])?[c] as? NSNumber,
            let eth = (obj?["ethereum"] as? [String: Any])?[c] as? NSNumber,
            let paxg = (obj?["pax-gold"] as? [String: Any])?[c] as? NSNumber
        else { throw CGError.badData }
        return (btc.doubleValue, eth.doubleValue, paxg.doubleValue)
    }

    static func fetchBtcSpot(vsCurrency: String) async throws -> Double {
        let c = vsCurrency.lowercased()
        let url = URL(string: "https://api.coingecko.com/api/v3/simple/price?ids=bitcoin&vs_currencies=\(c)")!
        let data = try await fetchData(url)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let btc = (obj?["bitcoin"] as? [String: Any])?[c] as? NSNumber else {
            throw CGError.badData
        }
        return btc.doubleValue
    }
}
