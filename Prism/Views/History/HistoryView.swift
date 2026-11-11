import AppKit
import SwiftUI

struct HistoryView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var entries: [NetworkHistoryEntry] = []
    @State private var confirmsClear = false
    @State private var selectedEntryID: UUID?
    @State private var searchText = ""
    @State private var copiedCSV = false
    @FocusState private var searchFocused: Bool

    private var flagStyle: CountryFlagStyle { environment.settings.countryFlagStyle }

    var body: some View {
        Group {
            if entries.isEmpty {
                ContentUnavailableView(
                    String(localized: "No exit history"),
                    systemImage: "clock.arrow.circlepath",
                    description: Text(String(localized: "Prism records a new item when the public IP, country, or ASN changes."))
                )
            } else {
                VStack(spacing: 0) {
                    searchBar
                    Divider()
                    HStack(spacing: 0) {
                        listContent
                        if let selected = selectedDisplayEntry {
                            Divider()
                            HistoryEntryDetailView(
                                displayEntry: selected,
                                flagStyle: flagStyle,
                                onDelete: { delete(selected.current.id) },
                                onClose: { selectedEntryID = nil }
                            )
                            .frame(width: 270)
                            .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                    .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: selectedEntryID != nil)
                }
            }
        }
        .navigationTitle(String(localized: "Exit History"))
        .safeAreaInset(edge: .bottom) {
            if !entries.isEmpty {
                HStack(spacing: 12) {
                    Text(String(localized: "Stored only on this Mac"))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(verbatim: "\(entries.count) / \(NetworkHistoryStore.defaultMaximumEntries)")
                        .font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                    Spacer()
                    Button {
                        copyCSV()
                    } label: {
                        Label(
                            copiedCSV ? String(localized: "Copied") : String(localized: "Copy as CSV"),
                            systemImage: copiedCSV ? "checkmark" : "tablecells"
                        )
                    }
                    .help(String(localized: "Copy the listed history to the clipboard as CSV"))
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
                if let selectedEntryID, !entries.contains(where: { $0.id == selectedEntryID }) {
                    self.selectedEntryID = nil
                }
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(String(localized: "Search country, city, IP, or ASN"), text: $searchText)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .accessibilityIdentifier("history.search")
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(String(localized: "Clear search"))
                .accessibilityLabel(String(localized: "Clear search"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background {
            // ⌘F 聚焦搜索框。
            Button("") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var listContent: some View {
        let sections = self.sections
        if sections.isEmpty {
            ContentUnavailableView.search(text: searchText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                                    UnstableHistoryRow(entries: flapEntries, flagStyle: flagStyle)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)
            .onDeleteCommand {
                if let selectedEntryID { delete(selectedEntryID) }
            }
        }
    }

    private func historyRow(_ entry: HistoryDisplayEntry) -> some View {
        HistoryRow(displayEntry: entry, flagStyle: flagStyle)
            .tag(entry.current.id)
            .accessibilityIdentifier("history.entry.\(entry.current.id.uuidString)")
            .accessibilityHint(String(localized: "View exit details"))
            .contextMenu {
                if let address = entry.current.addresses.preferredForLookup {
                    Button(String(localized: "Copy IP address")) { Self.copyToPasteboard(address) }
                }
                Button(String(localized: "Delete Record"), role: .destructive) {
                    delete(entry.current.id)
                }
            }
    }

    private func delete(_ id: UUID) {
        if selectedEntryID == id { selectedEntryID = nil }
        Task { await environment.historyStore.remove(id: id) }
    }

    private func copyCSV() {
        let rows = filteredDisplayEntries.sorted { $0.current.recordedAt > $1.current.recordedAt }
        Self.copyToPasteboard(HistoryCSV.make(rows))
        copiedCSV = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            copiedCSV = false
        }
    }

    static func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    /// 按时间升序，并带上前后相邻记录，用于显示“从哪里来”和停留时长。
    private var displayEntries: [HistoryDisplayEntry] {
        HistoryDisplayEntry.make(from: entries)
    }

    private var filteredDisplayEntries: [HistoryDisplayEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return displayEntries }
        let localizer = environment.cityLocalizer
        return displayEntries.filter { entry in
            entry.current.matches(query: query, localizedLocation: entry.current.locationLabel(using: localizer))
        }
    }

    private var selectedDisplayEntry: HistoryDisplayEntry? {
        guard let selectedEntryID else { return nil }
        return displayEntries.first { $0.id == selectedEntryID }
    }

    private var sections: [HistorySection] {
        let calendar = Calendar.autoupdatingCurrent
        let items = HistoryItem.folding(filteredDisplayEntries)
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
    /// 时间上紧随其后的记录；为空表示这是当前仍在使用的出口。
    var next: NetworkHistoryEntry? = nil
    var id: UUID { current.id }

    /// 在该出口停留的时长；最新一条按“至今”计算。
    func dwell(now: Date = .now) -> TimeInterval {
        max(0, (next?.recordedAt ?? now).timeIntervalSince(current.recordedAt))
    }

    var isCurrent: Bool { next == nil }

    static func make(from entries: [NetworkHistoryEntry]) -> [HistoryDisplayEntry] {
        let chronological = entries.sorted { $0.recordedAt < $1.recordedAt }
        return chronological.enumerated().map { index, entry in
            HistoryDisplayEntry(
                current: entry,
                previous: index > 0 ? chronological[index - 1] : nil,
                next: index + 1 < chronological.count ? chronological[index + 1] : nil
            )
        }
    }

    static func dwellLabel(_ interval: TimeInterval) -> String {
        guard interval >= 60 else { return String(localized: "< 1 min") }
        return Duration.seconds(interval.rounded()).formatted(
            .units(allowed: [.days, .hours, .minutes], width: .abbreviated, maximumUnitCount: 2)
        )
    }
}

extension NetworkHistoryEntry {
    func matches(query: String, localizedLocation: String) -> Bool {
        let needle = query.lowercased()
        let haystack = [
            localizedLocation,
            countryCode,
            city,
            addresses.ipv4,
            addresses.ipv6,
            asn.map { "AS\($0)" }
        ]
        return haystack.contains { $0?.lowercased().contains(needle) == true }
    }
}

enum HistoryCSV {
    static let header = "recorded_at,country_code,city,ipv4,ipv6,asn,route,probe_source,dwell_seconds"

    static func make(_ rows: [HistoryDisplayEntry], now: Date = .now) -> String {
        let formatter = ISO8601DateFormatter()
        var lines = [header]
        for row in rows {
            let entry = row.current
            let fields: [String] = [
                formatter.string(from: entry.recordedAt),
                entry.countryCode,
                entry.city ?? "",
                entry.addresses.ipv4 ?? "",
                entry.addresses.ipv6 ?? "",
                entry.asn.map(String.init) ?? "",
                entry.routeMode.rawValue,
                entry.exitSource.rawValue,
                String(Int(row.dwell(now: now).rounded()))
            ]
            lines.append(fields.map(escape).joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
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
    @Environment(AppEnvironment.self) private var environment
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
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if let asn = entry.asn {
                        Text(verbatim: "AS\(asn)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text(entry.recordedAt, style: .time)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                if displayEntry.isCurrent {
                    Text(String(localized: "Current"))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tint)
                } else {
                    Text(HistoryDisplayEntry.dwellLabel(displayEntry.dwell()))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .help(String(localized: "Time spent on this exit"))
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var location: String {
        entry.locationLabel(using: environment.cityLocalizer)
    }

    private var previousTransitionLabel: String? {
        guard let previous = displayEntry.previous else { return nil }
        let previousLocation = previous.locationLabel(using: environment.cityLocalizer)
        guard previousLocation != location else { return nil }
        return previousLocation
    }
}

/// 列表右侧的常驻详情栏：方向键浏览时随选中项更新，不再弹出模态窗口。
private struct HistoryEntryDetailView: View {
    @Environment(AppEnvironment.self) private var environment
    let displayEntry: HistoryDisplayEntry
    let flagStyle: CountryFlagStyle
    let onDelete: () -> Void
    let onClose: () -> Void

    private var entry: NetworkHistoryEntry { displayEntry.current }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    CountryFlagView(
                        countryCode: entry.countryCode,
                        style: flagStyle,
                        diameter: 32,
                        containerSize: CGSize(width: 44, height: 44)
                    )
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.locationLabel(using: environment.cityLocalizer))
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("history.entry.detail")
                        Text(entry.recordedAt.formatted(date: .abbreviated, time: .standard))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    .help(String(localized: "Close"))
                    .accessibilityLabel(String(localized: "Close"))
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    if let previous = displayEntry.previous {
                        field(
                            String(localized: "Switched from"),
                            previous.locationLabel(using: environment.cityLocalizer)
                        )
                    }
                    field(
                        displayEntry.isCurrent ? String(localized: "In use for") : String(localized: "Time on this exit"),
                        HistoryDisplayEntry.dwellLabel(displayEntry.dwell())
                    )
                    copyableField(String(localized: "Public IPv4"), entry.addresses.ipv4)
                    copyableField(String(localized: "Public IPv6"), entry.addresses.ipv6)
                    if let asn = entry.asn {
                        field(String(localized: "ASN"), "AS\(asn)", monospaced: true)
                    }
                    if entry.routeMode != .unknown {
                        field(String(localized: "Route"), entry.routeMode.label)
                    }
                    if entry.exitSource != .unknown {
                        field(String(localized: "Probe source"), entry.exitSource.label)
                    }
                    if entry.locationSource != .unknown {
                        field(String(localized: "Location source"), entry.locationSource.displayLabel)
                    }
                }

                Divider()

                Button(role: .destructive, action: onDelete) {
                    Label(String(localized: "Delete Record"), systemImage: "trash")
                }
                .controlSize(.small)
            }
            .padding(16)
        }
        .background(Color.primary.opacity(0.025))
    }

    private func field(_ label: String, _ value: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(monospaced ? .system(.callout, design: .monospaced) : .callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func copyableField(_ label: String, _ value: String?) -> some View {
        if let value {
            HStack(alignment: .bottom, spacing: 6) {
                field(label, value, monospaced: true)
                Button {
                    HistoryView.copyToPasteboard(value)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(String(localized: "Copy IP address"))
                .accessibilityLabel(String(localized: "Copy IP address"))
            }
        }
    }
}
