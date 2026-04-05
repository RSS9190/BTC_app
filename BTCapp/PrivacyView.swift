import SwiftUI

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
• Marked as "ThisDeviceOnly" so it is not synced to iCloud and does not migrate to a new phone via backup/restore.
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
