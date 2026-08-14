import SwiftUI

struct HistoryView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var entries: [NetworkHistoryEntry] = []
    @State private var confirmsClear = false

    var body: some View {
        Group {
            if entries.isEmpty {
                ContentUnavailableView(
                    String(localized: "No exit history"),
                    systemImage: "clock.arrow.circlepath",
                    description: Text(String(localized: "Prism records a new item when the public IP, country, or ASN changes."))
                )
            } else {
                List {
                    ForEach(sections) { section in
                        Section(section.title) {
                            ForEach(section.entries) { entry in
                                HistoryRow(displayEntry: entry)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle(String(localized: "Exit History"))
        .safeAreaInset(edge: .bottom) {
            if !entries.isEmpty {
                HStack {
                    Text(String(localized: "Stored only on this Mac"))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(String(localized: "Clear History"), role: .destructive) { confirmsClear = true }
                }
                .padding(.horizontal, 20).padding(.vertical, 10)
                .background(.bar)
            }
        }
        .confirmationDialog(
            String(localized: "Clear all exit history?"),
            isPresented: $confirmsClear
        ) {
            Button(String(localized: "Clear History"), role: .destructive) {
                Task { await environment.historyStore.clear() }
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "This cannot be undone."))
        }
        .task {
            for await values in environment.historyStore.stream() {
                entries = values.sorted { $0.recordedAt > $1.recordedAt }
            }
        }
    }

    private var sections: [HistorySection] {
        let calendar = Calendar.autoupdatingCurrent
        let chronological = entries.sorted { $0.recordedAt < $1.recordedAt }
        let displayEntries = chronological.enumerated().map { index, entry in
            HistoryDisplayEntry(
                current: entry,
                previous: index > 0 ? chronological[index - 1] : nil
            )
        }
        let grouped = Dictionary(grouping: displayEntries) {
            calendar.startOfDay(for: $0.current.recordedAt)
        }
        return grouped.keys.sorted(by: >).map { day in
            let title: String
            if calendar.isDateInToday(day) {
                title = String(localized: "Today")
            } else if calendar.isDateInYesterday(day) {
                title = String(localized: "Yesterday")
            } else {
                title = day.formatted(date: .abbreviated, time: .omitted)
            }
            return HistorySection(
                id: day,
                title: title,
                entries: (grouped[day] ?? []).sorted { $0.current.recordedAt > $1.current.recordedAt }
            )
        }
    }
}

private struct HistorySection: Identifiable {
    let id: Date
    let title: String
    let entries: [HistoryDisplayEntry]
}

private struct HistoryDisplayEntry: Identifiable {
    let current: NetworkHistoryEntry
    let previous: NetworkHistoryEntry?
    var id: UUID { current.id }
}

private struct HistoryRow: View {
    let displayEntry: HistoryDisplayEntry

    private var entry: NetworkHistoryEntry { displayEntry.current }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
                    )
                Text(CountryFlag.emoji(for: entry.countryCode) ?? "◎")
                    .font(.system(size: 18))
                    .accessibilityLabel(country)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 4) {
                if let previous = previousTransitionLabel {
                    HStack(spacing: 6) {
                        Text(previous)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Image(systemName: "arrow.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.tertiary)
                        Text(location)
                            .font(.subheadline.weight(.semibold))
                    }
                    .lineLimit(1)
                } else {
                    Text(location)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    Text(entry.addresses.preferredForLookup ?? "—")
                        .font(.system(.caption2, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(nsColor: .quaternaryLabelColor).opacity(0.3), in: RoundedRectangle(cornerRadius: 4))

                    if let asn = entry.asn {
                        Text(verbatim: "AS\(asn)")
                            .font(.system(.caption2, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color(nsColor: .quaternaryLabelColor).opacity(0.3), in: RoundedRectangle(cornerRadius: 4))
                    }

                    Text(entry.routeMode.label)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(entry.recordedAt, style: .time)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var country: String {
        Locale.autoupdatingCurrent.localizedString(forRegionCode: entry.countryCode) ?? entry.countryCode
    }

    private var location: String {
        guard let city = entry.city, !city.isEmpty else { return country }
        return "\(country) · \(city)"
    }

    private var previousTransitionLabel: String? {
        guard let previous = displayEntry.previous else { return nil }
        let previousCountry = Locale.autoupdatingCurrent.localizedString(forRegionCode: previous.countryCode) ?? previous.countryCode
        let previousLocation = previous.city.map { "\(previousCountry) · \($0)" } ?? previousCountry
        guard previousLocation != location else { return nil }
        return previousLocation
    }
}
