# Prism 代理断开识别与真实断网恢复 — Debug ExecPlan

这是一份持续维护的调试计划。项目内 `.agent/PLANS.md` 与全局 `~/.codex/PLANS.md` 均不存在，因此沿用仓库已有 ExecPlan 的自包含结构。用户确认前只允许完善本计划，不修改应用代码、资源、版本或安装包。

## Purpose

当前从新加坡代理切回国内直连时，Prism 可能先进入 `offline(previous: Singapore)`，界面继续使用旧信息渲染新加坡国旗、国家和城市，同时显示“已断开”；部分代理/VPN 关闭不会触发可靠的 `NWPathMonitor` 事件，或者恢复事件受旧刷新配置限制，导致应用没有及时探测中国直连出口。这破坏了 Prism 最核心的“当前出口”可信度。

本修复要明确区分三种用户可观察状态：

1. 代理关闭但互联网仍可用：立即触发全新连接探测，短暂显示“正在确认新出口”，确认后展示中国直连地址与地区，不出现“新加坡已断开”。
2. 网络真正断开：经过很短的防抖后只显示中性的离线状态，不显示旧国家、国旗或 IP；旧结果仅保留在内部供恢复与比较使用。
3. 网络恢复：无论周期资料校验是否开启，都立即重建探测连接并刷新当前出口，不停留在“已断开”。

## Progress

- [x] 2026-08-21：复核 `NetworkMonitor → RefreshCoordinator → RealtimeExitMonitor → NetworkLookupService → NetworkStatus/UI` 全链路。
- [x] 2026-08-21：确认旧国家与“已断开”并存来自 `offline(previous:)` 仍被 `NetworkStatus.info` 当作当前展示数据。
- [x] 2026-08-21：确认当前只监听 `NWPathMonitor`，没有系统代理配置变更监听；代理开关不保证触发及时刷新。
- [x] 2026-08-21：确认恢复刷新受 `refreshOnNetworkChange` 守卫影响，而实时出口正确性不应依赖周期资料设置。
- [x] 2026-08-21：创建本 Debug ExecPlan，等待用户确认。
- [x] 2026-08-21：用户确认本计划，进入 Implementation。
- [x] 2026-08-21：实施离线展示隔离、双向防抖、系统网络/代理配置监听和连接代际失效。
- [x] 2026-08-21：增加丢弃旧请求、强制排队新观察以及漏失恢复事件时由成功探测自愈的逻辑。
- [x] 2026-08-21：36 项相关单元测试通过，随后新增的离线自愈路径 11 项相关测试通过；未运行 UI 自动化。
- [x] 2026-08-21：106 项完整单元测试通过，Universal Release 构建与签名通过，安装 Prism `2.8.8 (33)` 至 `/Applications/Prism.app`。
- [x] 2026-08-21：以“修复代理断开识别与网络恢复状态”完成本地 Git 交付提交，不 push、不打标签。
- [x] 2026-08-21：填写 Outcomes & Retrospective。

## Surprises & Discoveries

- `NetworkStatus.info` 对 `.offline(previous:)` 返回旧 `NetworkInfo`，因此菜单栏和弹窗把旧新加坡国旗与位置继续作为当前内容渲染；状态徽章同时读取 `.offline`，形成语义冲突。
- `NetworkMonitor` 对 `unsatisfied` 立即发出离线，对恢复却延迟 100ms。代理切换造成的瞬时路径抖动因此很容易先闪出“旧国家 + 已断开”。
- `RefreshCoordinator` 仅在 `refreshOnNetworkChange` 为真时处理 `.onlineChanged`。该值虽然已没有直接用户界面入口，但历史设置仍可能为假，使应用从离线恢复后不主动刷新。
- `IPifyExitAddressProbe` 使用最长 1.5 秒轮换的 `URLSession`。代理配置刚变化时，主动刷新仍可能复用绑定旧代理路径的连接；事件处理必须显式失效当前连接代际。
- 即使后台探针已经重新成功，如果地址与离线前一致，原来的 `.unchanged` 分支也不会刷新状态，应用可能永久停留在“已断开”；成功观察现会在状态为 offline 时强制恢复在线。
- 海外 ipify 成功当前一律标为 `.proxy`。本计划不以“服务域名海外”推导线路真值；中国 IP 的最终显示以同一观察地址的 GeoIP/国内回退结果为准，路线语义如需进一步精确将记录为后续项，避免本次范围失控。

实施阶段发现的新事实必须追加到这里，不覆盖原记录。

## Decision Log

- 2026-08-21：将本批次按“小改动”发布。它修正既有核心状态流与事件监听，不改变产品架构或新增用户功能；成功后运行 `./scripts/release.sh small`。
- 2026-08-21：离线状态采用“保留内部数据、隐藏当前展示”的语义。缓存与 `previous` 不删除，以便恢复比较；所有当前界面和菜单栏不得把它渲染成现时国家或国旗。
- 2026-08-21：真实离线增加约 300ms 防抖，避免代理切换的瞬时 `unsatisfied` 污染 UI；恢复事件保持约 100ms 防抖并立即刷新。
- 2026-08-21：新增系统代理配置监听，覆盖全局与各网络服务的 Proxies 动态键；网络路径变化继续覆盖 VPN/TUN 与真实断网。两类事件统一进入强制重新观察入口。
- 2026-08-21：代理/路径变化时显式失效出口探针的 URLSession 连接代际、重置未确认候选并保证至少排队一次新观察，防止正在执行的旧请求吞掉新事件。
- 2026-08-21：网络恢复与代理配置变化属于“当前事实正确性”，不受周期资料校验设置控制；周期设置只决定稳定状态下的资料重查。
- 2026-08-21：遵循用户偏好，不运行会控制鼠标和屏幕的 UI 自动化；以状态机、事件流和服务单元测试加 Release 构建验证。
- 2026-08-21：SystemConfiguration 监听范围从 Proxies 扩展到全局与服务级 IPv4/IPv6、全局 DNS 和代理键，以覆盖不使用传统系统代理键的 VPN/TUN 路由切换；事件统一做 120ms 合并。
- 2026-08-21：为避免在途 GeoIP 晚到后覆盖离线或新网络结果，网络环境变化会同时使观察 generation 失效并取消 `NetworkLookupService` 的在途刷新。

## Architecture and Implementation

### Milestone 1：离线展示语义与防闪烁

调整 `NetworkStatus` 的展示信息语义：`.offline(previous:)` 继续携带内部旧值，但不再通过当前展示入口暴露。菜单栏、弹窗和 Dashboard 因而只显示离线图标与说明，不显示旧国旗、国家、城市或 IP。弹窗在真实离线时也不渲染“上次国内 IPv4”卡片，避免把历史地址误认为当前地址。

调整 `NetworkMonitor`，对真实离线和恢复使用可取消防抖。短暂 `unsatisfied → satisfied` 不发布离线；持续断网约 300ms 后发布离线，恢复约 100ms 后发布在线变化。

### Milestone 2：代理配置事件与强制新观察

新增轻量 `ProxyConfigurationMonitor`，通过 SystemConfiguration 动态存储监听全局和服务级代理配置变化，输出可测试的异步事件流。`RefreshCoordinator` 同时消费网络路径与代理配置事件。

为 HTTP 客户端/出口探针增加显式连接代际失效能力。`RealtimeExitMonitor` 提供“网络环境已变化”的入口：使当前连接失效、重置 stabilizer、进入 burst，并确保即使已有观察正在运行也会在其后执行一次新的强制观察。国内 IPv4 探测同步刷新。

### Milestone 3：恢复逻辑与竞态收敛

网络恢复不再受遗留 `refreshOnNetworkChange` 守卫阻塞。重复的路径与代理事件由已有串行 actor/coalescing 机制合并，但不得丢失最后一次强制刷新。晚到达的旧请求不得覆盖新网络环境结果。

确认后的中国地址通过现有 exact observation 进入 GeoIP、历史和通知；离线本身不写入出口历史，恢复后只有实际地址变化才新增一条记录。

### Milestone 4：验证、发布与安装

补充纯单元测试覆盖离线不暴露旧展示、瞬时断链防抖、持续断网、恢复强制刷新、代理事件强制新连接、进行中请求后的排队刷新，以及新加坡代理到中国直连的完整状态序列。运行相关测试与完整单元测试，不启动 UI 自动化。

全部通过后运行 `./scripts/release.sh small`。脚本完成单元测试和 Universal Release 构建后才能替换 `/Applications/Prism.app`，随后验证版本、构建号、架构与签名，并使用中文信息执行一次本地 Git 提交，不 push、不打标签。

## File-Level Changes

- `Prism/Models/NetworkStatus.swift`：区分当前展示信息与内部保留信息，提供明确离线判断。
- `Prism/Services/NetworkMonitor.swift`：对离线/恢复做双向可取消防抖，并支持测试注入。
- `Prism/Services/ProxyConfigurationMonitor.swift`（新增）：监听 macOS 系统代理配置变化并输出事件。
- `Prism/Services/HTTPClient.swift`：增加线程安全的当前连接代际失效能力。
- `Prism/Services/ExitAddressProbe.swift`：把强制连接失效传递给生产出口探针。
- `Prism/Services/RealtimeExitMonitor.swift`：新增网络环境变化入口，重置候选并保证新观察不会被在途请求吞掉。
- `Prism/Services/RefreshCoordinator.swift`、`Prism/App/AppEnvironment.swift`：协调路径、代理、断网与恢复事件，恢复时无条件刷新。
- `Prism/Views/MenuBar/MenuBarPopoverView.swift` 及必要的 Dashboard/菜单栏调用点：真实离线只显示中性离线内容。
- `PrismTests/NetworkStatusTests.swift`、`NetworkMonitorTests.swift`、`RealtimeExitMonitorTests.swift`、`HTTPClientTests.swift` 或等价现有测试文件：覆盖状态、竞态与连接重建。
- `README.md`：说明代理/VPN 切换识别、离线展示和联网恢复行为。
- `Prism.xcodeproj/project.pbxproj`：仅由发布脚本更新版本与内部构建号；若工程非自动同步目录，才登记新增源码。

实际文件归属允许小幅调整，但用户行为与验证标准不得改变；偏差必须记录到 Decision Log。

## Validation and Acceptance

### 自动验证

    xcodebuild -project Prism.xcodeproj -scheme Prism -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
    ./scripts/release.sh small
    defaults read /Applications/Prism.app/Contents/Info CFBundleShortVersionString
    defaults read /Applications/Prism.app/Contents/Info CFBundleVersion
    lipo -archs /Applications/Prism.app/Contents/MacOS/Prism
    codesign --verify --deep --strict /Applications/Prism.app

不会执行 `PrismUITests`，也不会通过 Computer Use 控制鼠标或屏幕。

### 行为验收

1. 新加坡代理稳定时显示新加坡。
2. 关闭代理但底层互联网可用时，不出现“新加坡已断开”；短暂确认后显示中国及当前国内 IP。
3. 快速关闭再开启代理时，旧请求不得覆盖最终网络状态，历史不产生无效离线条目或重复出口变化。
4. Wi-Fi/网线突然真正断开时，约 300ms 后菜单栏和弹窗只显示离线状态，不显示旧国家、国旗或 IP。
5. 网络恢复后立即重新探测；即使周期资料校验关闭，也能离开“已断开”并展示当前出口。
6. 探测服务暂时失败时使用“暂时无法更新”而非“已断开”，并清楚区分服务故障与真实断网。

## Idempotence and Recovery

代理与路径监听的 `start/stop` 必须幂等，不能在应用生命周期、睡眠/唤醒或重复设置变化后创建多个流。强制刷新事件可以重复到达，但只能合并为有界的新观察，不形成刷新风暴。连接失效只取消 Prism 自己的 URLSession，不修改系统代理/VPN 设置。

实现或验证失败时不得覆盖现有 `/Applications/Prism.app`。发布脚本负责在失败时恢复版本字段；已有缓存、历史和设置格式保持兼容，不通过清空用户数据规避问题。

## Outcomes & Retrospective

本次把“旧出口缓存”“当前展示信息”和“真实离线”分开：离线仍在内部保留上次已确认出口用于恢复比较，但菜单栏、弹窗和 Dashboard 不再显示旧国家、国旗或 IP。网络路径使用 300ms 离线/100ms 恢复防抖；SystemConfiguration 订阅系统代理、服务路由、IPv4/IPv6 与 DNS 变化。任何环境变化都会失效 HTTP 连接代际、取消在途 GeoIP、废弃旧 observation generation，并在已有探测完成后保证补做一次新观察。

恢复逻辑不再依赖周期资料校验设置；即使系统漏发恢复事件，后台成功探测也会把 offline 状态恢复为 online。代理关闭后若海外链不可用，国内回退仍执行连续两次确认，正常会在 burst 窗口内切换为中国直连；真实断网则保持中性离线展示。

最终完整单元测试为 106/106 通过；UI 测试在 Scheme 中保持 skipped，未运行任何鼠标或屏幕自动化。Universal Release 与签名验证通过，发布为 Prism `2.8.8 (33)` 并安装到 `/Applications/Prism.app`。由于遵循用户要求未自动操作本机代理/VPN，真实代理客户端的开关时延仍需用户日常使用验证；代码同时保留 5 秒稳定轮询作为系统事件漏失的兜底。
