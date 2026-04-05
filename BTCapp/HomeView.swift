import SwiftUI

// MARK: - Home

struct HomeView: View {
    @Environment(AppModel.self) private var model

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
