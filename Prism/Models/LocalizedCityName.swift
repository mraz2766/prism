import Foundation

enum LocalizedCityName {
    static func chineseName(
        for city: String?,
        countryCode: String,
        localizedCity: String?,
        locale: Locale
    ) -> String? {
        guard locale.language.languageCode?.identifier == "zh" else { return nil }

        if countryCode == "JP", city?.caseInsensitiveCompare("Tokyo") == .orderedSame {
            return "东京"
        }

        guard let localizedCity,
              !localizedCity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return localizedCity
            .applyingTransform(StringTransform(rawValue: "Traditional-Simplified"), reverse: false)
            ?? localizedCity
    }
}
