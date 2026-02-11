//
//  ContentView.swift
//  BTCapp
//
//  Created by Ron Scanlon on 12/17/25.
//

import SwiftUI
import Combine
import Security
import LocalAuthentication
import UniformTypeIdentifiers

extension Color {
    static let btcOrange = Color(red: 0.97, green: 0.58, blue: 0.10) // #F7931A
}

// MARK: - Models

struct DcaEntry: Codable, Identifiable, Hashable {
    let id: UUID
    var amountBtc: Double
    var priceUsd: Double
    /// Unix timestamp (seconds)
    var timestamp: Double

    init(id: UUID = UUID(), amountBtc: Double, priceUsd: Double, timestamp: Double = Date().timeIntervalSince1970) {
        self.id = id
        self.amountBtc = amountBtc
        self.priceUsd = priceUsd
        self.timestamp = timestamp
    }

    var costUsd: Double { amountBtc * priceUsd }
    var date: Date { Date(timeIntervalSince1970: timestamp) }

    private enum CodingKeys: String, CodingKey {
        case id, amountBtc, priceUsd, timestamp
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        self.amountBtc = (try? c.decode(Double.self, forKey: .amountBtc)) ?? 0
        self.priceUsd = (try? c.decode(Double.self, forKey: .priceUsd)) ?? 0
        // Backwards compatibility: older saved entries won't have timestamp
        self.timestamp = (try? c.decode(Double.self, forKey: .timestamp)) ?? Date().timeIntervalSince1970
    }
}

// MARK: - DCA Export/Import Documents

struct DcaJSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    static var writableContentTypes: [UTType] { [.json] }

    var entries: [DcaEntry]

    init(entries: [DcaEntry]) {
        self.entries = entries
    }

    init(configuration: ReadConfiguration) throws {
        let data = configuration.file.regularFileContents ?? Data()
        self.entries = (try? JSONDecoder().decode([DcaEntry].self, from: data)) ?? []
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try JSONEncoder().encode(entries)
        return .init(regularFileWithContents: data)
    }
}

struct DcaCSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText, .plainText] }
    static var writableContentTypes: [UTType] { [.commaSeparatedText] }

    var csvText: String

    init(csvText: String) {
        self.csvText = csvText
    }

    init(configuration: ReadConfiguration) throws {
        let data = configuration.file.regularFileContents ?? Data()
        self.csvText = String(data: data, encoding: .utf8) ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(csvText.utf8))
    }
}

struct DcaExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText, .plainText] }
    static var writableContentTypes: [UTType] { [.json, .commaSeparatedText] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - App State

final class AppModel: ObservableObject {
    static let shared = AppModel()

    private enum Keys {
        static let proMode = "pro_mode"
        static let currency = "currency"
        // Keychain key (device-only; not iCloud-synced)
        static let dcaKeychainKey = "dca_entries_json_device_only"
        static let satsMode = "sats_mode"
        static let satsGoalSats = "sats_goal_sats"
    }

    // Persisted settings (manual UserDefaults for iOS 13 compatibility)
    @Published var isProMode: Bool {
        didSet {
            UserDefaults.standard.set(isProMode, forKey: Keys.proMode)
        }
    }

    @Published var currency: String {
        didSet {
            UserDefaults.standard.set(currency, forKey: Keys.currency)
        }
    }

    @Published var satsMode: Bool {
        didSet {
            UserDefaults.standard.set(satsMode, forKey: Keys.satsMode)
        }
    }

    /// Goal in satoshis for stacking progress.
    @Published var satsGoalSats: Int64 {
        didSet {
            UserDefaults.standard.set(satsGoalSats, forKey: Keys.satsGoalSats)
        }
    }

    @Published var dcaEntries: [DcaEntry] = [] {
        didSet { saveDca() }
    }

    // Shared price state for tab sparkline / delta badge
    @Published var btcSpotUsd: Double? = nil
    @Published var btcHistoryLast24hUsd: [Double] = []
    @Published var btc24hChangeUsd: Double? = nil
    @Published var btc24hChangePct: Double? = nil

    private init() {
        self.isProMode = UserDefaults.standard.bool(forKey: Keys.proMode)
        self.currency = UserDefaults.standard.string(forKey: Keys.currency) ?? "USD"
        self.satsMode = UserDefaults.standard.bool(forKey: Keys.satsMode)
        let storedGoal = UserDefaults.standard.object(forKey: Keys.satsGoalSats) as? NSNumber
        self.satsGoalSats = storedGoal?.int64Value ?? 1_000_000 // default: 1,000,000 sats
        self.dcaEntries = []
        self.dcaEntries = loadDca()
    }

    func toggleCurrency() {
        currency = (currency == "USD") ? "EUR" : "USD"
    }

    func btcToSats(_ btc: Double) -> Int64 {
        Int64((btc * 100_000_000).rounded())
    }

    func formatSats(_ sats: Int64) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.groupingSeparator = ","
        nf.maximumFractionDigits = 0
        return nf.string(from: NSNumber(value: sats)) ?? "\(sats)"
    }

    func formatBtc(_ btc: Double) -> String {
        String(format: "%.8f", btc)
    }

    private func loadDca() -> [DcaEntry] {
        let json = KeychainStore.getString(key: Keys.dcaKeychainKey) ?? ""
        guard let data = json.data(using: .utf8), !json.isEmpty else { return [] }
        do {
            return try JSONDecoder().decode([DcaEntry].self, from: data)
        } catch {
            return []
        }
    }

    private func saveDca() {
        do {
            let data = try JSONEncoder().encode(dcaEntries)
            let json = String(data: data, encoding: .utf8) ?? ""
            KeychainStore.setString(json, key: Keys.dcaKeychainKey)
        } catch {
            // ignore
        }
    }
}

// MARK: - Keychain (device-only storage)
private enum KeychainStore {
    static let service = "BTCapp"

    static func setString(_ value: String, key: String) {
        let data = Data(value.utf8)

        // Delete any existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new item (THIS DEVICE ONLY)
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    static func getString(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
// MARK: - CoinGecko Client

struct CoinGeckoClient {
    /// NOTE: For App Store builds, do not hardcode keys. Use a server/proxy or secure config.
    /// This is here only to mirror your IOS prototype.
    static let demoApiKey: String = "CG-26iJ5q61kFYj2tArmQXg1Bf8"

    enum CGError: LocalizedError {
        case http(Int, String)
        case badData

        var errorDescription: String? {
            switch self {
            case let .http(code, details):
                if details.isEmpty { return "HTTP error \(code)" }
                return "HTTP error \(code): \(details)"
            case .badData:
                return "Malformed response data"
            }
        }
    }

    private static func request(_ url: URL) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 10
        if !demoApiKey.isEmpty {
            req.setValue(demoApiKey, forHTTPHeaderField: "x-cg-demo-api-key")
        }
        return req
    }

    private static func fetchData(_ url: URL) async throws -> Data {
        let req = request(url)
        let (data, resp): (Data, URLResponse) = try await withCheckedThrowingContinuation { cont in
            URLSession.shared.dataTask(with: req) { data, resp, err in
                if let err = err { cont.resume(throwing: err); return }
                guard let data = data, let resp = resp else { cont.resume(throwing: CGError.badData); return }
                cont.resume(returning: (data, resp))
            }.resume()
        }
        guard let http = resp as? HTTPURLResponse else {
            throw CGError.badData
        }
        if http.statusCode == 429 {
            // Basic backoff: respect Retry-After if present, else 2s; retry once.
            let retryAfter = (http.value(forHTTPHeaderField: "Retry-After")).flatMap { Int($0) }
            let waitSec = min(max(retryAfter ?? 2, 1), 10)
            try await Task.sleep(nanoseconds: UInt64(waitSec) * 1_000_000_000)
            let (data2, resp2): (Data, URLResponse) = try await withCheckedThrowingContinuation { cont in
                URLSession.shared.dataTask(with: req) { data, resp, err in
                    if let err = err { cont.resume(throwing: err); return }
                    guard let data = data, let resp = resp else { cont.resume(throwing: CGError.badData); return }
                    cont.resume(returning: (data, resp))
                }.resume()
            }
            guard let http2 = resp2 as? HTTPURLResponse else { throw CGError.badData }
            if !(200...299).contains(http2.statusCode) {
                let details = String(data: data2, encoding: .utf8) ?? ""
                throw CGError.http(http2.statusCode, details)
            }
            return data2
        }

        if !(200...299).contains(http.statusCode) {
            let details = String(data: data, encoding: .utf8) ?? ""
            throw CGError.http(http.statusCode, details)
        }
        return data
    }

    /// Fetch 2 days of market chart (no hourly interval), slice to last ~24h based on timestamps.
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

// MARK: - Watermark

struct WatermarkBackground<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            GeometryReader { geo in
                let size = min(geo.size.width, geo.size.height) * 0.92
                // Expect `btc_watermark` in Assets.xcassets
                Image("btc_watermark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .opacity(scheme == .dark ? 0.22 : 0.34)
                    .rotationEffect(.degrees(-10))
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    .allowsHitTesting(false)
            }
            .ignoresSafeArea()

            content
        }
    }
}

// MARK: - Root

struct ContentView: View {
    @ObservedObject private var model = AppModel.shared

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView {
                NavigationView { HomeView() }
                    .environmentObject(model)
                    .tabItem { Label("Home", systemImage: "house") }

                NavigationView { PriceView() }
                    .environmentObject(model)
                    .tabItem {
                        VStack(spacing: 3) {
                            Image(systemName: "dollarsign.circle")
                            Text("Price")
                            HStack(spacing: 6) {
                                Sparkline(prices: Array(model.btcHistoryLast24hUsd.suffix(36)))
                                    .frame(width: 34, height: 12)

                                if let pct = model.btc24hChangePct {
                                    let isUp = pct >= 0
                                    Text("\(isUp ? "+" : "")\(pct, specifier: "%.2f")%")
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .foregroundStyle(.white)
                                        .background(
                                            Capsule().fill(isUp ? Color.green : Color.red)
                                        )
                                }
                            }
                        }
                    }

                NavigationView { DcaView() }
                    .environmentObject(model)
                    .tabItem { Label("DCA", systemImage: "chart.line.uptrend.xyaxis") }

                NavigationView { SettingsView() }
                    .environmentObject(model)
                    .tabItem { Label("Settings", systemImage: "gearshape") }
            }
            .tint(Color.btcOrange)

            Rectangle()
                .frame(height: 60)
                .background {
                    if #available(iOS 17, *) {
                        Color.clear.background(.ultraThinMaterial)
                    } else {
                        Color.clear.background(.ultraThinMaterial)
                    }
                }
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
                .zIndex(-1)
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Home

struct HomeView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        WatermarkBackground {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Bitcoin Dashboard")
                        .font(.title2).bold()
                        .foregroundStyle(Color.btcOrange)
                        .frame(maxWidth: .infinity, alignment: .center)

                    Text("Welcome! Use the tabs below to see the live price, track DCA, learn about Bitcoin, and change settings.")
                        .font(.body)

                    Text("Pro Mode status: \(model.isProMode ? "On – BTC vs ETH & Gold analytics enabled" : "Off – enable in Settings for extra analytics")")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    // Stacking Progress
                    let totalBtc = model.dcaEntries.reduce(0) { $0 + $1.amountBtc }
                    let totalSats = model.btcToSats(totalBtc)
                    let goalSats = max(model.satsGoalSats, 1)
                    let progress = min(Double(totalSats) / Double(goalSats), 1.0)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Stacking Progress")
                                .font(.subheadline).bold()
                            Spacer()
                            Text(model.satsMode ? "SATs" : "BTC")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: progress)

                        if model.satsMode {
                            Text("Stacked: \(model.formatSats(totalSats)) sats")
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                            Text("Goal: \(model.formatSats(goalSats)) sats  •  \(progress * 100, specifier: "%.1f")%")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            let goalBtc = Double(goalSats) / 100_000_000.0

                            Text("Stacked: \(model.formatBtc(totalBtc)) BTC")
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                            Text("Goal: \(model.formatBtc(goalBtc)) BTC  •  \(progress * 100, specifier: "%.1f")%")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    NavigationLink("Learn About Bitcoin") {
                        LearnView()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.btcOrange)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("What you can do in this app:")
                            .font(.subheadline).bold()
                        Text("• Check the live Bitcoin price with a 24h chart\n• Compare BTC against Ethereum and Gold in Pro Mode\n• Track your DCA average\n• Read primary sources (whitepaper + genesis block)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(20)
            }
            .navigationTitle("BTC Info")
        }
    }
}

// MARK: - Price

struct PriceView: View {
    @EnvironmentObject private var model: AppModel

    @State private var isLoading = false
    @State private var error: String?

    @State private var history: [Double] = []
    @State private var current: Double?
    @State private var lastUpdated: String?
    @State private var lastUpdatedAt: Date?

    @State private var eth: Double?
    @State private var paxg: Double?

    // Simple TTL cache for comparisons to avoid 429 spam
    @State private var comparisonsLastFetch: Date?

    @Environment(\.verticalSizeClass) private var vSize

    private var chartHeight: CGFloat {
        // Landscape is typically compact vertical size class
        (vSize == .compact) ? 120 : 160
    }

    var body: some View {
        WatermarkBackground {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Live BTC Price")
                        .font(.title3).bold()
                        .foregroundStyle(Color.btcOrange)

                    if isLoading {
                        Text("Loading current BTC price...")
                            .foregroundStyle(.secondary)
                    } else if let current {
                        Text("Current price (\(model.currency)):")
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        Text(current, format: .currency(code: model.currency))
                            .font(.largeTitle).bold()

                        if let lastUpdated {
                            HStack(spacing: 10) {
                                Text("Last updated: \(lastUpdated)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)

                                if let t = lastUpdatedAt, Date().timeIntervalSince(t) < 60 {
                                    Text("LIVE")
                                        .font(.caption2).bold()
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .foregroundStyle(.white)
                                        .background(Capsule().fill(Color.btcOrange))
                                }
                            }
                        }

                        if let error {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(Color.red)
                        }
                    } else if let error {
                        Text(error)
                            .foregroundStyle(Color.red)
                    } else {
                        Text("Price data not available.")
                            .foregroundStyle(.secondary)
                    }

                    if history.count >= 2 {
                        let high = history.max() ?? 0
                        let low = history.min() ?? 0
                        let start = history.first ?? 0
                        let end = history.last ?? 0
                        let diff = end - start
                        let pct = start != 0 ? (diff / start) * 100 : 0

                        VStack(alignment: .leading, spacing: 6) {
                            Text("24h range:")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Text("Low: \(low, format: .currency(code: model.currency))   High: \(high, format: .currency(code: model.currency))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                            Text("24h change: \(diff >= 0 ? "+" : "")\(diff, specifier: "%.2f") \(model.currency) (\(pct, specifier: "%.2f")%)")
                                .font(.footnote)
                                .foregroundStyle(diff >= 0 ? Color.btcOrange : Color.red)
                        }
                        .padding(.top, 4)

                        LineChart(prices: history)
                            .frame(height: chartHeight)
                            .padding(.vertical, 8)
                    }

                    Button {
                        Task { await refreshAll(forceComparisons: model.isProMode) }
                    } label: {
                        Text("Refresh Price")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.btcOrange)

                    if model.isProMode, let current, let eth, let paxg {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Pro Mode: BTC vs Other Assets")
                                .font(.callout).bold()

                            Text("ETH price: \(eth, format: .currency(code: model.currency))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                            Text("Gold (PAXG) price: \(paxg, format: .currency(code: model.currency))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                            let btcPerEth = eth != 0 ? current / eth : 0
                            let btcPerGold = paxg != 0 ? current / paxg : 0
                            Text("BTC / ETH: \(btcPerEth, specifier: "%.4f")")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text("BTC / Gold (oz): \(btcPerGold, specifier: "%.4f")")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 8)
                    }

                    Spacer(minLength: 20)
                }
                .padding(20)
            }
            .navigationTitle("Price")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if isLoading {
                        ProgressView().scaleEffect(0.9)
                    } else {
                        Button {
                            Task { await refreshAll(forceComparisons: true) }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .accessibilityLabel("Refresh")
                    }
                }
            }
            .refreshable {
                await refreshAll(forceComparisons: false)
            }
            .onAppear {
                Task { await refreshAll(forceComparisons: false) }
            }
            .onChange(of: model.isProMode) { newValue in
                if newValue {
                    Task { await refreshComparisons(force: false) }
                } else {
                    eth = nil
                    paxg = nil
                }
            }
            .onChange(of: model.currency) { _ in
                Task { await refreshAll(forceComparisons: false) }
            }
        }
    }

    private func refreshAll(forceComparisons: Bool) async {
        isLoading = true
        error = nil
        do {
            async let chartTask: [Double] = CoinGeckoClient.fetchBtcPriceHistoryLast24h(vsCurrency: model.currency)
            async let spotTask: Double = CoinGeckoClient.fetchBtcSpot(vsCurrency: model.currency)

            let prices = try await chartTask
            let spot = try await spotTask

            history = prices
            current = spot

            // Publish to shared model for tab sparkline / delta badge
            model.btcHistoryLast24hUsd = prices
            model.btcSpotUsd = spot
            if let start = prices.first, let end = prices.last {
                let diff = end - start
                let pct = start != 0 ? (diff / start) * 100 : 0
                model.btc24hChangeUsd = diff
                model.btc24hChangePct = pct
            } else {
                model.btc24hChangeUsd = nil
                model.btc24hChangePct = nil
            }

            let now = Date()
            lastUpdatedAt = now
            let df = DateFormatter()
            df.dateFormat = "HH:mm:ss"
            lastUpdated = df.string(from: now)

            if model.isProMode {
                await refreshComparisons(force: forceComparisons)
            }
        } catch {
            self.error = "Failed to load data: \(error.localizedDescription)"
        }
        isLoading = false
    }

    private func refreshComparisons(force: Bool) async {
        if !force, let last = comparisonsLastFetch, Date().timeIntervalSince(last) < 60 {
            return
        }
        do {
            let c = try await CoinGeckoClient.fetchComparisons(vsCurrency: model.currency)
            comparisonsLastFetch = Date()
            eth = c.eth
            paxg = c.paxg
        } catch {
            // keep price chart working even if comparisons fail
            self.error = "Comparisons failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - DCA

struct DcaView: View {
    @EnvironmentObject private var model: AppModel

    @State private var amountInput = ""
    @State private var priceInput = ""
    @State private var inputError: String?

    // Edit flow
    @State private var editingEntry: DcaEntry?
    @State private var editAmountInput = ""
    @State private var editPriceInput = ""
    @State private var editDate = Date()
    @State private var editError: String?

    // Export / Import
    private enum ExportFormat: String, CaseIterable, Identifiable {
        case json = "JSON"
        case csv = "CSV"
        var id: String { rawValue }
    }
    @State private var exportFormat: ExportFormat = .json
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var importError: String?
    @State private var pendingImportCount: Int?

    private enum Field: Hashable { case amount, price }
    @FocusState private var focusedField: Field?

    @State private var isUnlocked = false
    @State private var authError: String?
    @State private var currentBtcPrice: Double?
    @State private var isLoadingPrice = false
    @State private var lastPriceUpdated: String?
    @State private var lastPriceFetchAt: Date?
    @State private var autoRefreshTask: Task<Void, Never>?

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df
    }()

    private var lockedView: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.fill")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(Color.btcOrange)

            Text("DCA is locked")
                .font(.title3).bold()

            Text("Unlock with Face ID / Touch ID (or passcode). Your entries never leave this device.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if let authError {
                Text(authError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Button("Unlock") { authenticate() }
                .buttonStyle(.borderedProminent)
                .tint(Color.btcOrange)
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { if !isUnlocked { authenticate() } }
    }

    private func authenticate() {
        let context = LAContext()
        var error: NSError?
        let canBio = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        let policy: LAPolicy = canBio ? .deviceOwnerAuthenticationWithBiometrics : .deviceOwnerAuthentication

        context.evaluatePolicy(policy, localizedReason: "Unlock your DCA entries") { success, err in
            DispatchQueue.main.async {
                if success { isUnlocked = true }
                else { authError = err?.localizedDescription ?? "Authentication failed" }
            }
        }
    }

    var body: some View {
        let totalBtc = model.dcaEntries.reduce(0) { $0 + $1.amountBtc }
        let totalCost = model.dcaEntries.reduce(0) { $0 + $1.costUsd }
        let avg = totalBtc > 0 ? totalCost / totalBtc : 0
        let livePrice = currentBtcPrice
        let currentValue = (livePrice ?? 0) * totalBtc
        let pnlUsd = (livePrice != nil) ? (currentValue - totalCost) : nil
        let pnlPct = (livePrice != nil && totalCost > 0) ? ((currentValue - totalCost) / totalCost) * 100 : nil

        return WatermarkBackground {
            if !isUnlocked {
                lockedView
            } else {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Live BTC (USD)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if isLoadingPrice {
                                    ProgressView().scaleEffect(0.9)
                                } else if let p = currentBtcPrice {
                                    Text(p, format: .currency(code: "USD"))
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("—")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            if let lastPriceUpdated {
                                Text("Last price update: \(lastPriceUpdated)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            TextField("Amount (BTC)", text: $amountInput)
                                .keyboardType(.decimalPad)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                                .focused($focusedField, equals: .amount)

                            HStack {
                                TextField("Price paid (USD)", text: $priceInput)
                                    .keyboardType(.decimalPad)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled(true)
                                    .focused($focusedField, equals: .price)

                                Button {
                                    if let p = currentBtcPrice {
                                        priceInput = String(format: "%.2f", p)
                                        inputError = nil
                                    }
                                } label: {
                                    Image(systemName: "arrow.down.to.line.compact")
                                }
                                .buttonStyle(.bordered)
                                .help("Use current BTC price")
                                .disabled(currentBtcPrice == nil)
                            }

                            if let inputError {
                                Text(inputError).foregroundStyle(.red)
                            }

                            Button("Add Buy") { addEntry() }
                                .frame(maxWidth: .infinity)
                        }
                    }

                    Section("Totals") {
                        if model.satsMode {
                            let sats = model.btcToSats(totalBtc)
                            Text("Total: \(model.formatSats(sats)) sats")
                        } else {
                            Text("Total BTC: \(model.formatBtc(totalBtc))")
                        }
                        Text("Total Cost: \(totalCost, format: .currency(code: "USD"))")
                        Text("Average Cost: \(avg, format: .currency(code: "USD"))")

                        if let p = currentBtcPrice {
                            Text("Current Value: \(currentValue, format: .currency(code: "USD"))")
                            if let pnlUsd, let pnlPct {
                                let isUp = pnlUsd >= 0
                                Text("P/L: \(isUp ? "+" : "")\(pnlUsd, specifier: "%.2f") USD (\(isUp ? "+" : "")\(pnlPct, specifier: "%.2f")%)")
                                    .foregroundStyle(isUp ? Color.btcOrange : Color.red)
                            }
                        } else {
                            Text("Current Value: —")
                                .foregroundStyle(.secondary)
                            Text("P/L: —")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section("Allocation") {
                        // Bucket buys by price ranges for quick insight.
                        let bucketSize: Double = 10_000
                        let grouped = Dictionary(grouping: model.dcaEntries) { e -> Int in
                            Int(floor(e.priceUsd / bucketSize))
                        }
                        let keys = grouped.keys.sorted()

                        if keys.isEmpty {
                            Text("No allocation data yet.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(keys, id: \.self) { k in
                                let lower = Double(k) * bucketSize
                                let upper = lower + bucketSize
                                let entries = grouped[k] ?? []
                                let btc = entries.reduce(0.0) { $0 + $1.amountBtc }
                                let buys = entries.count
                                HStack {
                                    Text("\(lower, format: .currency(code: "USD"))–\(upper, format: .currency(code: "USD"))")
                                        .font(.footnote)
                                    Spacer()
                                    Text("\(btc, specifier: "%.8f") BTC")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                    Text("(\(buys))")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    Section("Recent Buys") {
                        if model.dcaEntries.isEmpty {
                            Text("No buys yet. Add your first entry above.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(model.dcaEntries.sorted(by: { $0.timestamp > $1.timestamp })) { e in
                                VStack(alignment: .leading, spacing: 4) {
                                    if model.satsMode {
                                        let sats = model.btcToSats(e.amountBtc)
                                        Text("\(model.formatSats(sats)) sats @ \(e.priceUsd, format: .currency(code: "USD"))")
                                            .font(.subheadline)
                                    } else {
                                        Text("\(e.amountBtc, specifier: "%.8f") BTC @ \(e.priceUsd, format: .currency(code: "USD"))")
                                            .font(.subheadline)
                                    }
                                    Text("Cost: \(e.costUsd, format: .currency(code: "USD")) • \(Self.dateFormatter.string(from: e.date))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture { startEditing(e) }
                            }
                            .onDelete(perform: deleteEntries)
                        }
                    }
                }
            }
        }
        .navigationTitle("DCA")
        .task {
            await refreshLivePriceIfNeeded(force: false)
        }
        .onAppear {
            // Auto-refresh every 60s while visible, but skip if we fetched recently.
            autoRefreshTask?.cancel()
            autoRefreshTask = Task {
                while !Task.isCancelled {
                    await refreshLivePriceIfNeeded(force: false)
                    try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
                }
            }
        }
        .onDisappear {
            autoRefreshTask?.cancel()
            autoRefreshTask = nil
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Export Format", selection: $exportFormat) {
                        ForEach(ExportFormat.allCases) { f in
                            Text(f.rawValue).tag(f)
                        }
                    }

                    Button("Export DCA") {
                        showExporter = true
                    }

                    Button("Import DCA") {
                        showImporter = true
                    }

                    if let pendingImportCount {
                        Text("Imported \(pendingImportCount) entries")
                    }

                    if let importError {
                        Text(importError)
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Export / Import")
            }

            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
            }
        }
        .refreshable {
            await refreshLivePriceIfNeeded(force: true)
        }
        .fileExporter(
            isPresented: $showExporter,
            document: makeExportDocument(),
            contentType: exportFormat == .json ? .json : .commaSeparatedText,
            defaultFilename: exportFormat == .json ? "btc_dca_backup" : "btc_dca_backup"
        ) { result in
            // no-op; Share sheet handles completion
            if case .failure(let err) = result {
                importError = "Export failed: \(err.localizedDescription)"
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.json, .commaSeparatedText, .plainText]
        ) { result in
            do {
                let url = try result.get()
                let data = try Data(contentsOf: url)
                handleImportedData(data, suggestedName: url.lastPathComponent)
            } catch {
                importError = "Import failed: \(error.localizedDescription)"
            }
        }
        .sheet(item: $editingEntry) { entry in
            NavigationView {
                Form {
                    Section("Edit Buy") {
                        TextField("Amount (BTC)", text: $editAmountInput)
                            .keyboardType(.decimalPad)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)

                        TextField("Price (USD)", text: $editPriceInput)
                            .keyboardType(.decimalPad)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)

                        DatePicker("Date", selection: $editDate, displayedComponents: [.date, .hourAndMinute])

                        if let editError {
                            Text(editError)
                                .foregroundStyle(.red)
                        }
                    }

                    Section {
                        Button("Save") { applyEdits() }
                            .frame(maxWidth: .infinity)

                        Button("Cancel") {
                            editingEntry = nil
                            editError = nil
                        }
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.secondary)
                    }

                    Section {
                        Button("Delete This Entry") {
                            model.dcaEntries.removeAll { $0.id == entry.id }
                            editingEntry = nil
                        }
                        .foregroundStyle(.red)
                    }
                }
                .navigationTitle("Edit")
                .navigationBarTitleDisplayMode(.inline)
            }
            .onAppear {
                // Ensure fields reflect the selected entry (in case sheet opened via old state)
                startEditing(entry)
            }
        }
    }
    private func makeExportDocument() -> DcaExportDocument {
        switch exportFormat {
        case .json:
            let data = (try? JSONEncoder().encode(model.dcaEntries)) ?? Data()
            return DcaExportDocument(data: data)
        case .csv:
            let csv = makeCSV(entries: model.dcaEntries)
            return DcaExportDocument(data: Data(csv.utf8))
        }
    }
    private func makeCSV(entries: [DcaEntry]) -> String {
        var lines: [String] = []
        lines.append("id,amount_btc,price_usd,timestamp")
        for e in entries {
            // Use invariant formatting (dot decimals)
            let id = e.id.uuidString
            let amt = String(format: "%.8f", e.amountBtc)
            let price = String(format: "%.2f", e.priceUsd)
            let ts = String(format: "%.0f", e.timestamp)
            lines.append("\(id),\(amt),\(price),\(ts)")
        }
        return lines.joined(separator: "\n")
    }

    private func parseCSV(_ text: String) -> [DcaEntry] {
        let rows = text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !rows.isEmpty else { return [] }

        // Support optional header
        let startIndex: Int = rows.first?.lowercased().contains("amount_btc") == true ? 1 : 0

        var out: [DcaEntry] = []
        out.reserveCapacity(max(0, rows.count - startIndex))

        for i in startIndex..<rows.count {
            let parts = rows[i].split(separator: ",").map { String($0) }
            guard parts.count >= 4 else { continue }
            let id = UUID(uuidString: parts[0]) ?? UUID()
            let amt = Double(parts[1]) ?? 0
            let price = Double(parts[2]) ?? 0
            let ts = Double(parts[3]) ?? Date().timeIntervalSince1970
            guard amt > 0, price > 0 else { continue }
            out.append(DcaEntry(id: id, amountBtc: amt, priceUsd: price, timestamp: ts))
        }
        return out
    }

    private func applyEdits() {
        guard let editingEntry else { return }
        guard let a = Double(editAmountInput), let p = Double(editPriceInput), a > 0, p > 0 else {
            editError = "Invalid input"
            return
        }
        let updated = DcaEntry(id: editingEntry.id, amountBtc: a, priceUsd: p, timestamp: editDate.timeIntervalSince1970)
        if let idx = model.dcaEntries.firstIndex(where: { $0.id == editingEntry.id }) {
            model.dcaEntries[idx] = updated
        }
        self.editError = nil
        self.editingEntry = nil
    }

    private func startEditing(_ entry: DcaEntry) {
        editingEntry = entry
        editAmountInput = String(format: "%.8f", entry.amountBtc)
        editPriceInput = String(format: "%.2f", entry.priceUsd)
        editDate = entry.date
        editError = nil
    }

    private func handleImportedData(_ data: Data, suggestedName: String?) {
        // Try JSON first, then CSV.
        if let decoded = try? JSONDecoder().decode([DcaEntry].self, from: data), !decoded.isEmpty {
            model.dcaEntries = decoded
            pendingImportCount = decoded.count
            importError = nil
            return
        }

        if let text = String(data: data, encoding: .utf8) {
            let parsed = parseCSV(text)
            if !parsed.isEmpty {
                model.dcaEntries = parsed
                pendingImportCount = parsed.count
                importError = nil
                return
            }
        }

        importError = "Could not import file. Use JSON export from this app or a CSV with columns: id,amount_btc,price_usd,timestamp"
    }

    private func deleteEntries(at offsets: IndexSet) {
        // We displayed a sorted list; delete by matching IDs.
        let sorted = model.dcaEntries.sorted(by: { $0.timestamp > $1.timestamp })
        let idsToDelete = offsets.compactMap { sorted[$0].id }
        model.dcaEntries.removeAll { idsToDelete.contains($0.id) }
    }

    private func refreshLivePriceIfNeeded(force: Bool) async {
        // Throttle to avoid 429s / unnecessary calls.
        if !force, let last = lastPriceFetchAt, Date().timeIntervalSince(last) < 60 {
            return
        }
        if !force, isLoadingPrice { return }

        isLoadingPrice = true
        defer { isLoadingPrice = false }

        do {
            let p = try await CoinGeckoClient.fetchBtcSpot(vsCurrency: "USD")
            currentBtcPrice = p
            lastPriceFetchAt = Date()

            let df = DateFormatter()
            df.dateFormat = "HH:mm:ss"
            lastPriceUpdated = df.string(from: Date())
        } catch {
            // Keep the DCA screen functional even if price fetch fails.
            if currentBtcPrice == nil {
                currentBtcPrice = nil
            }
        }
    }

    private func addEntry() {
        guard let a = Double(amountInput), let p = Double(priceInput), a > 0, p > 0 else {
            inputError = "Invalid input"
            return
        }
        model.dcaEntries.append(DcaEntry(amountBtc: a, priceUsd: p))
        amountInput = ""
        priceInput = ""
        inputError = nil
    }
}


struct LearnView: View {
    var body: some View {
        WatermarkBackground {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("What is Bitcoin?")
                        .font(.title3).bold()
                        .foregroundStyle(Color.btcOrange)

                    Text("• Bitcoin is a decentralized digital currency with a fixed supply of 21 million coins.\n• It runs on a peer-to-peer network secured by miners using Proof-of-Work.\n• Transactions are recorded on a public ledger called the blockchain.\n• Bitcoin is divisible into 100,000,000 units called satoshis.\n• Price can be very volatile—never invest more than you can afford to lose.")
                        .font(.body)

                    Text("Primary sources:")
                        .font(.subheadline).bold()
                        .padding(.top, 8)

                    Link("• Bitcoin Whitepaper (Satoshi Nakamoto, 2008)", destination: URL(string: "https://bitcoin.org/bitcoin.pdf")!)
                    Link("• Genesis Block (Block 0) details", destination: URL(string: "https://en.bitcoin.it/wiki/Genesis_block")!)
                    Link("• View Genesis Block on a block explorer", destination: URL(string: "https://blockstream.info/block/000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f")!)

                    Spacer(minLength: 20)
                }
                .padding(20)
            }
            .navigationTitle("Learn")
        }
    }
}

// MARK: - Privacy

struct PrivacyView: View {
    var body: some View {
        WatermarkBackground {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Privacy")
                        .font(.title3).bold()
                        .foregroundStyle(Color.btcOrange)

                    Text("No account. No cloud. Your data stays with you.")
                        .font(.headline)

                    Text("DCA entries")
                        .font(.subheadline).bold()
                        .padding(.top, 6)

                    Text("""
• Stored encrypted in your device Keychain.
• Marked as “ThisDeviceOnly” so it is not synced to iCloud and does not migrate to a new phone via backup/restore.
• Not uploaded to any server.
""")
                    .font(.body)

                    Text("Live price requests")
                        .font(.subheadline).bold()
                        .padding(.top, 6)

                    Text("Live price data is fetched from CoinGecko over the internet. Your DCA entries are not sent with those requests.")
                        .font(.body)

                    Text("What can leave your phone?")
                        .font(.subheadline).bold()
                        .padding(.top, 6)

                    Text("Only what you choose to share — for example screenshots or anything you manually copy/export.")
                        .font(.body)

                    Spacer(minLength: 20)
                }
                .padding(20)
            }
            .navigationTitle("Privacy")
        }
    }
}
// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        WatermarkBackground {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Settings")
                        .font(.title3).bold()
                        .foregroundStyle(Color.btcOrange)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Privacy")
                            .font(.subheadline).bold()

                        Text("No account. No cloud. Your data stays with you.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("Your DCA entries are stored encrypted on your device only (Keychain). They are not synced to iCloud and do not leave your phone unless you choose to share them.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        
                        NavigationLink {
                            PrivacyView()
                        } label: {
                            Text("Learn more")
                                .font(.footnote)
                        }
                    }
                    .padding(.top, 6)

                    Text("Display Currency (Price tab): \(model.currency)")
                        .foregroundStyle(.secondary)

                    Button {
                        model.toggleCurrency()
                    } label: {
                        Text("Toggle Currency (USD / EUR)")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Divider().padding(.vertical, 6)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Units")
                            .font(.subheadline).bold()

                        Toggle(isOn: $model.satsMode) {
                            Text("Sats Mode (show BTC amounts as sats)")
                                .font(.footnote)
                        }

                        Text("Stacking goal: \(model.formatSats(model.satsGoalSats)) sats")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            Button("-100k") {
                                model.satsGoalSats = max(100_000, model.satsGoalSats - 100_000)
                            }
                            .buttonStyle(.bordered)

                            Button("+100k") {
                                model.satsGoalSats = min(2_100_000_000_000_000, model.satsGoalSats + 100_000)
                            }
                            .buttonStyle(.bordered)

                            Spacer()

                            Button("Set 1M") {
                                model.satsGoalSats = 1_000_000
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    Divider().padding(.vertical, 6)

                    Text("Pro Mode (BTC vs Gold & ETH): \(model.isProMode ? "On" : "Off")")
                        .foregroundStyle(.secondary)

                    Button {
                        model.isProMode.toggle()
                    } label: {
                        Text("Toggle Pro Mode")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.btcOrange)

                    Spacer(minLength: 20)
                }
                .padding(20)
            }
            .navigationTitle("Settings")
        }
    }
}

// MARK: - Sparkline (mini chart)
struct Sparkline: View {
    let prices: [Double]

    var body: some View {
        Canvas { context, size in
            guard prices.count >= 2,
                  let maxV = prices.max(),
                  let minV = prices.min() else { return }

            let range = max(maxV - minV, 1e-9)
            let stepX = size.width / CGFloat(prices.count - 1)

            var path = Path()
            for (idx, v) in prices.enumerated() {
                let x = CGFloat(idx) * stepX
                let norm = (v - minV) / range
                let y = size.height - CGFloat(norm) * size.height
                if idx == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(path, with: .color(Color.btcOrange), lineWidth: 2)
        }
        .background(.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Simple Line Chart (SwiftUI Canvas)

struct LineChart: View {
    let prices: [Double]

    var body: some View {
        Canvas { context, size in
            guard prices.count >= 2,
                  let maxV = prices.max(),
                  let minV = prices.min() else { return }

            let range = max(maxV - minV, 1e-9)
            let stepX = size.width / CGFloat(prices.count - 1)

            // grid
            let gridLines = 4
            for i in 0...gridLines {
                let y = size.height * CGFloat(i) / CGFloat(gridLines)
                var p = Path()
                p.move(to: CGPoint(x: 0, y: y))
                p.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(p, with: .color(.secondary.opacity(0.25)), lineWidth: 1)
            }

            // line
            var path = Path()
            for (idx, v) in prices.enumerated() {
                let x = CGFloat(idx) * stepX
                let norm = (v - minV) / range
                let y = size.height - CGFloat(norm) * size.height
                if idx == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(path, with: .color(Color.btcOrange), lineWidth: 3)
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}


