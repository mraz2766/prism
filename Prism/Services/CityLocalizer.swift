import Foundation
import Observation

/// 把在线归属地返回的英文城市名统一翻译成中文，供弹窗、概览、历史、菜单栏和通知共用。
/// 翻译按“国家代码 + 英文城市名”缓存在本机，同一城市只查询一次。
@MainActor
@Observable
final class CityLocalizer {
    typealias Lookup = @Sendable (_ ipAddress: String) async -> (countryCode: String, city: String)?

    private(set) var names: [String: String]

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let lookup: Lookup?
    @ObservationIgnored private let locale: @MainActor () -> Locale
    @ObservationIgnored private var inFlight: Set<String> = []
    @ObservationIgnored private var failedAt: [String: Date] = [:]
    private static let storageKey = "cityLocalizer.zhNames"
    private static let maximumEntries = 300

    init(
        defaults: UserDefaults = .standard,
        locale: @escaping @MainActor () -> Locale = { .autoupdatingCurrent },
        lookup: Lookup? = CityLocalizer.onlineLookup
    ) {
        self.defaults = defaults
        self.locale = locale
        self.lookup = lookup
        names = defaults.dictionary(forKey: Self.storageKey) as? [String: String] ?? [:]
    }

    static let onlineLookup: Lookup = { ipAddress in
        guard let result = try? await IPWhoIsGeoProvider(language: "zh-CN").lookup(ipAddress: ipAddress),
              let city = result.location.city, !city.isEmpty else { return nil }
        return (result.location.countryCode, city)
    }

    private var usesChinese: Bool {
        locale().language.languageCode?.identifier == "zh"
    }

    private static func key(countryCode: String, city: String) -> String {
        "\(countryCode.uppercased())|\(city.lowercased())"
    }

    /// 返回界面应显示的城市名：中文环境下优先使用已知译名，否则原样返回。
    func displayCity(_ city: String?, countryCode: String) -> String? {
        guard let city, !city.isEmpty else { return nil }
        let cached = names[Self.key(countryCode: countryCode, city: city)]
        return LocalizedCityName.chineseName(
            for: city,
            countryCode: countryCode,
            localizedCity: cached,
            locale: locale()
        ) ?? city
    }

    func displayCity(for info: NetworkInfo) -> String? {
        displayCity(info.location.city, countryCode: info.location.countryCode)
    }

    /// 出口确认且在线归属地可用时，按需补一次中文城市名。
    func resolveIfNeeded(for status: NetworkStatus) {
        guard usesChinese, let lookup,
              case .online(let info) = status,
              info.hasLocation,
              info.locationSource == .online,
              let city = info.location.city, !city.isEmpty,
              let address = info.addresses.preferredForLookup else { return }
        let countryCode = info.location.countryCode
        let key = Self.key(countryCode: countryCode, city: city)
        guard names[key] == nil, !inFlight.contains(key) else { return }
        if let failed = failedAt[key], Date.now.timeIntervalSince(failed) < 300 { return }
        inFlight.insert(key)
        Task { [weak self] in
            let result = await lookup(address)
            guard let self else { return }
            self.inFlight.remove(key)
            guard let result,
                  result.countryCode.uppercased() == countryCode.uppercased() else {
                self.failedAt[key] = .now
                return
            }
            self.store(result.city, for: key)
        }
    }

    private func store(_ city: String, for key: String) {
        let simplified = city
            .applyingTransform(StringTransform(rawValue: "Traditional-Simplified"), reverse: false) ?? city
        var next = names
        if next.count >= Self.maximumEntries, let victim = next.keys.sorted().first {
            next.removeValue(forKey: victim)
        }
        next[key] = simplified
        names = next
        defaults.set(next, forKey: Self.storageKey)
    }
}
