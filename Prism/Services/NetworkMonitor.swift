import Foundation
import Network

@MainActor
final class NetworkMonitor {
    enum Event: Sendable, Equatable {
        case onlineChanged
        case offline
    }

    private let offlineDebounce: Duration
    private let onlineDebounce: Duration
    private let queue = DispatchQueue(label: "com.mraz.prism.network-monitor")
    private var monitor: NWPathMonitor?
    private var continuations: [UUID: AsyncStream<Event>.Continuation] = [:]
    private var debounceTask: Task<Void, Never>?
    private var started = false

    init(
        offlineDebounce: Duration = .milliseconds(300),
        onlineDebounce: Duration = .milliseconds(100)
    ) {
        self.offlineDebounce = offlineDebounce
        self.onlineDebounce = onlineDebounce
    }

    func start() {
        guard !started else { return }
        started = true
        let monitor = NWPathMonitor()
        self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.receiveConnectivity(isSatisfied: path.status == .satisfied)
            }
        }
        monitor.start(queue: queue)
    }

    func stop() {
        debounceTask?.cancel()
        debounceTask = nil
        monitor?.cancel()
        monitor = nil
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

    func receiveConnectivity(isSatisfied: Bool) {
        debounceTask?.cancel()
        let delay = isSatisfied ? onlineDebounce : offlineDebounce
        let event: Event = isSatisfied ? .onlineChanged : .offline
        debounceTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                self?.emit(event)
            } catch {
                return
            }
        }
    }

    private func emit(_ event: Event) {
        continuations.values.forEach { $0.yield(event) }
    }
}
