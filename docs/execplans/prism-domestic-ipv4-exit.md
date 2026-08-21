# Prism 国内出口 IPv4 — Feature ExecPlan

这是一份持续维护的功能实施计划。项目内 `.agent/PLANS.md` 与全局 `~/.codex/PLANS.md` 均不存在，因此沿用仓库现有 ExecPlan 的自包含结构。用户确认本计划前不修改应用代码、不提升版本、不构建或安装。

## Purpose

用户单击菜单栏图标后，Popover 的公网地址区域应始终包含一行“国内出口 IPv4”，并支持与现有 IPv4、IPv6 相同的一键复制反馈。该值由中国大陆可访问的 IPIP 当前请求源地址端点独立探测，不依赖主出口国家，因此主出口显示日本、新加坡、美国或其他国家时仍会单独存在。

该能力观察的是“国内服务看到的 IPv4”，而不是承诺绕过代理。规则代理通常会将国内端点直连，此时它可能与海外公网出口不同；全隧道 VPN 或全局代理可能仍代理国内端点，此时两者可能相同，或国内端点返回非中国出口。UI 必须明确区分“国内独立出口”“与当前出口一致”“国内流量可能仍走代理”，不得把所有结果都标成“非代理 IP”。

用户可观察到的目标：打开 Popover 后无需进入详情，即可看到国内出口 IPv4、关系说明与复制按钮；启动、网络变化、主出口变化、唤醒、手动刷新及定期资料校验都会刷新它；失败不会阻塞主出口展示，也不会让 Popover 卡住。

## Progress

- [x] 2026-08-21：读取项目规则；确认计划模板文件缺失，选用仓库现有自包含 ExecPlan 结构。
- [x] 2026-08-21：只读检查现有 `myip.ipip.net/json` 国内回退、刷新协调器、Popover 与复制组件。
- [x] 2026-08-21：确认 IPIP 官方将 MyIP 描述为免费、无质量承诺的请求源 IP 服务；设计必须独立失败、短超时且不影响主链。
- [x] 2026-08-21：创建本 Feature ExecPlan。
- [x] 2026-08-21：用户确认本计划，并明确要求同步更新 README。
- [x] 2026-08-21：实现国内 IPv4 独立探针、状态模型与 ViewModel；请求使用单次会话、2 秒上限和 no-cache，失败保留内存结果。
- [x] 2026-08-21：接入启动、主出口变化、网络变化、唤醒、手动与定期刷新生命周期；离线和停止会取消独立请求。
- [x] 2026-08-21：在 Popover 地址卡加入国内出口 IPv4、关系说明与一键复制；主出口尚不可用时仍独立显示该行。
- [x] 2026-08-21：更新隐私说明、README、中文本地化；新增探针与 ViewModel 测试，全部 96 项单元测试通过。
- [x] 2026-08-21：按小改动发布 `2.8.5 (30)`，Universal Release、签名验证与 `/Applications/Prism.app` 安装成功。
- [x] 2026-08-21：填写 Outcomes & Retrospective。

## Surprises & Discoveries

- 项目已经包含 `IPIPCurrentNetworkResponse` 和 `myip.ipip.net/json`，但当前只在海外 ipify 全部失败时作为主出口回退。新能力不能复用“仅失败才请求”的控制流，需要把解析与独立探测抽出来，同时避免重复实现响应校验。
- 规则分流环境可能同时存在两个真实出口：海外端点看到代理 IP，国内端点看到运营商 IP。这个差异正是新能力的价值，但仅凭目标域名无法保证请求绕过全隧道 VPN。
- IPIP 官方说明免费 MyIP 服务不提供质量承诺，因此不能把它并入主状态的成功条件，也不能用它的失败把 Prism 标记为离线。
- 现有 `IPAddressRow` 已实现复制、成功反馈、键盘与辅助功能。新增行应复用该组件，只增加可选的短状态说明，不创建新的卡片或复制逻辑。
- 当前 5 秒实时出口观察不能同步请求国内端点，否则会对免费服务造成不必要压力。国内探测应在启动、确认的主出口变化、网络变化、唤醒、手动刷新和现有分钟级资料校验时触发。

## Decision Log

- 2026-08-21：产品名称使用“国内出口 IPv4”，不用“非代理 IPv4”。只有端点返回中国地址且与主 IPv4 不同时，关系说明才显示“国内独立出口”。
- 2026-08-21：继续使用项目已接入的 `https://myip.ipip.net/json`，单请求会话、2 秒上限、禁用 HTTP 缓存。该请求与主出口刷新并行且完全独立失败。
- 2026-08-21：接受端点返回的有效 IPv4，即使位置不是中国；这种结果用于显示“国内流量可能仍走代理”，而不是丢弃后伪装成不可用。
- 2026-08-21：国内结果只保存在内存，不写历史、不写磁盘，避免新增持久化网络标识。刷新失败可暂时保留内存中的上次结果并明确标记“上次结果”。
- 2026-08-21：不把国内探测挂到 5 秒实时轮询；主出口确认发生变化时额外触发一次，稳定期间遵循用户现有的资料校验周期。
- 2026-08-21：Popover 复用现有地址卡。主信息可用时，顺序为公网 IPv4、公网 IPv6、国内出口 IPv4；主信息尚不可用时仍显示独立的国内 IPv4 行。
- 2026-08-21：本批按“小改动”发布。虽然涉及多个文件和并发状态，但不改变 Prism 的核心定位、持久化格式或外部接口权限。

## Context and Implementation Plan

### Milestone 1：独立探针与状态

新增 `DomesticIPv4Probing` 协议和 IPIP 实现。解析复用 `IPIPCurrentNetworkResponse`，严格要求有效 IPv4，记录 IPIP 返回的国家字段与检查时间。新增 `DomesticIPv4Status`（idle/loading/available/failed）与 `DomesticIPv4ViewModel`，取消过期请求、避免重叠，并在失败时保留上次内存结果。

关系由国内结果与当前主 IPv4 动态计算：地址相同为“与当前出口一致”；IPIP 国家为中国且地址不同为“国内独立出口”；非中国结果为“国内流量可能仍走代理”。关系随主出口变化立即重算，不需要等待 UI 重建。

### Milestone 2：刷新生命周期

`AppEnvironment` 创建并暴露国内 ViewModel；UI 测试使用固定中国 IPv4，不访问网络。`RefreshCoordinator` 在启动、网络变化、手动刷新、定期校验和唤醒时触发国内刷新，在离线或停止时更新/取消国内状态。主 `NetworkLookupService` 确认新的在线出口后也触发一次国内刷新，以覆盖不产生 NWPath 变化的代理规则切换。

国内探测不参与 `NetworkStatus`、GeoIP Provider 健康度、出口稳定器、通知或历史；它失败时主出口仍可正常显示和刷新。

### Milestone 3：Popover 与复制

扩展 `IPAddressRow` 支持可选的短说明文本，保持当前 30pt 复制按钮、成功反馈和 VoiceOver。Popover 在现有地址卡新增第三行，说明只使用次级文字，不新增彩色徽章或独立卡片。主信息不可用时，国内行仍可单独显示。

新增辅助功能标识 `popover.domestic-ipv4-row`。复制逻辑继续由 `IPAddressRow` 负责，因此新地址与现有地址拥有相同交互。

### Milestone 4：隐私、测试与发布

隐私页与 README 明确 `myip.ipip.net/json` 会用于独立国内出口观察，并注明规则代理与全隧道 VPN 的差异。自动测试覆盖：中国独立出口、与主出口一致、非中国/仍代理、无效 IPv6、失败保留、请求 no-cache 与 ViewModel 取消旧请求。执行项目小版本发布脚本，只有测试和 Universal Release 构建成功后才替换安装版。

## File-Level Changes

- `Prism/Models/DomesticIPv4Info.swift`：国内地址、状态和关系语义。
- `Prism/Services/DomesticIPv4Probe.swift`：IPIP 独立 IPv4 请求与响应校验。
- `Prism/ViewModels/DomesticIPv4ViewModel.swift`：可观察状态、取消、刷新与失败降级。
- `Prism/App/AppEnvironment.swift`：正式与 UI 测试依赖组装、主出口变化触发。
- `Prism/Services/RefreshCoordinator.swift`：启动、网络、手动、周期、休眠唤醒生命周期。
- `Prism/Views/Components/IPAddressRow.swift`：可选短说明，不复制现有按钮逻辑。
- `Prism/Views/MenuBar/MenuBarPopoverView.swift`：新增国内出口 IPv4 行。
- `Prism/Views/Settings/PrivacySettingsView.swift`：外部请求说明。
- `Prism/Resources/Localizable.xcstrings`：中英文状态与标签。
- `PrismTests/DomesticIPv4ProbeTests.swift`：解析、IPv4 校验、缓存策略和失败。
- `PrismTests/DomesticIPv4ViewModelTests.swift`：状态、关系、取消与保留结果。
- `README.md`：能力、服务用途和全隧道限制。
- `docs/execplans/prism-domestic-ipv4-exit.md`：持续更新实施记录。

## Validation and Acceptance

自动验证：

    xcodebuild -project Prism.xcodeproj -scheme Prism -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO test
    ./scripts/release.sh small
    defaults read /Applications/Prism.app/Contents/Info CFBundleShortVersionString
    defaults read /Applications/Prism.app/Contents/Info CFBundleVersion
    codesign --verify --deep --strict /Applications/Prism.app

不运行会接管屏幕的 UI 自动化。自动测试必须证明国内探测失败不改变主 `NetworkStatus`，请求不重叠且旧请求结果不会覆盖新结果。

可观察验收：

1. 在中国规则代理下打开 Popover，主出口可为海外国家；“国内出口 IPv4”显示中国运营商 IPv4，并标记“国内独立出口”。
2. 点击该行复制按钮，剪贴板得到完整 IPv4，按钮短暂显示“已复制”。
3. 全局代理或全隧道 VPN 下，若国内端点看到同一/海外 IP，显示“与当前出口一致”或“国内流量可能仍走代理”，不声称已绕过代理。
4. 手动刷新、切换网络、睡眠唤醒和主出口确认变化后，国内行自动更新；稳定期间不以 5 秒频率请求 IPIP。
5. IPIP 超时或不可用时，主 IPv4/IPv6 与 Popover 操作保持正常；国内行显示不可用或上次结果。
6. 最终版本、构建号、测试、签名和安装路径符合项目发布规则。

## Idempotence and Recovery

国内状态不持久化，因此不存在数据迁移或清理。重复刷新会取消旧任务；取消和 App 退出不应留下网络任务。新增依赖均有 UI 测试替身。发布脚本在测试或构建失败时恢复版本号并保留当前 `/Applications/Prism.app`。

## Outcomes & Retrospective

Prism 现在把国内出口 IPv4 作为独立、非阻塞状态展示在菜单栏 Popover。它不再依赖主出口是否为中国，也不把国内端点天然等同于绕过代理；中国且不同的地址显示“国内独立出口”，相同地址显示“与当前出口一致”，非中国结果显示“国内流量可能仍走代理”。新增行复用了现有 `IPAddressRow`，因此复制、成功反馈、键盘与辅助功能行为保持一致。

国内探测只在启动、网络或主出口变化、唤醒、手动刷新与分钟级资料校验时发生，没有进入 5 秒实时循环。请求采用单次会话、2 秒上限和禁用缓存；超时或服务失败不会改变主 `NetworkStatus`。结果只在运行内存保留，失败时可标记上次结果，退出后不持久化。

最终自动验证为 96 项单元测试全部通过，`2.8.5 (30)` Universal Release 构建和严格签名验证成功，并安装到 `/Applications/Prism.app`。按用户要求未运行会接管屏幕的 UI 自动化；真实规则代理与全隧道差异留给用户在实际网络环境中观察。
