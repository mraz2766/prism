import SwiftUI

struct SettingsRootView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(SettingsStore.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: SettingsSection = .general
    /// 切换方向：向右的标签从右侧滑入，向左的从左侧滑入。
    @State private var movesForward = true

    /// 设置窗口的固定尺寸，所有标签页共用。
    static let windowSize = CGSize(width: 620, height: 600)

    var body: some View {
        VStack(spacing: 0) {
            SettingsNavigationBar(selection: selectionBinding)
                .padding(.horizontal, 22)
                .padding(.top, 10)
                .padding(.bottom, 10)

            Divider()

            ZStack(alignment: .top) {
                page(for: selection)
                    .id(selection)
                    .transition(pageTransition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipped()
        }
        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(settings.accentColorChoice.color)
        .navigationTitle(selection.title)
        .background(SettingsWindowAccessor { environment.registerSettingsWindow($0) })
    }

    private var selectionBinding: Binding<SettingsSection> {
        Binding(
            get: { selection },
            set: { next in
                guard next != selection else { return }
                SettingsFocus.clear()
                movesForward = next.index > selection.index
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.32)) {
                    selection = next
                }
            }
        )
    }

    private var pageTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let distance: CGFloat = 28
        return .asymmetric(
            insertion: .offset(x: movesForward ? distance : -distance).combined(with: .opacity),
            removal: .offset(x: movesForward ? -distance : distance).combined(with: .opacity)
        )
    }

    @ViewBuilder
    private func page(for section: SettingsSection) -> some View {
        switch section {
        case .general: GeneralSettingsView()
        case .menuBar: MenuBarSettingsView()
        case .appearance: AppearanceSettingsView()
        case .about: AboutSettingsView()
        }
    }
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case menuBar
    case appearance
    case about

    var id: String { rawValue }
    var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .menuBar: String(localized: "Menu Bar")
        case .appearance: String(localized: "Appearance")
        case .about: String(localized: "About")
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .menuBar: "menubar.rectangle"
        case .appearance: "paintpalette"
        case .about: "info.circle"
        }
    }
}

/// 顶部分段导航：选中底块在标签之间滑动，选中时图标轻弹一下。
private struct SettingsNavigationBar: View {
    @Binding var selection: SettingsSection
    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bounce = 0
    @State private var hovered: SettingsSection?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(SettingsSection.allCases) { section in
                item(section)
            }
        }
        .padding(3)
        .background(
            Capsule().fill(Color.primary.opacity(0.05))
        )
        .frame(maxWidth: .infinity)
        .onMoveCommand { direction in
            guard direction == .left || direction == .right else { return }
            let delta = direction == .left ? -1 : 1
            let next = min(max(selection.index + delta, 0), SettingsSection.allCases.count - 1)
            select(SettingsSection.allCases[next])
        }
    }

    private func select(_ section: SettingsSection) {
        guard section != selection else { return }
        selection = section
        bounce += 1
    }

    private func item(_ section: SettingsSection) -> some View {
        let isSelected = selection == section
        return Button {
            select(section)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 16, height: 16)
                    .keyframeAnimator(initialValue: 1.0, trigger: bounce) { content, scale in
                        content.scaleEffect(isSelected ? scale : 1)
                    } keyframes: { _ in
                        if reduceMotion {
                            LinearKeyframe(1.0, duration: 0.01)
                        } else {
                            SpringKeyframe(1.22, duration: 0.14)
                            SpringKeyframe(1.0, duration: 0.3, spring: .bouncy)
                        }
                    }
                Text(section.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 14)
            .frame(height: 28)
            .frame(maxWidth: .infinity)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                        .overlay(Capsule().fill(.tint.opacity(0.1)))
                        .matchedGeometryEffect(id: "selection", in: namespace)
                } else if hovered == section {
                    Capsule().fill(Color.primary.opacity(0.05))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
                hovered = hovering ? section : (hovered == section ? nil : hovered)
            }
        }
        .accessibilityLabel(section.title)
        .accessibilityIdentifier("settings.section.\(section.rawValue)")
        .accessibilityValue(isSelected ? String(localized: "Selected") : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// 设置窗口挂载时回调一次，用于把窗口激活并置于最前。
private struct SettingsWindowAccessor: NSViewRepresentable {
    let onAttach: (NSWindow) -> Void

    func makeNSView(context: Context) -> AttachView {
        let view = AttachView()
        view.onAttach = onAttach
        return view
    }

    func updateNSView(_ nsView: AttachView, context: Context) {}

    final class AttachView: NSView {
        var onAttach: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            onAttach?(window)
        }
    }
}
