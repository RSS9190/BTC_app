// Config.swift
//
// API keys and environment configuration.
//
// For App Store distribution, do NOT ship the key in source.
// Instead:
//   1. Create BTCapp.xcconfig with:  COINGECKO_API_KEY = CG-...
//   2. Add $(COINGECKO_API_KEY) to Info.plist under key "CoinGeckoApiKey"
//   3. Read at runtime: Bundle.main.object(forInfoDictionaryKey: "CoinGeckoApiKey") as? String
//   4. Add BTCapp.xcconfig to .gitignore
//
// Until then, the demo key below is for local / TestFlight use only.

import Foundation

enum AppConfig {
    static let coinGeckoApiKey = "CG-26iJ5q61kFYj2tArmQXg1Bf8"
}
