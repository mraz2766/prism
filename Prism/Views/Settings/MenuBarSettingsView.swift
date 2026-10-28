import SwiftUI

struct MenuBarSettingsView: View {
    @Environment(SettingsStore.self) private var settings

    @State private var showsTemplateText = false

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section(String(localized: "Display style")) {
                Picker(String(localized: "Menu bar shows"), selection: $settings.menuBarDisplayMode) {
                    ForEach(MenuBarDisplayMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .accessibilityIdentifier("settings.menuBar.displayMode")
            }

            if settings.menuBarDisplayMode == .custom {
                customComposer
            }

            Section(String(localized: "Menu Bar Preview")) {
                VStack(spacing: 8) {
                    simulatedMenuBar(String(localized: "Online"), status: .online(.preview))
                    simulatedMenuBar(
                        String(localized: "Confirming"),
                        status: .verifying(previous: .preview, candidateAddress: "198.51.100.8")
                    )
                    simulatedMenuBar(String(localized: "Offline"), status: .offline(previous: .preview))
                }
                .padding(.vertical, 4)
                .animation(.easeOut(duration: 0.12), value: settings.countryFlagStyle)
                .animation(.easeOut(duration: 0.15), value: settings.customMenuTemplate)
            }
            Section(String(localized: "Country flag style")) {
                Picker(String(localized: "Style"), selection: $settings.countryFlagStyle) {
                    ForEach(CountryFlagStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .accessibilityIdentifier("settings.menuBar.flagStyle")

                Text(String(localized: "Flag style also applies to the popover, details, and history. Each style uses a compact menu bar rendering."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private func simulatedMenuBar(_ stateLabel: String, status: NetworkStatus) -> some View {
        let presentation = preview(status: status)
        return HStack(spacing: 12) {
            Text(stateLabel)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)

            Spacer()

            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    previewIndicator(presentation.indicator)
                    if !presentation.title.isEmpty {
                        Text(presentation.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("settings.menuBar.preview")

                Image(systemName: "wifi")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Image(systemName: "controlcenter")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 0.5)
                    )
            )
        }
    }

    private var composition: MenuBarTemplateComposition {
        MenuBarTemplateComposition(template: settings.customMenuTemplate)
    }

    private func updateComposition(_ change: (inout MenuBarTemplateComposition) -> Void) {
        var next = composition
        change(&next)
        guard !next.isEmpty else { return }
        withAnimation(.easeOut(duration: 0.15)) {
            settings.customMenuTemplate = next.template
        }
    }

    private var customComposer: some View {
        @Bindable var settings = settings
        let current = composition
        let available = MenuBarTemplateElement.allCases.filter { !current.elements.contains($0) }

        return Section {
            Toggle(String(localized: "Show flag"), isOn: Binding(
                get: { current.showsFlag },
                set: { newValue in updateComposition { $0.showsFlag = newValue } }
            ))
            .disabled(current.showsFlag && current.elements.isEmpty)
            .accessibilityIdentifier("settings.menuBar.custom.flag")

            LabeledContent(String(localized: "Text")) {
                ChipFlowLayout(spacing: 6) {
                    if current.elements.isEmpty {
                        Text(String(localized: "None"))
                            .foregroundStyle(.tertiary)
                    }
                    ForEach(Array(current.elements.enumerated()), id: \.element) { index, element in
                        selectedChip(element, index: index, in: current)
                    }
                }
            }

            if !available.isEmpty {
                LabeledContent(String(localized: "Add")) {
                    ChipFlowLayout(spacing: 6) {
                        ForEach(available) { element in
                            Button {
                                updateComposition { $0.elements.append(element) }
                            } label: {
                                Label(element.label, systemImage: "plus")
                                    .font(.callout)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .accessibilityIdentifier("settings.menuBar.custom.add.\(element.rawValue)")
                        }
                    }
                }
            }

            DisclosureGroup(String(localized: "Edit as text"), isExpanded: $showsTemplateText) {
                VStack(alignment: .leading, spacing: 6) {
                    TextField(String(localized: "Custom template"), text: $settings.customMenuTemplate)
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                    Text(String(localized: "Available placeholders: {flag} {code} {country} {city} {status}. The flag always appears first."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
        } header: {
            Text(String(localized: "Custom content"))
        } footer: {
            if !MenuBarTemplateComposition.isRepresentable(settings.customMenuTemplate) {
                Text(String(localized: "The template contains custom text. Editing the items above will replace it."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func selectedChip(
        _ element: MenuBarTemplateElement,
        index: Int,
        in current: MenuBarTemplateComposition
    ) -> some View {
        let canRemove = current.showsFlag || current.elements.count > 1
        return HStack(spacing: 2) {
            if index > 0 {
                Button {
                    updateComposition { $0.elements.swapAt(index, index - 1) }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.caption2.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(String(localized: "Move left"))
            }

            Text(element.label)
                .font(.callout)

            Button {
                updateComposition { $0.elements.remove(at: index) }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(!canRemove)
            .opacity(canRemove ? 1 : 0.35)
            .help(String(localized: "Remove"))
            .accessibilityIdentifier("settings.menuBar.custom.remove.\(element.rawValue)")
        }
        .padding(.leading, index > 0 ? 6 : 8)
        .padding(.trailing, 6)
        .padding(.vertical, 3)
        .background(Color.accentColor.opacity(0.15), in: Capsule())
    }

    private func preview(status: NetworkStatus) -> MenuBarPresentation {
        MenuBarLabelRenderer.presentation(
            status: status,
            mode: settings.menuBarDisplayMode,
            flagStyle: settings.countryFlagStyle,
            customTemplate: settings.customMenuTemplate
        )
    }

    @ViewBuilder
    private func previewIndicator(_ indicator: MenuBarIndicator) -> some View {
        switch indicator {
        case .none:
            EmptyView()
        case .flag(let countryCode):
            CountryFlagView(
                countryCode: countryCode,
                style: settings.countryFlagStyle,
                diameter: 16,
                containerSize: CGSize(width: 18, height: 18)
            )
        case .emoji(let countryCode):
            Text(CountryFlag.emoji(for: countryCode) ?? "◎")
                .font(.system(size: 14))
                .frame(width: 20, height: 18)
        case .systemSymbol(let name):
            Image(systemName: name)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 16, height: 16)
        }
    }
}

/// 右对齐换行排布，避免元素较多时把设置窗口撑宽。
private struct ChipFlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, maxWidth: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, maxWidth: bounds.width) {
            var x = bounds.maxX - row.width
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(for subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let proposedWidth = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if proposedWidth > maxWidth, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
