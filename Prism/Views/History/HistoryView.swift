import SwiftUI

struct HistoryView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var entries: [NetworkHistoryEntry] = []
    @State private var confirmsClear = false
    @State private var selectedEntryID: UUID?

    var body: some View {
        ZStack {
            Group {
                if entries.isEmpty {
                    ContentUnavailableView(
                        String(localized: "No exit history"),
                        systemImage: "clock.arrow.circlepath",
                        description: Text(String(localized: "Prism records a new item when the public IP, country, or ASN changes."))
                    )
                } else {
                    List(selection: $selectedEntryID) {
                        ForEach(sections) { section in
                            Section(section.title) {
                                ForEach(section.entries) { entry in
                                    HistoryRow(
                                        displayEntry: entry,
                                        flagStyle: environment.settings.countryFlagStyle
                                    )
                                        .tag(entry.current.id)
                                        .accessibilityIdentifier("history.entry.\(entry.current.id.uuidString)")
                                        .accessibilityHint(String(localized: "View exit details"))
                                        .accessibilityAddTraits(.isButton)
                                }
                            }
                        }
                    }
                    .listStyle(.inset)
                }
            }

            if let selectedEntry {
                Color.black.opacity(0.10)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { selectedEntryID = nil }

                HistoryEntryDetailView(
                    entry: selectedEntry,
                    flagStyle: environment.settings.countryFlagStyle
                ) {
                    selectedEntryID = nil
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5))
                )
                .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .animation(.easeOut(duration: 0.14), value: selectedEntryID)
        .onExitCommand { selectedEntryID = nil }
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

    private var selectedEntry: NetworkHistoryEntry? {
        entries.first { $0.id == selectedEntryID }
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
    let flagStyle: CountryFlagStyle

    private var entry: NetworkHistoryEntry { displayEntry.current }

    var body: some View {
        HStack(spacing: 12) {
            CountryFlagView(
                countryCode: entry.countryCode,
                style: flagStyle,
                diameter: 22,
                containerSize: CGSize(width: 30, height: 30)
            )

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
                        .foregroundStyle(.secondary)

                    if let asn = entry.asn {
                        Text(verbatim: "AS\(asn)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.tertiary)
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

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
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

private struct HistoryEntryDetailView: View {
    let entry: NetworkHistoryEntry
    let flagStyle: CountryFlagStyle
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                CountryFlagView(
                    countryCode: entry.countryCode,
                    style: flagStyle,
                    diameter: 36,
                    containerSize: CGSize(width: 48, height: 48)
                )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(location)
                        .font(.title3.weight(.semibold))
                        .accessibilityIdentifier("history.entry.detail")
                    Text(entry.recordedAt.formatted(date: .abbreviated, time: .standard))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 12) {
                detailRow(String(localized: "Public IPv4"), entry.addresses.ipv4 ?? "—", monospaced: true)
                detailRow(String(localized: "Public IPv6"), entry.addresses.ipv6 ?? "—", monospaced: true)
                detailRow(String(localized: "ASN"), entry.asn.map { "AS\($0)" } ?? "—", monospaced: true)
                detailRow(String(localized: "Route"), entry.routeMode.label)
                detailRow(String(localized: "Probe source"), entry.exitSource.label)
            }

            HStack {
                Spacer()
                Button(String(localized: "Close"), action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    @ViewBuilder
    private func detailRow(_ label: String, _ value: String, monospaced: Bool = false) -> some View {
        GridRow {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(value)
                .font(monospaced ? .system(.callout, design: .monospaced) : .callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var location: String {
        let country = Locale.autoupdatingCurrent.localizedString(forRegionCode: entry.countryCode) ?? entry.countryCode
        guard let city = entry.city, !city.isEmpty else { return country }
        return "\(country) · \(city)"
    }
}
