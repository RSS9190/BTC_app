//
//  BTCappTests.swift
//  BTCappTests
//
//  Created by Ron Scanlon on 12/17/25.
//

import Foundation
import Testing
@testable import BTCapp

struct BTCappTests {

    // MARK: - DcaEntry Tests

    @Test func testDcaEntryInit() async throws {
        let entry = DcaEntry(amountBtc: 0.5, priceUsd: 40000.0, timestamp: 1700000000)
        #expect(entry.amountBtc == 0.5)
        #expect(entry.priceUsd == 40000.0)
        #expect(entry.timestamp == 1700000000)
    }

    @Test func testDcaEntryCostUsd() async throws {
        let entry = DcaEntry(amountBtc: 0.25, priceUsd: 60000.0)
        #expect(entry.costUsd == 15000.0)
    }

    @Test func testDcaEntryCostUsdZeroAmount() async throws {
        let entry = DcaEntry(amountBtc: 0, priceUsd: 50000.0)
        #expect(entry.costUsd == 0)
    }

    // MARK: - BTC ↔ Sats Conversion

    @Test func testBtcToSats() async throws {
        let model = AppModel.shared
        #expect(model.btcToSats(1.0) == 100_000_000)
        #expect(model.btcToSats(0.01) == 1_000_000)
        #expect(model.btcToSats(0.00000001) == 1)
        #expect(model.btcToSats(0) == 0)
    }

    // MARK: - Format Sats

    @Test func testFormatSats() async throws {
        let model = AppModel.shared
        #expect(model.formatSats(1_234_567) == "1,234,567")
        #expect(model.formatSats(0) == "0")
        #expect(model.formatSats(100_000_000) == "100,000,000")
        #expect(model.formatSats(1) == "1")
    }

    // MARK: - Average Cost Calculation

    @Test func testAverageCostCalc() async throws {
        let entries = [
            DcaEntry(amountBtc: 0.1, priceUsd: 30000),
            DcaEntry(amountBtc: 0.2, priceUsd: 60000),
        ]
        let totalBtc = entries.reduce(0) { $0 + $1.amountBtc }
        let totalCost = entries.reduce(0) { $0 + $1.costUsd }
        let avg = totalBtc > 0 ? totalCost / totalBtc : 0

        // 0.1 * 30000 = 3000, 0.2 * 60000 = 12000, total = 15000, totalBtc = 0.3
        // avg = 15000 / 0.3 = 50000
        #expect(abs(totalBtc - 0.3) < 1e-10)
        #expect(totalCost == 15000.0)
        #expect(abs(avg - 50000.0) < 1e-6)
    }

    // MARK: - P/L Calculation

    @Test func testPnlCalc() async throws {
        let entries = [
            DcaEntry(amountBtc: 0.5, priceUsd: 40000),
        ]
        let totalBtc = entries.reduce(0) { $0 + $1.amountBtc }
        let totalCost = entries.reduce(0) { $0 + $1.costUsd }

        let livePrice = 50000.0
        let currentValue = livePrice * totalBtc
        let pnl = currentValue - totalCost
        let pnlPct = (pnl / totalCost) * 100

        // 0.5 BTC @ $40k = $20k cost, current value = 0.5 * $50k = $25k
        // P/L = $5k = +25%
        #expect(currentValue == 25000.0)
        #expect(pnl == 5000.0)
        #expect(pnlPct == 25.0)
    }

    @Test func testPnlCalcLoss() async throws {
        let entries = [
            DcaEntry(amountBtc: 1.0, priceUsd: 60000),
        ]
        let totalBtc = entries.reduce(0) { $0 + $1.amountBtc }
        let totalCost = entries.reduce(0) { $0 + $1.costUsd }

        let livePrice = 45000.0
        let currentValue = livePrice * totalBtc
        let pnl = currentValue - totalCost

        // 1.0 BTC @ $60k = $60k, current = $45k, P/L = -$15k
        #expect(pnl == -15000.0)
    }

    // MARK: - JSON Round Trip

    @Test func testJsonRoundTrip() async throws {
        let original = [
            DcaEntry(amountBtc: 0.123, priceUsd: 45000, timestamp: 1700000000),
            DcaEntry(amountBtc: 0.456, priceUsd: 55000, timestamp: 1700100000),
        ]

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode([DcaEntry].self, from: data)

        #expect(decoded.count == 2)
        #expect(decoded[0].amountBtc == original[0].amountBtc)
        #expect(decoded[0].priceUsd == original[0].priceUsd)
        #expect(decoded[0].timestamp == original[0].timestamp)
        #expect(decoded[1].amountBtc == original[1].amountBtc)
    }
}
