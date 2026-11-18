import SwiftUI

/// 期望地区输入：已添加的国家显示为带国旗的标签，后面是一个只负责“添加”的小输入框。
///
/// 输入内容先留在本地草稿里，按回车、逗号或空格才写入设置，
/// 避免每敲一个字母就改写设置、刷新菜单栏和整页重排。
struct RegionCodeField: View {
    @Binding var storage: String
    let flagStyle: CountryFlagStyle

    @State private var draft = ""
    @State private var shakes: CGFloat = 0
    @State private var rejected = false
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var codes: [String] { RegionGuard.parse(storage) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            FlowLayout(spacing: 6) {
                ForEach(codes, id: \.self) { code in
                    chip(code)
                        .transition(
                            reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity)
                        )
                }
                inputField
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: isFocused || rejected ? 1.5 : 0.5)
            )
            // 自绘焦点框画在边框内，不会被所在卡片裁掉。
            .contentShape(Rectangle())
            .onTapGesture { isFocused = true }
            .modifier(ShakeEffect(animatableData: shakes))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isFocused)
            .animation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.3), value: codes)

            if rejected {
                Text(String(localized: "Use two-letter country codes, such as JP or US."))
                    .font(.caption)
                    .foregroundStyle(StatusPalette.offline)
                    .transition(.opacity)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.general.regionGuard.countries")
    }

    private var borderColor: Color {
        if rejected { return StatusPalette.offline }
        return isFocused ? Color.accentColor : Color(nsColor: .separatorColor)
    }

    private var inputField: some View {
        TextField(
            String(localized: "Expected regions"),
            text: $draft,
            prompt: Text(codes.isEmpty ? String(localized: "Type a code, e.g. JP") : String(localized: "Add"))
        )
        .textFieldStyle(.plain)
        .labelsHidden()
        .focusEffectDisabled()
        .focused($isFocused)
        .font(.body.monospaced())
        .frame(minWidth: 96, maxWidth: 160)
        .onSubmit(commit)
        .onChange(of: draft) { _, value in
            let upper = value.uppercased()
            if upper != value { draft = upper; return }
            if rejected { withAnimation(.easeOut(duration: 0.15)) { rejected = false } }
            // 输入分隔符时立即把前面的代码变成标签。
            if value.contains(where: { ",，、;；/| ".contains($0) }) { commit() }
        }
        .onChange(of: isFocused) { _, focused in
            if !focused, !draft.trimmingCharacters(in: .whitespaces).isEmpty { commit() }
        }
        .onKeyPress(.delete) {
            guard draft.isEmpty, let last = codes.last else { return .ignored }
            remove(last)
            return .handled
        }
        .accessibilityLabel(String(localized: "Expected regions"))
    }

    private func chip(_ code: String) -> some View {
        HStack(spacing: 4) {
            CountryFlagView(
                countryCode: code,
                style: flagStyle,
                diameter: 14,
                containerSize: CGSize(width: 18, height: 14)
            )
            Text(verbatim: code)
                .font(.callout.monospaced().weight(.medium))
            Button {
                remove(code)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 14)
                    .background(Color.primary.opacity(0.08), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(String(localized: "Remove"))
            .accessibilityLabel("\(String(localized: "Remove")) \(code)")
        }
        .padding(.leading, 5)
        .padding(.trailing, 4)
        .padding(.vertical, 2)
        .background(.tint.opacity(0.12), in: Capsule())
        .help(Locale.autoupdatingCurrent.localizedString(forRegionCode: code) ?? code)
        .accessibilityElement(children: .combine)
    }

    private func commit() {
        let tokens = draft
            .components(separatedBy: CharacterSet(charactersIn: ",，、;；/|").union(.whitespaces))
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { draft = ""; return }
        let valid = RegionGuard.parse(tokens.joined(separator: ","))
        let invalid = tokens.filter { !valid.contains($0.uppercased()) }
        if !valid.isEmpty {
            storage = Self.merged(codes, adding: valid)
        }
        if invalid.isEmpty {
            draft = ""
        } else {
            // 保留无效部分给用户修改，并抖动提示。
            draft = invalid.joined(separator: " ")
            withAnimation(.easeOut(duration: 0.15)) { rejected = true }
            if !reduceMotion {
                withAnimation(.linear(duration: 0.32)) { shakes += 1 }
            }
        }
    }

    private func remove(_ code: String) {
        storage = codes.filter { $0 != code }.joined(separator: ", ")
    }

    /// 合并并去重，保持原有顺序。
    static func merged(_ existing: [String], adding new: [String]) -> String {
        var result = existing
        for code in new where !result.contains(code) { result.append(code) }
        return result.joined(separator: ", ")
    }
}
