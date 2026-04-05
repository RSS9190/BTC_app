import SwiftUI
import UniformTypeIdentifiers

// MARK: - DcaEntry

struct DcaEntry: Codable, Identifiable, Hashable {
    let id: UUID
    var amountBtc: Double
    var priceUsd: Double
    /// Unix timestamp (seconds)
    var timestamp: Double

    init(id: UUID = UUID(), amountBtc: Double, priceUsd: Double, timestamp: Double = Date().timeIntervalSince1970) {
        self.id = id
        self.amountBtc = amountBtc
        self.priceUsd = priceUsd
        self.timestamp = timestamp
    }

    var costUsd: Double { amountBtc * priceUsd }
    var date: Date { Date(timeIntervalSince1970: timestamp) }

    private enum CodingKeys: String, CodingKey {
        case id, amountBtc, priceUsd, timestamp
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        self.amountBtc = (try? c.decode(Double.self, forKey: .amountBtc)) ?? 0
        self.priceUsd = (try? c.decode(Double.self, forKey: .priceUsd)) ?? 0
        // Backwards compatibility: older saved entries won't have timestamp
        self.timestamp = (try? c.decode(Double.self, forKey: .timestamp)) ?? Date().timeIntervalSince1970
    }
}

// MARK: - DCA Export/Import Document

struct DcaExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText, .plainText] }
    static var writableContentTypes: [UTType] { [.json, .commaSeparatedText] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
