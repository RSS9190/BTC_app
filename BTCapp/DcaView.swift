import SwiftUI
import LocalAuthentication
import UniformTypeIdentifiers

// MARK: - DCA

struct DcaView: View {
    @Environment(AppModel.self) private var model

    @State private var amountInput = ""
    @State private var priceInput = ""
    @State private var inputError: String?

    // Edit flow
    @State private var editingEntry: DcaEntry?
    @State private var editAmountInput = ""
    @State private var editPriceInput = ""
    @State private var editDate = Date()
    @State private var editError: String?

    // Export / Import
    private enum ExportFormat: String, CaseIterable, Identifiable {
        case json = "JSON"
        case csv = "CSV"
        var id: String { rawValue }
    }
    @State private var exportFormat: ExportFormat = .json
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var importError: String?
    @State private var pendingImportCount: Int?
    @State private var pendingImport: [DcaEntry]?
    @State private var showImportConfirm = false

    private enum Field: Hashable { case amount, price }
    @FocusState private var focusedField: Field?

    @State private var isUnlocked = false
    @State private var authError: String?
    @State private var currentBtcPrice: Double?
    @State private var isLoadingPrice = false
    @State private var lastPriceUpdated: String?
    @State private var lastPriceFetchAt: Date?
    @State private var autoRefreshTask: Task<Void, Never>?
    @State private var lastActivityDate = Date()

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df
    }()

    private static let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.timeStyle = .medium
        return df
    }()

    // MARK: - Locked View

    private var lockedView: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.fill")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(Color.btcOrange)

            Text("DCA is locked")
                .font(.title3).bold()

            Text("Unlock with Face ID / Touch ID (or passcode). Your entries never leave this device.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if let authError {
                Text(authError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Button("Unlock") { authenticate() }
                .buttonStyle(.borderedProminent)
                .tint(Color.btcOrange)
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { if !isUnlocked { authenticate() } }
    }

    private func authenticate() {
        let context = LAContext()
        var error: NSError?
        let canBio = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        let policy: LAPolicy = canBio ? .deviceOwnerAuthenticationWithBiometrics : .deviceOwnerAuthentication

        context.evaluatePolicy(policy, localizedReason: "Unlock your DCA entries") { success, err in
            DispatchQueue.main.async {
                if success { isUnlocked = true }
                else { authError = err?.localizedDescription ?? "Authentication failed" }
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var inputSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Live BTC (\(model.currency))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if isLoadingPrice {
                        ProgressView().scaleEffect(0.9)
                    } else if let p = currentBtcPrice {
                        Text(p, format: .currency(code: model.currency))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("—")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if let lastPriceUpdated {
                    Text("Last price update: \(lastPriceUpdated)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                TextField("Amount (BTC)", text: $amountInput)
                    .keyboardType(.decimalPad)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .focused($focusedField, equals: .amount)

                HStack {
                    let priceLabel = "Price paid (\(model.currency))"
                    TextField(priceLabel, text: $priceInput)
                        .keyboardType(.decimalPad)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .focused($focusedField, equals: .price)

                    Button {
                        if let p = currentBtcPrice {
                            priceInput = String(format: "%.2f", p)
                            inputError = nil
                        }
                    } label: {
                        Image(systemName: "arrow.down.to.line.compact")
                    }
                    .buttonStyle(.bordered)
                    .help("Use current BTC price")
                    .disabled(currentBtcPrice == nil)
                }

                if let inputError {
                    Text(inputError).foregroundStyle(.red)
                }

                Button("Add Buy") { addEntry() }
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private var totalsSection: some View {
        let totalBtc = model.dcaEntries.reduce(0) { $0 + $1.amountBtc }
        let totalCost = model.dcaEntries.reduce(0) { $0 + $1.costUsd }
        let avg = totalBtc > 0 ? totalCost / totalBtc : 0
        let currentValue = (currentBtcPrice ?? 0) * totalBtc

        Section("Totals") {
            if model.satsMode {
                let sats = model.btcToSats(totalBtc)
                Text("Total: \(model.formatSats(sats)) sats")
            } else {
                Text("Total BTC: \(model.formatBtc(totalBtc))")
            }
            Text("Total Cost: \(totalCost, format: .currency(code: model.currency))")
            Text("Average Cost: \(avg, format: .currency(code: model.currency))")

            if currentBtcPrice != nil {
                Text("Current Value: \(currentValue, format: .currency(code: model.currency))")
                let pnlUsd = currentValue - totalCost
                let pnlPct = totalCost > 0 ? ((currentValue - totalCost) / totalCost) * 100 : 0.0
                let isUp = pnlUsd >= 0
                let arrow = isUp ? "↑" : "↓"
                Text("P/L: \(arrow) \(isUp ? "+" : "")\(pnlUsd, specifier: "%.2f") \(model.currency) (\(isUp ? "+" : "")\(pnlPct, specifier: "%.2f")%)")
                    .foregroundStyle(isUp ? Color.btcOrange : Color.red)
            } else {
                Text("Current Value: —").foregroundStyle(.secondary)
                Text("P/L: —").foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var allocationSection: some View {
        Section("Allocation") {
            let bucketSize: Double = 10_000
            let grouped = Dictionary(grouping: model.dcaEntries) { e -> Int in
                Int(floor(e.priceUsd / bucketSize))
            }
            let keys = grouped.keys.sorted()

            if keys.isEmpty {
                Text("No allocation data yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(keys, id: \.self) { k in
                    let lower = Double(k) * bucketSize
                    let upper = lower + bucketSize
                    let entries = grouped[k] ?? []
                    let btc = entries.reduce(0.0) { $0 + $1.amountBtc }
                    let buys = entries.count
                    HStack {
                        Text("\(lower, format: .currency(code: model.currency))–\(upper, format: .currency(code: model.currency))")
                            .font(.footnote)
                        Spacer()
                        Text("\(btc, specifier: "%.8f") BTC")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text("(\(buys))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var monthlyChartSection: some View {
        Section("Monthly Buys") {
            MonthlyChart(
                entries: model.dcaEntries,
                satsMode: model.satsMode,
                formatSats: model.formatSats
            )
        }
    }

    @ViewBuilder
    private var recentBuysSection: some View {
        Section("Recent Buys") {
            if model.dcaEntries.isEmpty {
                Text("No buys yet. Add your first entry above.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.dcaEntries.sorted(by: { $0.timestamp > $1.timestamp })) { e in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            if model.satsMode {
                                let sats = model.btcToSats(e.amountBtc)
                                Text("\(model.formatSats(sats)) sats @ \(e.priceUsd, format: .currency(code: model.currency))")
                                    .font(.subheadline)
                            } else {
                                Text("\(e.amountBtc, specifier: "%.8f") BTC @ \(e.priceUsd, format: .currency(code: model.currency))")
                                    .font(.subheadline)
                            }
                            Spacer()
                            if let live = currentBtcPrice, e.priceUsd > 0 {
                                let pctChange = ((live - e.priceUsd) / e.priceUsd) * 100
                                let arrow = pctChange >= 0 ? "↑" : "↓"
                                Text("\(arrow) \(pctChange, specifier: "%.1f")%")
                                    .font(.caption2).bold()
                                    .foregroundStyle(pctChange >= 0 ? Color.green : Color.red)
                            }
                        }
                        Text("Cost: \(e.costUsd, format: .currency(code: model.currency)) • \(Self.dateFormatter.string(from: e.date))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { startEditing(e) }
                }
                .onDelete(perform: deleteEntries)
            }
        }
    }

    // MARK: - Body

    var body: some View {
        WatermarkBackground {
            if !isUnlocked {
                lockedView
            } else {
                List {
                    inputSection
                    totalsSection
                    allocationSection
                    monthlyChartSection
                    recentBuysSection
                }
            }
        }
        .navigationTitle("DCA")
        .task {
            await refreshLivePriceIfNeeded(force: false)
        }
        .onAppear {
            // Re-lock if timeout has elapsed
            if model.lockTimeoutMinutes > 0,
               Date().timeIntervalSince(lastActivityDate) > Double(model.lockTimeoutMinutes) * 60 {
                isUnlocked = false
            }
            lastActivityDate = Date()

            // Auto-refresh every 60s while visible
            autoRefreshTask?.cancel()
            autoRefreshTask = Task {
                while !Task.isCancelled {
                    await refreshLivePriceIfNeeded(force: false)
                    try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
                }
            }
        }
        .onDisappear {
            autoRefreshTask?.cancel()
            autoRefreshTask = nil
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Export Format", selection: $exportFormat) {
                        ForEach(ExportFormat.allCases) { f in
                            Text(f.rawValue).tag(f)
                        }
                    }
                    Button("Export DCA") { showExporter = true }
                    Button("Import DCA") { showImporter = true }
                    if let pendingImportCount {
                        Text("Imported \(pendingImportCount) entries")
                    }
                    if let importError {
                        Text(importError)
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Export / Import")
            }

            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
            }
        }
        .refreshable {
            await refreshLivePriceIfNeeded(force: true)
        }
        .fileExporter(
            isPresented: $showExporter,
            document: makeExportDocument(),
            contentType: exportFormat == .json ? .json : .commaSeparatedText,
            defaultFilename: "btc_dca_backup"
        ) { result in
            if case .failure(let err) = result {
                importError = "Export failed: \(err.localizedDescription)"
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.json, .commaSeparatedText, .plainText]
        ) { result in
            do {
                let url = try result.get()
                let data = try Data(contentsOf: url)
                handleImportedData(data, suggestedName: url.lastPathComponent)
            } catch {
                importError = "Import failed: \(error.localizedDescription)"
            }
        }
        .alert("Replace DCA entries?", isPresented: $showImportConfirm) {
            Button("Replace", role: .destructive) {
                if let entries = pendingImport {
                    model.dcaEntries = entries
                    pendingImportCount = entries.count
                    pendingImport = nil
                }
            }
            Button("Cancel", role: .cancel) {
                pendingImport = nil
            }
        } message: {
            let existing = model.dcaEntries.count
            let incoming = pendingImport?.count ?? 0
            Text("This will replace your \(existing) existing entries with \(incoming) imported entries. This cannot be undone.")
        }
        .sheet(item: $editingEntry) { entry in
            NavigationStack {
                Form {
                    Section("Edit Buy") {
                        TextField("Amount (BTC)", text: $editAmountInput)
                            .keyboardType(.decimalPad)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)

                        let editPriceLabel = "Price (\(model.currency))"
                        TextField(editPriceLabel, text: $editPriceInput)
                            .keyboardType(.decimalPad)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)

                        DatePicker("Date", selection: $editDate, in: ...Date(), displayedComponents: [.date, .hourAndMinute])

                        if let editError {
                            Text(editError).foregroundStyle(.red)
                        }
                    }

                    Section {
                        Button("Save") { applyEdits() }
                            .frame(maxWidth: .infinity)

                        Button("Cancel") {
                            editingEntry = nil
                            editError = nil
                        }
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.secondary)
                    }

                    Section {
                        Button("Delete This Entry") {
                            model.dcaEntries.removeAll { $0.id == entry.id }
                            editingEntry = nil
                        }
                        .foregroundStyle(.red)
                    }
                }
                .navigationTitle("Edit")
                .navigationBarTitleDisplayMode(.inline)
            }
            .onAppear { startEditing(entry) }
        }
    }

    // MARK: - Helpers

    private func makeExportDocument() -> DcaExportDocument {
        switch exportFormat {
        case .json:
            let data = (try? JSONEncoder().encode(model.dcaEntries)) ?? Data()
            return DcaExportDocument(data: data)
        case .csv:
            return DcaExportDocument(data: Data(makeCSV(entries: model.dcaEntries).utf8))
        }
    }

    private func makeCSV(entries: [DcaEntry]) -> String {
        var lines = ["id,amount_btc,price_usd,timestamp"]
        for e in entries {
            let amt = String(format: "%.8f", e.amountBtc)
            let price = String(format: "%.2f", e.priceUsd)
            let ts = String(format: "%.0f", e.timestamp)
            lines.append("\(e.id.uuidString),\(amt),\(price),\(ts)")
        }
        return lines.joined(separator: "\n")
    }

    private func parseCSV(_ text: String) -> [DcaEntry] {
        let rows = text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !rows.isEmpty else { return [] }

        let startIndex: Int = rows.first?.lowercased().contains("amount_btc") == true ? 1 : 0
        var out: [DcaEntry] = []
        out.reserveCapacity(max(0, rows.count - startIndex))

        for i in startIndex..<rows.count {
            let parts = rows[i].split(separator: ",").map { String($0) }
            guard parts.count >= 4 else { continue }
            let id = UUID(uuidString: parts[0]) ?? UUID()
            let amt = Double(parts[1]) ?? 0
            let price = Double(parts[2]) ?? 0
            let ts = Double(parts[3]) ?? Date().timeIntervalSince1970
            guard amt > 0, price > 0, amt <= 1000, price <= 1_000_000 else { continue }
            out.append(DcaEntry(id: id, amountBtc: amt, priceUsd: price, timestamp: ts))
        }
        return out
    }

    private func handleImportedData(_ data: Data, suggestedName: String?) {
        if let decoded = try? JSONDecoder().decode([DcaEntry].self, from: data), !decoded.isEmpty {
            pendingImport = decoded
            showImportConfirm = true
            importError = nil
            return
        }
        if let text = String(data: data, encoding: .utf8) {
            let parsed = parseCSV(text)
            if !parsed.isEmpty {
                pendingImport = parsed
                showImportConfirm = true
                importError = nil
                return
            }
        }
        importError = "Could not import file. Use JSON export from this app or a CSV with columns: id,amount_btc,price_usd,timestamp"
    }

    private func deleteEntries(at offsets: IndexSet) {
        let sorted = model.dcaEntries.sorted(by: { $0.timestamp > $1.timestamp })
        let idsToDelete = offsets.compactMap { sorted[$0].id }
        model.dcaEntries.removeAll { idsToDelete.contains($0.id) }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    private func refreshLivePriceIfNeeded(force: Bool) async {
        if !force, let last = lastPriceFetchAt, Date().timeIntervalSince(last) < 60 { return }
        if !force, isLoadingPrice { return }

        isLoadingPrice = true
        defer { isLoadingPrice = false }

        do {
            let p = try await CoinGeckoClient.fetchBtcSpot(vsCurrency: model.currency)
            currentBtcPrice = p
            lastPriceFetchAt = Date()
            lastPriceUpdated = Self.timeFormatter.string(from: Date())
        } catch {
            lastPriceUpdated = "Error fetching price"
        }
    }

    private func addEntry() {
        guard let a = Double(amountInput), let p = Double(priceInput), a > 0, p > 0 else {
            inputError = "Invalid input"
            return
        }
        guard a <= 1000, p <= 1_000_000 else {
            inputError = "Values seem too large"
            return
        }
        model.dcaEntries.append(DcaEntry(amountBtc: a, priceUsd: p))
        lastActivityDate = Date()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        amountInput = ""
        priceInput = ""
        inputError = nil
    }

    private func applyEdits() {
        guard let editingEntry else { return }
        guard let a = Double(editAmountInput), let p = Double(editPriceInput), a > 0, p > 0 else {
            editError = "Invalid input"
            return
        }
        guard a <= 1000, p <= 1_000_000 else {
            editError = "Values seem too large"
            return
        }
        let updated = DcaEntry(id: editingEntry.id, amountBtc: a, priceUsd: p, timestamp: editDate.timeIntervalSince1970)
        if let idx = model.dcaEntries.firstIndex(where: { $0.id == editingEntry.id }) {
            model.dcaEntries[idx] = updated
        }
        self.editError = nil
        self.editingEntry = nil
    }

    private func startEditing(_ entry: DcaEntry) {
        editingEntry = entry
        editAmountInput = String(format: "%.8f", entry.amountBtc)
        editPriceInput = String(format: "%.2f", entry.priceUsd)
        editDate = entry.date
        editError = nil
    }
}
