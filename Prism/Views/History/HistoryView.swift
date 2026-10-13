import SwiftUI

struct HistoryView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var entries: [NetworkHistoryEntry] = []
    @State private var confirmsClear = false
    @State private var selectedEntryID: UUID?

    var body: some View {
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
                            ForEach(section.items) { item in
                                switch item {
                                case .single(let entry):
                                    historyRow(entry)
                                case .unstable(_, let flapEntries):
                                    DisclosureGroup {
                                        ForEach(flapEntries) { entry in
                                            historyRow(entry)
                                        }
                                    } label: {
                                        UnstableHistoryRow(
                                            entries: flapEntries,
                                            flagStyle: environment.settings.countryFlagStyle
                                        )
                                    }
                                }
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
        // 使用系统 Sheet：原生出现动画、Esc 关闭与焦点管理。
        .sheet(isPresented: Binding(
            get: { selectedEntry != nil },
            set: { if !$0 { selectedEntryID = nil } }
        )) {
            if let selectedEntry {
                HistoryEntryDetailView(
                    entry: selectedEntry,
                    flagStyle: environment.settings.countryFlagStyle
                ) {
                    selectedEntryID = nil
                }
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

    private func historyRow(_ entry: HistoryDisplayEntry) -> some View {
        HistoryRow(
            displayEntry: entry,
            flagStyle: environment.settings.countryFlagStyle
        )
        .tag(entry.current.id)
        .accessibilityIdentifier("history.entry.\(entry.current.id.uuidString)")
        .accessibilityHint(String(localized: "View exit details"))
        .accessibilityAddTraits(.isButton)
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
        let items = HistoryItem.folding(displayEntries)
        let grouped = Dictionary(grouping: items) {
            calendar.startOfDay(for: $0.latestDate)
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
                items: (grouped[day] ?? []).sorted { $0.latestDate > $1.latestDate }
            )
        }
    }
}

private struct HistorySection: Identifiable {
    let id: Date
    let title: String
    let items: [HistoryItem]
}

struct HistoryDisplayEntry: Identifiable {
    let current: NetworkHistoryEntry
    let previous: NetworkHistoryEntry?
    var id: UUID { current.id }
}

/// 短时间内在出口之间来回切换（A → B → A）折叠为一条“出口不稳定”，避免淹没主历史。
enum HistoryItem: Identifiable {
    case single(HistoryDisplayEntry)
    case unstable(id: UUID, entries: [HistoryDisplayEntry])

    static let flapWindow: TimeInterval = 90

    var id: UUID {
        switch self {
        case .single(let entry): entry.id
        case .unstable(let id, _): id
        }
    }

    var latestDate: Date {
        switch self {
        case .single(let entry): entry.current.recordedAt
        case .unstable(_, let entries): entries.first?.current.recordedAt ?? .distantPast
        }
    }

    /// `chronological` 按时间升序；返回的不稳定分组内部按时间降序。
    static func folding(_ chronological: [HistoryDisplayEntry]) -> [HistoryItem] {
        var items: [HistoryItem] = []
        var run: [HistoryDisplayEntry] = []

        func flush() {
            defer { run.removeAll() }
            guard !run.isEmpty else { return }
            if isFlap(run) {
                items.append(.unstable(id: run[0].id, entries: Array(run.reversed())))
            } else {
                items.append(contentsOf: run.map(HistoryItem.single))
            }
        }

        for entry in chronological {
            if let last = run.last,
               entry.current.recordedAt.timeIntervalSince(last.current.recordedAt) > flapWindow {
                flush()
            }
            run.append(entry)
        }
        flush()
        return items
    }

    static func isFlap(_ run: [HistoryDisplayEntry]) -> Bool {
        guard run.count >= 3 else { return false }
        for index in 2..<run.count {
            let returning = run[index].current
            if run[0..<(index - 1)].contains(where: { $0.current.representsSameExit(as: returning) }) {
                return true
            }
        }
        return false
    }
}

private struct UnstableHistoryRow: View {
    let entries: [HistoryDisplayEntry]
    let flagStyle: CountryFlagStyle

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                CountryFlagView(
                    countryCode: entries.first?.current.countryCode ?? "",
                    style: flagStyle,
                    diameter: 22,
                    containerSize: CGSize(width: 30, height: 30)
                )
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(2.5)
                    .background(StatusPalette.confirming, in: Circle())
                    .offset(x: 2, y: 2)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "Unstable exit"))
                    .font(.subheadline.weight(.semibold))
                Text(summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let newest = entries.first?.current.recordedAt,
               let oldest = entries.last?.current.recordedAt {
                Text("\(oldest.formatted(date: .omitted, time: .shortened)) – \(newest.formatted(date: .omitted, time: .shortened))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .help(String(localized: "The exit switched back and forth within a short time"))
        .accessibilityElement(children: .combine)
    }

    private var summary: String {
        let countText = String(format: String(localized: "%lld changes"), Int64(entries.count))
        var seen: [String] = []
        for entry in entries.reversed() {
            let code = entry.current.countryCode.uppercased()
            let label = entry.current.city.map { "\(code) \($0)" } ?? code
            if !seen.contains(label) { seen.append(label) }
        }
        return "\(countText) · \(seen.joined(separator: " ⇄ "))"
    }
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
