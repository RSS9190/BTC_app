import SwiftUI

// MARK: - Price

struct PriceView: View {
    @Environment(AppModel.self) private var model

    @State private var isLoading = false
    @State private var error: String?
    @State private var history: [Double] = []
    @State private var current: Double?
    @State private var lastUpdated: String?
    @State private var lastUpdatedAt: Date?
    @State private var eth: Double?
    @State private var paxg: Double?
    @State private var comparisonsLastFetch: Date?

    @Environment(\.verticalSizeClass) private var vSize

    private var chartHeight: CGFloat {
        (vSize == .compact) ? 120 : 160
    }

    private static let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.timeStyle = .medium
        return df
    }()

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
            .onChange(of: model.isProMode) { _, newValue in
                if newValue {
                    Task { await refreshComparisons(force: false) }
                } else {
                    eth = nil
                    paxg = nil
                }
            }
            .onChange(of: model.currency) { _, _ in
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
            lastUpdated = Self.timeFormatter.string(from: now)

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
            self.error = "Comparisons failed: \(error.localizedDescription)"
        }
    }
}
