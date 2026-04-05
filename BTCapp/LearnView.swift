import SwiftUI

// MARK: - Learn

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

                    Text("What is Dollar-Cost Averaging?")
                        .font(.title3).bold()
                        .foregroundStyle(Color.btcOrange)
                        .padding(.top, 12)

                    Text("• DCA means investing a fixed amount at regular intervals, regardless of price.\n• Instead of trying to time the market, you buy consistently over time.\n• Your average cost per BTC smooths out volatility — you buy more when prices are low, less when high.\n• This app tracks your average cost so you can see how your DCA strategy is performing.")
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
