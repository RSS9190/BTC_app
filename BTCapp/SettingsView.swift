import SwiftUI

// MARK: - Settings

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
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

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Display Currency")
                            .font(.subheadline).bold()
                        Picker("Currency", selection: $model.currency) {
                            Text("USD").tag("USD")
                            Text("EUR").tag("EUR")
                        }
                        .pickerStyle(.segmented)
                    }

                    Divider().padding(.vertical, 6)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Units")
                            .font(.subheadline).bold()

                        Toggle(isOn: $model.satsMode) {
                            Text("Sats Mode (show BTC amounts as sats)")
                                .font(.footnote)
                        }

                        Text("Stacking goal (sats):")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        TextField("Stacking goal", value: $model.satsGoalSats, format: .number)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                    }

                    Divider().padding(.vertical, 6)

                    Toggle(isOn: $model.isProMode) {
                        Text("Pro Mode (BTC vs Gold & ETH)")
                            .font(.subheadline).bold()
                    }

                    Divider().padding(.vertical, 6)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Auto-Lock DCA")
                            .font(.subheadline).bold()

                        Text("Re-require Face ID / Touch ID after inactivity.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Picker("Auto-Lock", selection: $model.lockTimeoutMinutes) {
                            Text("Never").tag(0)
                            Text("1 min").tag(1)
                            Text("5 min").tag(5)
                            Text("15 min").tag(15)
                        }
                        .pickerStyle(.segmented)
                    }

                    Spacer(minLength: 20)
                }
                .padding(20)
            }
            .navigationTitle("Settings")
        }
    }
}
