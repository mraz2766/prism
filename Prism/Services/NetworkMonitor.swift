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
    private var lastPathSignature: PathSignature?

    /// NWPath 会因“昂贵/受限”标记等无关字段反复回调；只有连通性、网卡或网关变化才视为环境变化。
    struct PathSignature: Equatable, Sendable {
        let isSatisfied: Bool
        let interfaces: [String]
        let gateways: [String]

        init(isSatisfied: Bool, interfaces: [String], gateways: [String]) {
            self.isSatisfied = isSatisfied
            self.interfaces = interfaces
            self.gateways = gateways
        }

        init(_ path: NWPath) {
            isSatisfied = path.status == .satisfied
            interfaces = path.availableInterfaces.map { "\($0.name):\($0.type)" }
            gateways = path.gateways.map { "\($0)" }.sorted()
        }
    }

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
            let signature = PathSignature(path)
            Task { @MainActor [weak self] in
                self?.receivePath(signature)
            }
        }
        monitor.start(queue: queue)
    }

    func stop() {
        debounceTask?.cancel()
        debounceTask = nil
        monitor?.cancel()
        monitor = nil
        lastPathSignature = nil
        continuations.values.forEach { $0.finish() }
        continuations.removeAll()
        started = false
    }

    func events() -> AsyncStream<Event> {
        AsyncStream { continuation in
            let id = UUID()
            continuations[id] = continuation
            continuation.onTermination = { @Sendable [weak self] _ in
                Task { @MainActor [weak self] in self?.continuations.removeValue(forKey: id) }
            }
        }
    }

    func receivePath(_ signature: PathSignature) {
        guard signature != lastPathSignature else { return }
        lastPathSignature = signature
        receiveConnectivity(isSatisfied: signature.isSatisfied)
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
