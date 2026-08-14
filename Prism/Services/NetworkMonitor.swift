import Foundation
import Network

@MainActor
final class NetworkMonitor {
    enum Event: Sendable, Equatable {
        case onlineChanged
        case offline
    }

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.mraz.prism.network-monitor")
    private var continuations: [UUID: AsyncStream<Event>.Continuation] = [:]
    private var debounceTask: Task<Void, Never>?
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in self?.handle(path) }
        }
        monitor.start(queue: queue)
    }

    func stop() {
        debounceTask?.cancel()
        monitor.cancel()
        continuations.values.forEach { $0.finish() }
        continuations.removeAll()
        started = false
    }

    func events() -> AsyncStream<Event> {
        AsyncStream { continuation in
            let id = UUID()
            continuations[id] = continuation
            continuation.onTermination = { @Sendable _ in
                Task { @MainActor [weak self] in self?.continuations.removeValue(forKey: id) }
            }
        }
    }

    private func handle(_ path: NWPath) {
        debounceTask?.cancel()
        if path.status != .satisfied {
            emit(.offline)
            return
        }
        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.emit(.onlineChanged)
        }
    }

    private func emit(_ event: Event) {
        continuations.values.forEach { $0.yield(event) }
    }
}
