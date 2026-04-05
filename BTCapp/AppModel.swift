import SwiftUI
import Observation

// MARK: - App State

@Observable
final class AppModel {
    static let shared = AppModel()

    private enum Keys {
        static let proMode = "pro_mode"
        static let currency = "currency"
        static let dcaKeychainKey = "dca_entries_json_device_only"
        static let satsMode = "sats_mode"
        static let satsGoalSats = "sats_goal_sats"
        static let lockTimeoutMinutes = "lock_timeout_minutes"
    }

    var isProMode: Bool {
        didSet { UserDefaults.standard.set(isProMode, forKey: Keys.proMode) }
    }

    var currency: String {
        didSet { UserDefaults.standard.set(currency, forKey: Keys.currency) }
    }

    var satsMode: Bool {
        didSet { UserDefaults.standard.set(satsMode, forKey: Keys.satsMode) }
    }

    var satsGoalSats: Int64 {
        didSet { UserDefaults.standard.set(satsGoalSats, forKey: Keys.satsGoalSats) }
    }

    var lockTimeoutMinutes: Int {
        didSet { UserDefaults.standard.set(lockTimeoutMinutes, forKey: Keys.lockTimeoutMinutes) }
    }

    var dcaEntries: [DcaEntry] = [] {
        didSet { saveDca() }
    }

    // Shared price state for tab sparkline / delta badge
    var btcSpotUsd: Double?
    var btcHistoryLast24hUsd: [Double] = []
    var btc24hChangeUsd: Double?
    var btc24hChangePct: Double?

    private init() {
        self.isProMode = UserDefaults.standard.bool(forKey: Keys.proMode)
        self.currency = UserDefaults.standard.string(forKey: Keys.currency) ?? "USD"
        self.satsMode = UserDefaults.standard.bool(forKey: Keys.satsMode)
        let storedGoal = UserDefaults.standard.object(forKey: Keys.satsGoalSats) as? NSNumber
        self.satsGoalSats = storedGoal?.int64Value ?? 50_000_000
        self.lockTimeoutMinutes = UserDefaults.standard.integer(forKey: Keys.lockTimeoutMinutes)
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
        return (try? JSONDecoder().decode([DcaEntry].self, from: data)) ?? []
    }

    private func saveDca() {
        guard let data = try? JSONEncoder().encode(dcaEntries),
              let json = String(data: data, encoding: .utf8) else { return }
        KeychainStore.setString(json, key: Keys.dcaKeychainKey)
    }
}
