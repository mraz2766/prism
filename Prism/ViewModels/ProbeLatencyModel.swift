import Foundation
import Observation

/// 最近一次成功出口探测的往返耗时，做轻度平滑后供界面展示。
@MainActor
@Observable
final class ProbeLatencyModel {
    private(set) var milliseconds: Int?
    @ObservationIgnored private var smoothed: Double?

    func record(_ duration: Duration) {
        let components = duration.components
        let value = Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15
        guard value.isFinite, value >= 0 else { return }
        let next = smoothed.map { $0 * 0.6 + value * 0.4 } ?? value
        smoothed = next
        // 取整到 5ms，避免数字每轮都在跳动。
        let rounded = max(1, Int((next / 5).rounded()) * 5)
        if rounded != milliseconds { milliseconds = rounded }
    }

    func reset() {
        smoothed = nil
        milliseconds = nil
    }

    static func quality(for milliseconds: Int) -> LatencyQuality {
        switch milliseconds {
        case ..<200: .good
        case ..<600: .fair
        default: .poor
        }
    }
}

enum LatencyQuality: Equatable, Sendable {
    case good
    case fair
    case poor
}
