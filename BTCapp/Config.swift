// Config.swift
//
// API keys and environment configuration.
//
// Keys are not stored in source: they live in Secrets.swift, which is
// gitignored. On a fresh checkout, copy Secrets.swift.example to
// Secrets.swift and fill in your own key — the build fails with
// "cannot find 'Secrets'" until you do.

import Foundation

enum AppConfig {
    static let coinGeckoApiKey = Secrets.coinGeckoApiKey
}
