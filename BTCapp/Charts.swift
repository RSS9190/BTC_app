import SwiftUI

// MARK: - Monthly Bar Chart

struct MonthlyChart: View {
    let entries: [DcaEntry]
    let satsMode: Bool
    let formatSats: (Int64) -> String

    private var monthlyData: [(label: String, btc: Double)] {
        guard !entries.isEmpty else { return [] }
        let cal = Calendar.current
        let df = DateFormatter()
        df.dateFormat = "MMM ''yy"

        let grouped = Dictionary(grouping: entries) { e -> DateComponents in
            cal.dateComponents([.year, .month], from: e.date)
        }

        return grouped.keys
            .sorted { ($0.year ?? 0, $0.month ?? 0) < ($1.year ?? 0, $1.month ?? 0) }
            .compactMap { key -> (String, Double)? in
                guard let date = cal.date(from: key) else { return nil }
                let btc = (grouped[key] ?? []).reduce(0.0) { $0 + $1.amountBtc }
                return (df.string(from: date), btc)
            }
    }

    var body: some View {
        let data = monthlyData
        if data.isEmpty {
            Text("No monthly data yet.")
                .foregroundStyle(.secondary)
        } else {
            let maxBtc = data.map(\.btc).max() ?? 1
            VStack(alignment: .leading, spacing: 6) {
                ForEach(data, id: \.label) { item in
                    HStack(spacing: 8) {
                        Text(item.label)
                            .font(.caption)
                            .frame(width: 60, alignment: .leading)

                        GeometryReader { geo in
                            let barWidth = max(CGFloat(item.btc / maxBtc) * geo.size.width, 4)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.btcOrange)
                                .frame(width: barWidth, height: 16)
                        }
                        .frame(height: 16)

                        if satsMode {
                            let sats = Int64((item.btc * 100_000_000).rounded())
                            Text("\(formatSats(sats)) sats")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("\(item.btc, specifier: "%.8f")")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Sparkline (mini tab chart)

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

// MARK: - Line Chart (SwiftUI Canvas)

struct LineChart: View {
    let prices: [Double]

    var body: some View {
        Canvas { context, size in
            guard prices.count >= 2,
                  let maxV = prices.max(),
                  let minV = prices.min() else { return }

            let range = max(maxV - minV, 1e-9)
            let stepX = size.width / CGFloat(prices.count - 1)

            // Grid lines
            let gridLines = 4
            for i in 0...gridLines {
                let y = size.height * CGFloat(i) / CGFloat(gridLines)
                var p = Path()
                p.move(to: CGPoint(x: 0, y: y))
                p.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(p, with: .color(.secondary.opacity(0.25)), lineWidth: 1)
            }

            // Price line
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
