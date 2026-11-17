import Foundation

/// 将内部毫秒值统一显示为秒，保留三位小数。
enum LatencyFormat {
    static func seconds(_ milliseconds: Double?) -> String {
        milliseconds.map { String(format: "%.3f", $0 / 1_000) } ?? "—"
    }
}
