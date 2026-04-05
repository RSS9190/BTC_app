import SwiftUI

extension Color {
    static let btcOrange = Color(red: 0.97, green: 0.58, blue: 0.10) // #F7931A
}

// MARK: - Root

struct ContentView: View {
    @State private var model = AppModel.shared

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView {
                NavigationStack { HomeView() }
                    .environment(model)
                    .tabItem { Label("Home", systemImage: "house") }

                NavigationStack { PriceView() }
                    .environment(model)
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

                NavigationStack { DcaView() }
                    .environment(model)
                    .tabItem { Label("DCA", systemImage: "chart.line.uptrend.xyaxis") }

                NavigationStack { LearnView() }
                    .environment(model)
                    .tabItem { Label("Learn", systemImage: "book.fill") }

                NavigationStack { SettingsView() }
                    .environment(model)
                    .tabItem { Label("Settings", systemImage: "gearshape") }
            }
            .tint(Color.btcOrange)

            Rectangle()
                .frame(height: 60)
                .background { Color.clear.background(.ultraThinMaterial) }
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
                .zIndex(-1)
        }
        .preferredColorScheme(.dark)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
