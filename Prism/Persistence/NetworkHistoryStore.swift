import Foundation
import OSLog

actor NetworkHistoryStore {
    private let fileURL: URL
    private let maximumEntries: Int
    private var entries: [NetworkHistoryEntry]
    private var continuations: [UUID: AsyncStream<[NetworkHistoryEntry]>.Continuation] = [:]
    private let logger = Logger(subsystem: "com.mraz.prism", category: "history")

    init(fileURL: URL? = nil, maximumEntries: Int = 100) {
        self.fileURL = fileURL ?? Self.defaultURL()
        self.maximumEntries = maximumEntries
        self.entries = Self.load(from: self.fileURL)
        if entries.count > maximumEntries {
            entries = Array(entries.suffix(maximumEntries))
        }
    }

    nonisolated func stream() -> AsyncStream<[NetworkHistoryEntry]> {
        AsyncStream { continuation in
            let id = UUID()
            Task { await self.register(id: id, continuation: continuation) }
            continuation.onTermination = { @Sendable _ in
                Task { await self.unregister(id: id) }
            }
        }
    }

    func snapshot() -> [NetworkHistoryEntry] { entries }

    @discardableResult
    func recordIfChanged(_ info: NetworkInfo, at date: Date = .now) -> Bool {
        if let last = entries.last, last.representsSameExit(as: info) { return false }
        entries.append(NetworkHistoryEntry(recordedAt: date, info: info))
        if entries.count > maximumEntries {
            entries.removeFirst(entries.count - maximumEntries)
        }
        persist()
        emit()
        return true
    }

    func clear() {
        entries.removeAll()
        persist()
        emit()
    }

    private func register(id: UUID, continuation: AsyncStream<[NetworkHistoryEntry]>.Continuation) {
        continuations[id] = continuation
        continuation.yield(entries)
    }

    private func unregister(id: UUID) {
        continuations.removeValue(forKey: id)
    }

    private func emit() {
        continuations.values.forEach { $0.yield(entries) }
    }

    private func persist() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(entries).write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Unable to save history: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func load(from url: URL) -> [NetworkHistoryEntry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([NetworkHistoryEntry].self, from: data)) ?? []
    }

    private static func defaultURL() -> URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Prism", isDirectory: true)
            .appendingPathComponent("network-history.json")
    }
}
