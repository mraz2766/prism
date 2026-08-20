import Foundation
import OSLog

actor NetworkHistoryStore {
    private let fileURL: URL
    private let maximumEntries: Int
    private let settlingDelay: Duration
    private var entries: [NetworkHistoryEntry]
    private var pendingEntry: PendingEntry?
    private var pendingTask: Task<Void, Never>?
    private var continuations: [UUID: AsyncStream<[NetworkHistoryEntry]>.Continuation] = [:]
    private let logger = Logger(subsystem: "com.mraz.prism", category: "history")

    init(
        fileURL: URL? = nil,
        maximumEntries: Int = 100,
        settlingDelay: Duration = .seconds(3),
        initialEntries: [NetworkHistoryEntry]? = nil
    ) {
        let resolvedURL = fileURL ?? Self.defaultURL()
        let loadedEntries = initialEntries ?? Self.load(from: resolvedURL)
        let trimmedEntries = loadedEntries.count > maximumEntries
            ? Array(loadedEntries.suffix(maximumEntries))
            : loadedEntries
        self.fileURL = resolvedURL
        self.maximumEntries = maximumEntries
        self.settlingDelay = settlingDelay
        self.entries = trimmedEntries
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
        if let last = entries.last, last.representsSameExit(as: info) {
            cancelPendingEntry()
            return false
        }
        if let pendingEntry, pendingEntry.entry.representsSameExit(as: info) {
            return false
        }

        let entry = NetworkHistoryEntry(recordedAt: date, info: info)
        guard !entries.isEmpty, settlingDelay > .zero else {
            cancelPendingEntry()
            commit(entry)
            return true
        }

        cancelPendingEntry()
        let id = UUID()
        pendingEntry = PendingEntry(id: id, entry: entry)
        let delay = settlingDelay
        pendingTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            await self?.commitPendingEntry(id: id)
        }
        return true
    }

    private func commit(_ entry: NetworkHistoryEntry) {
        entries.append(entry)
        if entries.count > maximumEntries {
            entries.removeFirst(entries.count - maximumEntries)
        }
        persist()
        emit()
    }

    func clear() {
        cancelPendingEntry()
        entries.removeAll()
        persist()
        emit()
    }

    private func commitPendingEntry(id: UUID) {
        guard let pendingEntry, pendingEntry.id == id else { return }
        self.pendingEntry = nil
        pendingTask = nil
        guard entries.last?.representsSameExit(as: pendingEntry.entry) != true else { return }
        commit(pendingEntry.entry)
    }

    private func cancelPendingEntry() {
        pendingTask?.cancel()
        pendingTask = nil
        pendingEntry = nil
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

    private struct PendingEntry {
        let id: UUID
        let entry: NetworkHistoryEntry
    }
}
