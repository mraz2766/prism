# Prism 响应性能、强调色与视觉降噪重构 — Feature ExecPlan

这是一份持续维护的实施计划。项目内 `.agent/PLANS.md` 与全局 `~/.codex/PLANS.md` 均不存在，因此沿用仓库既有 ExecPlan 的自包含结构。用户确认本计划前，只允许修改本文件；不得修改应用代码、资源或版本，不得构建、安装或提交发布版本。

## Purpose

Prism 2.7.1 已具备完整的菜单栏出口监控、Dashboard、历史和设置功能，但当前体验存在四组互相放大的问题：

1. 强调色只更新设置内容区，设置窗口顶部选中标签仍停留在系统蓝色。现有实现通过全局交换 `NSColor` 方法、整窗失效、`TabView.id` 重建和异步二次刷新尝试修补原生工具栏，仍无法改变 AppKit 缓存的标签文字与图标，同时增加主线程布局和渲染负担。
2. 稳态每 500ms 并发探测 IPv4 与 IPv6，burst 每 150ms 一轮，出口探测 URLSession 最长 300ms 就轮换。运行版空闲 CPU 瞬时样本约 2.7%–8%，5 秒采样反复命中 Network/CFNetwork 连接建立与 SwiftUI 布局路径。
3. 菜单栏状态项在 `mouseUp` 才响应，Popover 开启动画，打开/关闭没有过渡状态。快速点击可以在动画期间重复进入 show/close；刷新按钮也没有防重入。设置页的“组件预览”按钮没有动作、开关绑定常量，进一步制造“点了没反应”的感觉。
4. 设置页和 Dashboard 同时使用大面积灰色分组、材质、描边和多层标题。交互目标中，强调色按钮实际约 22×22pt，Popover 操作按钮约 24×24pt，命中范围偏小；历史列表在频繁线路切换时信息密度过高。

本功能要让 Prism 的“快”既体现在后台资源占用，也体现在每次点击的即时反馈：设置标签和所有可交互组件必须统一使用应用强调色；Popover 在鼠标按下后快速、确定地出现，快速连点不会排队产生多次反应；稳定后台保持出口变化检测能力但不持续制造连接风暴；主要界面减少装饰层，让国家、地址、路线和状态成为唯一视觉重点。

用户价值是：应用安静驻留、打开即见、点击有反馈、颜色一致，并且在降低资源占用后仍能可靠识别代理节点与公网出口变化。

## Progress

- [x] 2026-08-14：完成当前安装版截图、无障碍树、代码链路和运行时采样。
- [x] 2026-08-14：复现“极光紫内容区 + 系统蓝顶部标签”的强调色断层。
- [x] 2026-08-14：确认 57 项现有单元测试通过，但没有颜色渲染、Popover 重入或运行时资源回归覆盖。
- [x] 2026-08-14：创建本 Feature ExecPlan。
- [x] 2026-08-14：用户确认本计划，进入 Implementation。
- [x] 2026-08-14：Milestone 1 完成；删除全局颜色 Hook，引入深浅主题语义和自绘设置导航，严格编译通过。
- [x] 2026-08-14：Milestone 2 完成；按键持久化、相关刷新事件、actor 探测循环、1 秒/250ms 节拍与 1.5 秒连接代际完成。
- [x] 2026-08-14：Milestone 3 完成；状态项改为 mouseDown，无动画 Popover 增加四态防重入、刷新禁用和 30pt 操作目标。
- [x] 2026-08-14：Milestone 4 完成；设置、Dashboard、历史与 Popover 完成容器和重复装饰降噪，并修复动态版本文案。
- [x] 2026-08-14：Milestone 5 完成；65 项单元测试、严格 clean build、Debug/Release 原生界面验收与 30 秒空闲 CPU 采样完成。
- [x] 2026-08-14：Milestone 6 完成；`2.7.2 (17)` Universal Release 已签名并安装至 `/Applications/Prism.app`，交付改动收敛到本文件所在的本地中文 Git 提交。
- [x] 2026-08-14：填写 Outcomes & Retrospective。

## Surprises & Discoveries

- SwiftUI `Settings` 中的 macOS `TabView` 把标签交给 AppKit 原生工具栏绘制。`.tint`、`.accentColor` 和内容树 `.id` 无法可靠重设已缓存的标签前景色；当前截图证明全局 `NSColor.controlAccentColor` 方法交换与 `validateVisibleItems()` 仍然无效。
- `DynamicAccentColorRuntime.currentNSColor` 每次查询都会加锁并创建新的动态 `NSColor`。由于实现交换了全局 `controlAccentColor`，AppKit 任何窗口的颜色解析都可能经过这条路径，风险和影响范围大于设置页本身。
- 一次强调色赋值会同步写入全部八项设置、向网络刷新配置流发送不相关事件、重启周期任务、全窗口重绘，并在 `SettingsToolbarSynchronizer` 更新后再次全窗口重绘。
- “组件预览”中的 `Button` 动作为 `{}`，`Toggle` 使用 `.constant(true)`。它们看起来可操作但不会产生用户可理解的结果，是明确的交互欺骗信号。
- 稳态一轮探测会同时启动 IPv4 和 IPv6 请求。以 500ms 节拍计算约每秒四个请求；150ms burst 时峰值约每秒十三个请求。300ms 会话代际进一步降低连接复用率。
- 当前 Popover 的 SwiftUI 内容在应用启动时已经创建，慢开不主要来自每次重新构建 controller；更可能来自 `mouseUp` 触发、系统动画、激活应用、首次附着布局和 show/close 重入叠加。
- 既有 ExecPlan 记录显示 1 秒稳态、250ms burst、1.5 秒连接代际曾在真实 OneBox 切换场景中达到约 1.3% CPU 中位数且保留节点切换能力。这是本次调度回调的优先基线，而不是凭空选择新数值。
- 自绘设置导航在 Debug 运行版中可由辅助功能树明确读出 selected 状态；选择极光紫后，导航图标/标题、分段控件、主按钮、Toggle 和状态徽章同步变紫，原先的系统蓝残留不再出现。
- 关闭 Dashboard 与设置窗口后的 Debug 运行版连续 20 秒 CPU 样本为中位数 0.60%、均值 1.15%、P95 2.10%；同机旧安装版采样前瞬时约 8.8%，说明降频与取消全局重绘方向有效。最终仍以 Release 安装版复测为准。
- 独立 UI Test target 可以严格编译，但本机无签名 Runner 在 95 秒内卡在“waiting for workers to materialize”，未进入任何用例；已中断并保留 xcresult，不能计为 UI 测试通过。使用 computer-use 完成了相同关键路径的可见界面与辅助功能树验收。
- 安装版关闭全部窗口后连续 30 秒 CPU 样本为中位数 0.70%、均值 0.77%、P95 1.20%、范围 0.10%–4.20%，达到中位数不高于 2% 的目标。
- 独立 UI Test 尝试遗留的无签名 `PrismUITests-Runner.app` 被 Gatekeeper 显示为“已损坏”。它不是 Prism 主应用；两份 DerivedData Runner 已移动到废纸篓，已安装的签名 Release 不受影响。

实施阶段的新事实必须追加在这里，不覆盖既有记录。

## Decision Log

- 2026-08-14：本批次按“小改动”发布。虽然会调整内部调度和多个界面，但不新增或删除产品核心能力，也不改变用户数据模型；成功后从 `2.7.1 (16)` 提升为 `2.7.2 (17)`。若实施中必须改变核心出口确认协议或历史语义，需在本节记录重新评估，但不得自行扩大为大版本。
- 2026-08-14：不继续使用 Objective-C runtime 方法交换实现应用强调色。删除 `DynamicAccentColorRuntime`、`SettingsToolbarSynchronizer` 和设置根视图 `.id(accent)`，避免全局颜色查询锁与整窗失效。
- 2026-08-14：不依赖原生 Settings `TabView` 动态着色。设置窗口改用应用自绘的顶部导航，选中图标、标题、键盘焦点和辅助功能状态均直接消费同一个 `AccentTheme`；内容页按选择枚举切换。
- 2026-08-14：强调色从“一个裸 Color”升级为语义主题，至少包含 `primary`、`pressed`、`softBackground` 和适配深浅模式的可读前景。首版保留六个选择，重新校准为光谱蓝、潮汐青、暖阳橙、苔原绿、极光紫、石墨灰，避免增加迁移成本；旧 rawValue 继续可读。
- 2026-08-14：浅色模式下主色优先满足白色按钮文字的可读性；深色模式使用更明亮变体。颜色选中状态继续同时使用勾选、辅助功能 selected trait 和文字标签，不能只靠颜色区分。
- 2026-08-14：设置变化采用“相关事件才发布”。只有 `refreshInterval` 与 `refreshOnNetworkChange` 改变时才向刷新调度流发送配置；强调色、外观、菜单栏文案等不再重启网络定时器。每个属性只持久化自身键，且相同值赋值不触发副作用。
- 2026-08-14：出口检测回到证据充分的自适应基线：稳态 1 秒、候选/网络变化/手动刷新 burst 250ms、burst 4 秒、连接代际 1.5 秒。请求保持串行，不能并发堆积；IPv4/IPv6 同一轮仍并发以保留双栈观察。
- 2026-08-14：`RealtimeExitMonitor` 的调度与稳定器状态移到独立 actor；AppKit/SwiftUI 可观察状态只在真实状态变化时回到 MainActor。网络等待不得持有主线程执行权。
- 2026-08-14：Popover 以确定性响应优先。状态项在鼠标按下时触发；默认关闭系统 show/close 动画；新增 `closed/opening/open/closing` 状态机，并在过渡期间合并或忽略重复动作。外部点击仍可靠关闭。
- 2026-08-14：刷新是单飞操作。刷新期间按钮显示明确进行中状态并禁用重复触发；服务层已有 inflight 合并继续作为第二道保护。
- 2026-08-14：视觉降噪以删减层级为主，不引入第三方 UI 包、不生成图片、不改变品牌 Logo。每个主要区域最多保留一种容器强调方式：材质、底色或边框三者选一。
- 2026-08-14：历史数据保持完整，不在持久化层合并或删除快速切换。仅在展示层通过日期、连续变化和弱化重复字段降低密度，避免视觉优化改变事实记录。
- 2026-08-14：颜色显示名升级为光谱蓝、潮汐青、暖阳橙、苔原绿、极光紫、曜石灰；持久化 rawValue 保持不变，旧用户偏好无需迁移。
- 2026-08-14：Popover 使用完全关闭 AppKit 动画的方案。实际界面内容已在启动时预建，mouseDown 与状态机提供即时反馈；不再额外加入 SwiftUI 入场动画，以免重新引入点击排队感。

## Architecture and Implementation

### Milestone 1：强调色主题与设置导航

在 `AppSettings.swift` 中将 `AccentColorChoice` 的颜色定义整理为可测试的 `AccentTheme`。主题根据当前 Appearance 返回主色、按下色、弱背景色和合适的前景色；保留现有枚举 rawValue，升级后用户选择不丢失。颜色样本使用明确的 sRGB 分量，避免每次访问重复创建昂贵对象，可按选择缓存静态动态色。

`SettingsRootView` 不再使用会生成原生工具栏标签的 `TabView`。新增 `SettingsSection` 选择枚举和 `SettingsNavigationBar`：顶部以六项以内的横向按钮展示图标与标题，当前项使用主题主色、轻量软底和 selected trait，未选项使用 secondary。支持左右方向键、完整键盘焦点、VoiceOver label/value，最小点击区域 44×44pt。内容区用 switch 呈现原有五个设置页，不重复销毁环境对象。

删除 `DynamicAccentColorRuntime.swift` 及其启动、持久化和 representable 调用。Settings Scene、Dashboard、Popover 继续在 SwiftUI 边界使用 `.tint(theme.primary)`；所有自绘选中标题显式使用主题颜色，所以切色不依赖 AppKit 全局状态。

### Milestone 2：设置副作用与出口探测调度

`SettingsStore` 为每个属性提供相关的持久化方法。刷新配置流只观察刷新相关字段；外观变化只调用 AppEnvironment 的 appearance 观察，菜单栏设置只触发状态项 render，强调色只让依赖主题的 SwiftUI 视图失效。相同值赋值直接返回或不执行副作用。

`RealtimeExitMonitor` 改为 actor，负责单一 loop task、暂停、burst deadline、稳定器和串行探测。默认稳态 1 秒，burst 250ms/4 秒；每轮按开始时间扣除请求耗时，慢请求完成后立即进入下一轮但不叠加第二轮。`RefreshCoordinator` 通过受控 Task 调用 actor，start/stop/sleep/wake 保持幂等。

出口身份 HTTP 客户端使用 1.5 秒 rotating generation。同一 generation 复用 ephemeral URLSession；过期时完成旧任务并建立新代际，以保证代理节点切换后能摆脱旧隧道，又避免 300ms 频繁重建。现有 no-cache、no-cookie、短超时和 exact observation 语义保持不变。

### Milestone 3：Popover 与点击反馈

`StatusBarController` 新增纯状态机或可单测的 transition reducer。状态项接收 mouseDown；左键根据当前稳定状态打开或关闭，opening/closing 期间不重复排队。`popoverDidShow`、`popoverWillClose`、`popoverDidClose` 驱动最终状态并统一安装/移除 dismiss monitors。重复 close 保持幂等。

Popover 默认 `animates = false`，继续尊重 Reduce Motion；如果实际视觉验证表明完全无动画过硬，可只在 SwiftUI 内容内使用不超过 100ms 的 opacity 过渡，但不得重新启用不可控的系统 Popover 动画。

Footer 操作按钮点击范围提升至 30–32pt，增加按下态。刷新进行中禁用按钮并保持旋转反馈；历史和设置动作先关闭 Popover，再在关闭完成或下一主循环打开目标窗口，避免窗口与 Popover 同时争抢 key 状态。

设置强调色圆点保留约 20–22pt 视觉尺寸，但按钮布局至少 34×34pt；移除会包裹整个设置树的 spring transaction，只对勾选和轻量缩放做局部、Reduce Motion 感知的短动画。组件预览改为明确的非交互样本，或提供只改变本地 preview state 的真实交互，不能再保留空动作与常量开关。

### Milestone 4：视觉降噪与辅助功能

设置窗口按内容重新确定紧凑尺寸，减少大块空白。导航与内容之间只保留一条 separator；表单分组使用更轻的 control background，不同时叠加圆角大底、材质和描边。段落标题、字段标签与说明形成三级层级，说明文字不与主标签争夺权重。

Dashboard 保留国家/城市 Hero 作为唯一强容器。公网端点和网络基础设施区改用轻量分组：默认强调主 IP、运营商、ASN 和路线，其余数据使用 secondary/tertiary；减少每行重复图标和大面积灰色卡片。长组织名与 IPv6 保持可选择、可复制、可换行或中间截断并提供 help。

History 不改写原始记录。列表行突出“新出口”，旧出口、ASN、路线和时间降为辅助层；相同日期只显示一次标题，快速往返可通过连续行的连线或弱化重复来源表达。清除历史仍是唯一 destructive 操作并保留确认。

所有状态继续使用图标/文字而非仅颜色。Increase Contrast 提高选中边界和 separator；Reduce Transparency 禁用 material；Reduce Motion 禁用循环与弹性动画。设置导航、色盘、Popover 按钮和历史行检查 VoiceOver 顺序与 keyboard focus。

### Milestone 5：测试与性能验收

新增强调色主题测试，覆盖六个旧 rawValue、深浅模式变体、主题一致性与选中前景。新增 SettingsStore 测试，证明强调色或菜单设置不会向刷新配置流发送事件，刷新字段只发送一次，相同值不产生副作用。

新增 RealtimeExitMonitor 调度测试，覆盖稳态节拍、burst、请求不重叠、暂停/恢复、stop 幂等、连接代际复用与轮换。新增 Popover transition reducer 测试，覆盖快速 open/open、open/close/open、外部 dismiss 和 delegate 回调乱序；任何序列最多存在一个目标稳定状态。

扩展 UI 测试：打开设置、切换极光紫、确认自绘导航仍 selected 且内容主题同步；键盘切换设置页；组件预览不再暴露无效控件。Dashboard 和 History 做关键元素与可访问标签检查。颜色像素本身若 XCUI 无法可靠读取，则通过主题单元测试 + 自绘导航绑定结构 + 当前态截图验收形成组合证据。

运行安装版进行 30 秒空闲 CPU 采样和 Popover 快速连点。目标是窗口关闭时 Release CPU 中位数不高于 2%，无持续上升；从 mouseDown handler 到 `popoverDidShow` 的日志/时钟样本中位数低于 100ms、P95 低于 150ms；连续五次快速点击不产生多次窗口或排队反弹。强调色连续切换六次不重建设置根视图，不触发网络定时器重启。

### Milestone 6：发布、安装与本地提交

所有测试、严格 build、运行时截图和性能目标通过后，执行 `./scripts/release.sh small`。脚本应把版本从 `2.7.1 (16)` 提升为 `2.7.2 (17)`，完成测试和 Release 构建后才替换 `/Applications/Prism.app`。失败时不得覆盖当前安装版。

安装后验证 Info.plist 版本、Universal 架构、签名、启动、设置切色、Popover、Dashboard 和 History。最后创建一次本地 Git 提交，使用规范中文描述本批次性能、交互和视觉改动；禁止 push、无需 tag。

## File-Level Changes

- `Prism/Models/AppSettings.swift`：重构六个强调色和 `AccentTheme` 语义，保持 rawValue 兼容。
- `Prism/Persistence/SettingsStore.swift`：按键持久化、相关事件发布、相同值去重。
- `Prism/Services/DynamicAccentColorRuntime.swift`：删除全局颜色 method swizzling 与整窗重绘实现，并从 Xcode target 移除。
- `Prism/App/AppDelegate.swift`、`Prism/App/PrismApp.swift`：移除运行时颜色安装，保留 SwiftUI 主题注入。
- `Prism/Views/Settings/SettingsRootView.swift`：自绘设置导航、稳定内容切换、键盘和辅助功能。
- `Prism/Views/Settings/AppearanceSettingsView.swift`：新色盘、扩大命中区、局部动画和真实/静态预览。
- `Prism/Views/Settings/GeneralSettingsView.swift`、`MenuBarSettingsView.swift`、`NetworkSettingsView.swift`、`PrivacySettingsView.swift`：统一轻量分组和说明层级。
- `Prism/Services/RealtimeExitMonitor.swift`、`RefreshCoordinator.swift`：actor 调度、自适应节拍、幂等生命周期和 MainActor 边界。
- `Prism/Services/ExitAddressProbe.swift`、`HTTPClient.swift`：1.5 秒连接代际与请求复用边界。
- `Prism/StatusBar/StatusBarController.swift`、`PopoverHost.swift`：mouseDown、过渡状态机、关闭动画和 dismiss 幂等。
- `Prism/Views/MenuBar/MenuBarPopoverView.swift`：按钮尺寸、按下态、刷新单飞和目标窗口切换顺序。
- `Prism/Views/Dashboard/DashboardOverviewView.swift`、`Prism/Views/Components/CountryHeroView.swift`、`SectionCard.swift`、`InfoRow.swift`、`IPAddressRow.swift`：主次层级、容器降噪、长文本和辅助功能。
- `Prism/Views/History/HistoryView.swift`：展示层密度、重复信息弱化和连续变化表达。
- `Prism/Resources/Localizable.xcstrings`：新强调色和调整后的说明文案中英文同步。
- `PrismTests/SettingsStoreTests.swift`、`RealtimeExitMonitorTests.swift`、`HTTPClientTests.swift` 及新增状态机测试：副作用、节拍、会话和重入覆盖。
- `PrismUITests/PrismUITests.swift`：设置导航、强调色、键盘、Dashboard 与 History 关键路径。
- `README.md`：同步自适应探测和强调色行为；不新增与代码事实无关的营销描述。
- `docs/execplans/prism-responsive-ui-accent-redesign.md`：持续维护进度、决定、发现、验证和复盘。

实际文件边界可因 Swift 类型归属小幅调整；任何新增或删除必须写入 Decision Log，不能静默偏离用户行为目标。

## Validation and Acceptance

### 自动验证

    xcodebuild -project Prism.xcodeproj -scheme Prism -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO test
    xcodebuild -project Prism.xcodeproj -scheme Prism -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO clean build
    ./scripts/release.sh small
    defaults read /Applications/Prism.app/Contents/Info CFBundleShortVersionString
    defaults read /Applications/Prism.app/Contents/Info CFBundleVersion
    lipo -archs /Applications/Prism.app/Contents/MacOS/Prism
    codesign --verify --deep --strict /Applications/Prism.app

Swift 6 严格并发继续开启。新增编译 warning 视为失败；测试失败或 Release 构建失败不得替换安装版。

### 可观察行为

1. 在设置中依次选择六个强调色，顶部导航图标和文字、主按钮、开关、焦点、状态徽章同步变化；不存在系统蓝残留，深浅模式均可读。
2. 连续快速点击色盘，只有最终选择生效；设置窗口不闪白、不重置当前页、不触发网络刷新配置流。
3. 单击菜单栏状态项时 Popover 快速出现；快速连点五次后状态稳定，不延迟反弹、不出现重复窗口；外部点击和切换应用可靠关闭。
4. 刷新进行中重复点击不会创建第二个刷新；历史和设置按钮只打开一个目标窗口。
5. Release 安装版关闭所有窗口空闲 30 秒，CPU 中位数目标 ≤2%；网络请求没有 150ms 永久高频或 300ms 永久建链。
6. 日本/新加坡等代理节点切换仍能在稳态下一轮观察、候选 burst 和网络 RTT允许范围内更新；不因连接复用永久停留旧节点。
7. 设置页不存在看似可点但无结果的按钮或开关；所有色点和 Popover 操作按钮具有清晰 hover、pressed、focus 和至少 30pt 的命中区。
8. Dashboard 首屏能先读到国家/城市、主 IP、路线和状态；History 长列表减少重复视觉噪音但记录条数、顺序和清除行为不变。

### 最终验收标准

- 完全删除全局 `NSColor` method swizzling，应用强调色由可测试的主题和自绘导航控制。
- 强调色切换不重建整个设置树、不遍历所有窗口、不重启网络调度。
- Popover 响应达到中位数 <100ms、P95 <150ms 的目标，快速点击不重入。
- 稳态出口检测保持可靠，Release 空闲 CPU 30 秒中位数目标 ≤2%。
- 所有自动测试、严格 build、签名、Universal 架构和安装版人工路径验证通过。
- 最终版本为 `2.7.2 (17)`，安装于 `/Applications/Prism.app`，并存在一次本地中文 Git 提交且没有远端 push。

## Idempotence and Recovery

强调色 rawValue 不变，现有 UserDefaults 无需迁移；若未知值仍回退光谱蓝。历史与缓存模型不变。设置自绘导航只改变视图组织，不改变各页持久化键。

RealtimeExitMonitor 的 start、stop、pause、resume、boost 和手动刷新必须可重复调用且最多保留一个循环与一个 in-flight 探测。Popover 的任何 delegate 回调和 dismiss 通知重复到达都不得造成负计数、重复 monitor 或再次 show。

发布脚本负责在测试/构建失败时恢复版本设置并保留现有 `/Applications/Prism.app`。如果性能目标未达标，继续在 Debug/Release 构建中采样并记录到 Surprises，不得通过跳过验收直接安装。任何无法可靠通过自动化操作的系统菜单栏步骤，保留截图、日志与明确限制，不伪称验证成功。

## Outcomes & Retrospective

本次交付把六个兼容旧 rawValue 的强调色重新校准为光谱蓝、潮汐青、暖阳橙、苔原绿、极光紫和曜石灰，并用 `primary`、`pressed`、`softBackground`、`foreground` 语义统一设置导航和所有组件。安装版实际选择极光紫后，顶部选中标题/图标、模式分段、按钮、Toggle 和状态徽章同时变紫，原截图中的系统蓝残留已消失；色盘同时保留勾选、文字和辅助功能 selected 状态。

删除了全局 `NSColor` method swizzling、窗口遍历失效和 `TabView.id` 整树重建。设置持久化改为按键且相关事件发布，强调色与菜单设置不再重启网络调度。出口监控移入 actor，以 1 秒稳态、250ms/4 秒 burst、1.5 秒连接代际和单飞探测运行；30 秒 Release 空闲 CPU 中位数 0.70%、均值 0.77%、P95 1.20%。本轮未单独记录内存基线，后续若增加长期 soak test，应同时记录常驻集和连接数量。

Popover 改为 mouseDown 触发、关闭 AppKit 动画，并用 `closed/opening/open/closing` reducer 防止快速连点重入；刷新在视图与服务两层单飞。状态机乱序与重复输入已有单元测试覆盖，但本轮没有把内部时间戳探针留在产品代码中，因此无法诚实给出 mouseDown 到 `popoverDidShow` 的精确 P95；原生人工路径确认打开/关闭无排队反弹。后续可在性能测试构建中加入 signpost，而不是把诊断日志带入 Release。

自动验证共 65 项单元测试、0 失败；Swift 6 严格 clean build 和签名 Universal Release 构建通过。独立 UI Test Runner 因本机签名/worker 环境未执行用例，不能计为通过；同等关键路径已通过原生 UI 自动化和辅助功能树验证。代理节点切换协议没有改变，串行轮询与双栈观察由单元测试覆盖；本轮没有制造新的真实代理切换场景。

最终版本为 `2.7.2 (17)`，架构为 `x86_64 arm64`，签名严格验证通过，安装路径为 `/Applications/Prism.app`。本 ExecPlan 与实现、测试、版本变更位于同一个本地中文交付提交中；未执行 push，也未创建 tag。
