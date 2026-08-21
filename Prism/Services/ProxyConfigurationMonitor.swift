import Foundation
import SystemConfiguration

@MainActor
final class ProxyConfigurationMonitor {
    enum Event: Equatable, Sendable {
        case changed
    }

    private let debounce: Duration
    private let callbackQueue = DispatchQueue(label: "com.mraz.prism.proxy-configuration")
    private var store: SCDynamicStore?
    private var callbackBox: ProxyConfigurationCallbackBox?
    private var debounceTask: Task<Void, Never>?
    private var continuations: [UUID: AsyncStream<Event>.Continuation] = [:]

    private(set) var isMonitoring = false

    init(debounce: Duration = .milliseconds(120)) {
        self.debounce = debounce
    }

    func start() {
        guard store == nil else { return }

        let box = ProxyConfigurationCallbackBox { [weak self] in
            Task { @MainActor [weak self] in
                self?.receiveChange()
            }
        }
        var context = SCDynamicStoreContext(
            version: 0,
            info: Unmanaged.passUnretained(box).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: SCDynamicStoreCallBack = { _, _, info in
            guard let info else { return }
            Unmanaged<ProxyConfigurationCallbackBox>
                .fromOpaque(info)
                .takeUnretainedValue()
                .notify()
        }
        guard let store = SCDynamicStoreCreate(
            nil,
            "com.mraz.prism.proxy-configuration" as CFString,
            callback,
            &context
        ) else { return }

        let keys = [
            "State:/Network/Global/IPv4",
            "State:/Network/Global/IPv6",
            "State:/Network/Global/DNS",
            "State:/Network/Global/Proxies"
        ] as CFArray
        let patterns = [
            "State:/Network/Service/.*/IPv4",
            "State:/Network/Service/.*/IPv6",
            "State:/Network/Service/.*/Proxies",
            "Setup:/Network/Global/Proxies",
            "Setup:/Network/Service/.*/Proxies"
        ] as CFArray
        guard SCDynamicStoreSetNotificationKeys(store, keys, patterns),
              SCDynamicStoreSetDispatchQueue(store, callbackQueue) else { return }

        callbackBox = box
        self.store = store
        isMonitoring = true
    }

    func stop() {
        debounceTask?.cancel()
        debounceTask = nil
        if let store {
            SCDynamicStoreSetDispatchQueue(store, nil)
        }
        store = nil
        callbackBox = nil
        isMonitoring = false
        continuations.values.forEach { $0.finish() }
        continuations.removeAll()
    }

    func events() -> AsyncStream<Event> {
        AsyncStream { continuation in
            let id = UUID()
            continuations[id] = continuation
            continuation.onTermination = { @Sendable _ in
                Task { @MainActor [weak self] in
                    self?.continuations.removeValue(forKey: id)
                }
            }
        }
    }

    func receiveChange() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: debounce)
                guard !Task.isCancelled else { return }
                continuations.values.forEach { $0.yield(.changed) }
            } catch {
                return
            }
        }
    }
}

private final class ProxyConfigurationCallbackBox: @unchecked Sendable {
    private let handler: @Sendable () -> Void

    init(handler: @escaping @Sendable () -> Void) {
        self.handler = handler
    }

    func notify() {
        handler()
    }
}
