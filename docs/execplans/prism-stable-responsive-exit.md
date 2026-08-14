# Prism 稳定实时出口与体验优化 — Feature ExecPlan

这是一份持续维护的实施计划。项目与全局 `PLANS.md` 模板均不存在，因此使用自包含结构记录 Purpose、Progress、Decision Log、Surprises & Discoveries、Validation 与 Outcomes。用户确认本计划前，只允许完善本文件，不修改应用代码、资源或版本。

## Purpose

Prism 当前可以在 macOS 菜单栏显示公网出口，但真实运行中出现两个彼此关联的问题：应用为了追求 250ms 检测，稳定后台仍持续创建 HTTPS 请求并占用约 5.6%–9.3% CPU；在 OneBox 规则分流环境中，海外服务看到东京代理出口、国内服务同时看到上海直连出口，任意一次海外请求短暂失败都会把上海当作新主出口，随后又切回东京。真实历史在 55 秒内记录了 6 次 JP/CN 往返。

本功能要把“快”重新定义为可观察且可信：首次发现候选地址后立即在菜单栏和窗口显示“正在确认”，通常在 1 秒内提交稳定地区；瞬时失败不改变主出口、不写历史、不通知。稳定后台降低公网请求频率和会话创建成本，网络或候选发生变化时再临时进入 250ms burst。应用还要明确区分代理、直连和规则分流，并整理 Dashboard、历史与设置，使用户能理解当前出口、确认状态和数据来源。

网络 RTT 决定了绝对的几毫秒完成不可保证。本计划的可验收目标是：普通可达环境下候选反馈不晚于一次稳态探测（目标 1 秒内），候选出现后 250ms 级连续确认，最终地区通常在 1 秒左右完成；黑洞或 Provider 故障时有明确上限和旧数据状态，不出现无期限等待。

## Progress

- [x] 2026-08-14：完成运行版 UI 截图、代码链路和后台资源审查。
- [x] 2026-08-14：确认真实历史在 55 秒内出现 6 次东京/上海往返，稳定后台 CPU 样本约 5.6%–9.3%、内存约 82MB。
- [x] 2026-08-14：创建本 Feature ExecPlan。
- [x] 2026-08-14：用户确认本计划，进入 Implementation。
- [x] 2026-08-14：实施统一 `ExitObservation`，启动、手动、周期、网络变化和唤醒均消费 exact observation，消除二次决定出口。
- [x] 2026-08-14：实施候选确认状态机、路线/来源语义、Provider 30 秒熔断与 1s/250ms 自适应探测。
- [x] 2026-08-14：实施 verifying 分阶段状态、300ms hedged GeoIP 回退、短超时与双栈观察。
- [x] 2026-08-14：实施 confirmed-only 写入链路、变化式历史界面、旧 JSON 兼容和通知去抖。
- [x] 2026-08-14：整理 Dashboard、General、Menu Bar、Network Settings 的信息层级与 Provider 健康信息。
- [x] 2026-08-14：完成 Reduce Motion、Reduce Transparency、Increase Contrast 与 VoiceOver 状态反馈。
- [x] 2026-08-14：严格 clean build 与 54 项自动测试通过；已完成当前 OneBox 规则分流稳定性、运行版 UI 与 30 秒资源采样。
- [x] 2026-08-14：按大改动发布 `2.0.0 (8)`，签名 Universal Release 已替换并启动 `/Applications/Prism.app`。
- [ ] 获得动作时确认后执行 OneBox/VPN 开关真机切换，记录日本→中国上海→代理出口的确认时延与历史条数。
- [x] 2026-08-14：修复 OneBox 国家节点切换回归；增加连接代际测试，55 项测试通过，最终发布 `2.2.0 (10)` 并替换安装版。
- [ ] 填写 Outcomes & Retrospective。

## Surprises & Discoveries

- `RealtimeExitMonitor.pollNow()` 先得到 `observedAddress`，随后调用无参数 `NetworkLookupService.refresh()`；后者通过 `PublicIPService` 再查询一次地址。检查与使用不是同一份网络事实，规则分流或瞬时失败时可以得到相反结果。
- `IPifyExitAddressProbe` 依次等待 IPv4 1 秒、IPv6 1 秒、国内 IPIP 2 秒，最坏仅地址阶段就可约 4 秒；完整 GeoIP 链的 ipwho.is 与 ip.guide 默认单项请求上限仍为 8 秒，最终依赖 15 秒总截止。
- `lastTriggeredChange` 在刷新结果未包含候选时仍保留，并把同一候选抑制 5 秒。这既没有稳定确认候选，也可能延迟真实变化。
- 实时刷新默认 `showLoading: false`。地址正在变化时 UI 继续展示旧城市且没有活动提示，这是用户认为“没有切换”的重要感知原因。
- “自动刷新关闭”只关闭周期完整刷新，250ms 实时探测仍永久开启；通用设置中的两组文案没有解释两者的差别。
- `SectionCard` 在 Reduce Transparency 开启时仍继续叠加 material background；`RefreshGlyph` 和 `NSPopover` 动画也没有读取 Reduce Motion。
- 统一观察管线后发现原先的轻探针只返回“主地址”，会丢弃并发拿到的另一个地址族；已改为同一 `ExitObservation` 保存本轮 IPv4 与 IPv6，IPv4 仍为首选 GeoIP 输入。
- macOS 26 SDK 已废弃旧的 `NSAccessibilityPostNotificationWithUserInfo` Swift 入口；VoiceOver 公告改用 `NSAccessibility.post(element:notification:userInfo:)`，同时保持 macOS 14 部署目标。
- 1.6 缓存不含路线字段。如果地址未变化，普通稳定器会永久视为 unchanged；升级逻辑现把“地址相同但路线 unknown”的首次有效观察立即确认为路线元数据更新。
- 2.0 为降低 CPU，把实时 ipify 客户端从每次新连接改成了永久 `URLSession`。OneBox 切换国家节点时本机代理监听地址不变，现有 HTTPS/HTTP2 连接可继续绑定旧上游节点，因此探针可能持续得到旧国家；关闭/开启 OneBox会中断连接，所以该路径反而正常。这与用户真机现象完全一致。

实施阶段遇到的新事实必须继续追加在这里，不覆盖既有记录。

## Decision Log

- 2026-08-14：将本批次定义为“大改动”。它重构核心检测架构、状态模型和多个主要界面，按项目版本规则从 `1.6.0 (7)` 提升到 `2.0.0 (8)`；只有全部验证成功后才由发布脚本落地版本并覆盖安装版。
- 2026-08-14：采用单一网络事实事务。探针返回 `ExitSnapshot`，包含 IPv4/IPv6、主地址、探针来源、路线类型、观察时间，以及仅限本次事务可复用的国内位置载荷；GeoIP、状态、历史与通知不得重新选择另一出口。
- 2026-08-14：采用 `stable → pending → confirmed` 状态机。第一次不同候选立即发布 pending；正常情况下同一候选连续两次成功后提交。`NWPathMonitor`、代理配置变化或手动刷新可以触发 burst，但不能绕过响应合法性检查。
- 2026-08-14：历史与通知只消费 confirmed 结果。pending、单次失败和被撤销候选只进入诊断日志，不进入用户历史。
- 2026-08-14：稳定期目标每 1 秒执行一次轻探测；发现候选、系统网络变化、唤醒或手动刷新后，临时以 250ms 检查 5 秒。连续失败的 Provider 使用指数式或分级熔断，避免每个周期反复等待同一故障服务。
- 2026-08-14：保留无 HTTP 响应缓存语义，但不再把“结果新鲜”与“每次创建完整 URLSession”绑定。探测客户端按受控 generation 复用 ephemeral session，并在系统路径变化、候选异常或最长 1 秒时重建连接池，兼顾资源与旧代理连接风险。
- 2026-08-14：GeoIP 使用明确的单 Provider 1–2 秒上限；主服务在 250–300ms 内未完成时启动备选服务，首个合法且匹配同一 IP 的结果获胜，其余任务取消。国内 IPIP 探测已经携带匹配地址的位置时，在同一事务内直接复用，不视为城市缓存。
- 2026-08-14：`NetworkStatus` 新增 verifying 语义，继续携带上次 confirmed 信息和候选地址。所有菜单栏样式在 verifying、stale、offline 时都必须带非颜色状态符号，不能只有 `statusAndFlag` 模式才表达状态。
- 2026-08-14：规则分流不是错误。数据模型明确表示 proxy、direct、split 和 unknown；主标签在海外代理探针稳定可用时显示代理出口，国内直连作为诊断/详情信息；代理链确认不可用且国内链稳定后才把国内出口提升为主出口。
- 2026-08-14：不新增第三方 Swift 包、不接入特定 VPN 客户端私有 API、不引入账号或遥测。通用性优先于对 OneBox 的专有耦合。
- 2026-08-14：`PublicIPService` 保留用于旧单元测试与兼容边界，但生产 `RefreshCoordinator` 的所有刷新入口改由 `RealtimeExitMonitor.refreshNow()` 先生成 exact observation；这样不需要在一次发布中破坏既有服务协议。
- 2026-08-14：Provider 健康状态保持运行期内存数据，不落盘。连续两次非取消失败后暂停该 Provider 30 秒，成功即恢复；设置页仅展示可操作的最近耗时/暂时停用状态，不暴露内部错误码。
- 2026-08-14：节点切换回归采用“短寿命连接代际”修复，不恢复 1.6 的永久 250ms 新会话。稳定探测仍为 1 秒；同一轮 IPv4/IPv6 共享会话，下一代主动失效旧连接。初版 500ms 代际实测 CPU 中位数约 2.2%，略高于 ≤2% 目标，因此最终调整为 1.5 秒：稳定期约每两轮重建一次，国家节点切换最迟约 2 秒获得全新连接。

## Architecture and Implementation

### Milestone 1：统一出口观察事务

新增 `ExitObservation`、`ExitSource`、`NetworkRouteMode` 等 Sendable 模型。把 `ExitAddressProbing.fetchPrimaryAddress()` 改为返回观察对象：IPv4/IPv6 并发请求，海外结果和国内结果都有独立来源与耗时；国内 IPIP 的位置数组作为仅本次观察可用的数据。`NetworkLookupService` 增加 `confirm(observation:)` 或等价接口，以观察中的确定地址为 GeoIP 输入，禁止内部再调用 `PublicIPService` 决定另一个出口。

手动刷新、启动刷新和周期资料校验继续可以发起完整观察，但它们也必须先产生观察，再进入同一确认管线，避免存在两套出口选择规则。

### Milestone 2：稳定器、自适应调度与服务健康

新增隔离的 `ExitStabilizer`，跟踪 confirmed、pending、连续成功数、失败数、首次/最近观察时间和路线模式。相同 confirmed 地址只更新时间，不触发 GeoIP；不同候选第一次出现就发布 verifying，连续确认后才调用完整解析。候选消失则恢复 stable，不写历史。

`RealtimeExitMonitor` 改为自适应节拍：平稳 1 秒；网络/代理事件、唤醒、手动刷新和 pending 状态进入 250ms burst 5 秒；睡眠暂停。新增 Provider 健康状态与熔断，重复超时不会在每个周期串行阻塞。调度时间与 sleep 通过可注入时钟/闭包测试，不依赖真实等待。

### Milestone 3：分阶段解析与状态流

`NetworkStatus` 增加 verifying；`NetworkLookupService` 分开“地址已观察”“出口已确认”“GeoIP 已解析”。候选一出现先把 verifying 发到 ViewModel；确认后用同一地址做 GeoIP。国内位置载荷可直接映射；海外 Provider 使用短上限与 hedged fallback。IPv4 先用于位置并发布，IPv6 若尚未结束则作为同一 confirmed 出口的补全更新，不制造第二条历史。

取消必须从 ViewModel/Coordinator 一直传播到探针和 Provider；后到达的旧 generation 结果不得覆盖更新的候选。保留最后成功信息用于 stale/offline，但不得把它标记为新确认。

### Milestone 4：历史、通知和诊断

历史存储只接收 confirmed `NetworkInfo`。历史界面由相邻 confirmed 条目推导“旧出口 → 新出口”，显示时间、主 IP、国家/城市和路线类型；首次条目仍为基线。若同一批升级前历史已存在抖动，不自动破坏用户数据，仅对新事件应用确认规则。

通知只在 confirmed ID 变化时发送。Network Settings 展示当前路线模式、当前服务、最近成功耗时与健康状态；Provider 详细顺序放在高级 DisclosureGroup，不把内部实现占据默认层级。

### Milestone 5：UI 层级与无障碍

Dashboard 只保留一个主状态徽章；Hero 展示国家、完整城市、路线模式、主 IP 和“多久前确认”。详情改为自适应 Grid，长组织名和 IPv6 允许合理换行或中间截断并带 Tooltip。verifying 时沿用旧 confirmed 内容，但显著显示“正在确认新出口”，防止把候选当真值。

General Settings 将“自动刷新”改为“定期重新校验资料”，关闭时隐藏或禁用周期选择；独立说明实时切换检测为自适应模式。菜单栏预览增加正常、确认中、离线示例。Logo 保留但缩小并减少单独卡片空间。

动画读取 Reduce Motion；材质真正遵循 Reduce Transparency；Increase Contrast 提高分隔和状态边界。VoiceOver 对 verifying→confirmed 进行一次语义公告，不播报被撤销的每次 pending。

### Milestone 6：验证、发布与安装

每个里程碑先运行相关 XCTest，再运行完整 `xcodebuild test` 与严格 build。真机先记录 VPN 开启稳定状态，再在获得操作时确认后切换 OneBox，测量候选提示、confirmed 地区、历史与 CPU。系统 VPN/代理开关属于安全敏感设置，必须在实际点击前再次取得用户确认，ExecPlan 确认不能代替动作确认。

全部通过后运行 `./scripts/release.sh major`，由脚本把版本从 `1.6.0 (7)` 提升为 `2.0.0 (8)`、构建 Universal Release、签名并替换 `/Applications/Prism.app`。失败时不覆盖现有安装版。

## File-Level Changes

- `Prism/Models/ExitObservation.swift`：新增出口观察、来源、路线模式和本次国内位置载荷。
- `Prism/Models/NetworkStatus.swift`：增加 verifying 与状态辅助语义。
- `Prism/Models/NetworkInfo.swift`、`NetworkHistoryEntry.swift`：保存已确认路线类型与必要来源信息，并兼容旧 JSON。
- `Prism/Services/ExitAddressProbe.swift`、`PublicIPService.swift`：合并为一致观察规则，IPv4/IPv6 并发、返回 exact snapshot。
- `Prism/Services/ExitStabilizer.swift`：新增候选连续确认、撤销、路线优先级和防抖。
- `Prism/Services/ProviderHealth.swift`：新增耗时、失败计数与熔断状态。
- `Prism/Services/RealtimeExitMonitor.swift`：自适应节拍、burst、generation 与稳定器集成。
- `Prism/Services/NetworkLookupService.swift`：消费 exact snapshot、分阶段发布、hedged GeoIP、旧结果防覆盖。
- `Prism/Services/GeoIPProvider.swift` 及具体 Provider：单项短超时、并发回退和服务健康记录。
- `Prism/Services/RefreshCoordinator.swift`、`NetworkMonitor.swift`：统一启动、周期、网络变化、代理变化和唤醒触发。
- `Prism/Persistence/NetworkHistoryStore.swift`：confirmed-only 写入与旧格式兼容。
- `Prism/StatusBar/MenuBarLabelRenderer.swift`、`StatusBarController.swift`、`PopoverHost.swift`：verifying 状态、稳定标签和 Reduce Motion。
- `Prism/Views/Dashboard/DashboardOverviewView.swift`、`CountryHeroView.swift`、`StatusBadge.swift`：新层级、路线与确认状态。
- `Prism/Views/History/HistoryView.swift`：变化式历史行与抖动免疫展示。
- `Prism/Views/Settings/GeneralSettingsView.swift`、`MenuBarSettingsView.swift`、`NetworkSettingsView.swift`：概念重命名、状态预览和高级诊断。
- `Prism/Views/Components/SectionCard.swift`、`RefreshGlyph`：辅助功能修正。
- `Prism/Resources/Localizable.xcstrings`：完整 en / zh-Hans 新文案。
- `PrismTests/*`、`PrismUITests/*`：新增状态机、时序、回退、历史、设置与 UI 状态覆盖。
- `README.md`、`PRODUCT_SPEC.md`、`docs/execplans/prism-stable-responsive-exit.md`：同步行为、限制、验证数据与复盘。

实际文件边界可因 Swift 类型归属做小幅调整，但不得改变上述用户行为；任何调整必须写入 Decision Log。

## Validation and Acceptance

### 自动测试

- 观察：IPv4/IPv6 部分成功、并发完成、国内响应、海外/国内同时可用、分流来源、非法地址、超时、取消、后到达旧 generation。
- 稳定器：单次异常不提交、同候选连续两次提交、候选撤销、A→B→A 不写历史、网络事件 burst、稳定期节拍、熔断开启/恢复。
- exact snapshot：探针候选与 GeoIP/历史使用同一 IP，确认阶段不进行第二次出口选择。
- 状态：首次 verifying、带旧值 verifying、online、stale、offline；菜单栏所有模式都有非颜色状态表达。
- GeoIP：主服务快速成功、hedged backup 获胜、取消 loser、单项上限、IPIP 本次载荷复用、城市无磁盘缓存。
- 历史与通知：只记录 confirmed、IPv6 补全不制造重复、100 条裁剪、旧 JSON 解码、变化行顺序。
- UI：Dashboard verifying、历史变化行、设置术语与三种菜单预览、键盘快捷键、Reduce Motion/Transparency。

执行：

    xcodebuild -project Prism.xcodeproj -scheme Prism -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
    xcodebuild -project Prism.xcodeproj -scheme Prism -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO clean build
    ./scripts/release.sh major
    defaults read /Applications/Prism.app/Contents/Info CFBundleShortVersionString
    defaults read /Applications/Prism.app/Contents/Info CFBundleVersion
    codesign --verify --deep --strict /Applications/Prism.app

Swift 6 严格并发继续开启，项目 Warning 视为 Error。

### 真机矩阵

1. 稳定 VPN 运行 5 分钟：不得出现国内回退历史；窗口关闭后采样 30 秒，目标 Release 版 CPU 中位数不高于 2%，且无持续上升。
2. 日本节点切新加坡：菜单栏在首次候选后立即显示确认状态，通常约 1 秒内成为新加坡；历史只新增一条 confirmed 变化。
3. VPN 关闭：海外链失败后稳定提升国内出口，显示中国和英文城市；不得先后反复 JP/CN。
4. VPN 重开：国内转代理只新增一次历史与最多一次通知。
5. OneBox 规则模式保持不变：海外代理为主出口，国内 IPIP 仅作为分流诊断，不因单次海外超时抢占主出口。
6. 断网、Provider 超时、睡眠/唤醒、IPv4-only、IPv6、浅/深色、高对比度、Reduce Motion、简中/英文分别检查。

### 最终验收标准

- 探针、GeoIP、历史和通知消费同一 exact snapshot。
- 稳定网络中单次海外失败不切到上海；5 分钟不产生虚假历史。
- 候选变化有即时 verifying 反馈，正常服务下地区通常约 1 秒完成。
- confirmed-only 历史不再出现瞬时 A→B→A 污染。
- 稳定后台 Release CPU 30 秒中位数目标 ≤2%；若硬件噪声导致未达标，必须记录实测与继续优化，不能只以测试通过交付。
- 所有自动测试和严格构建通过；最终安装版为 `2.0.0 (8)`。

## Idempotence and Recovery

新增 JSON 字段必须提供默认值或自定义解码，确保 1.6.0 的缓存、历史和设置可继续读取。状态机与 Provider 健康只保存必要、可安全丢弃的运行状态，不允许损坏时阻止启动。重复 start/stop、睡眠/唤醒和设置变化不得创建多个探测循环。

各里程碑均先测试后进入下一阶段。发布脚本失败时恢复项目版本并保留现有 `/Applications/Prism.app`。真机切换失败时保留测试日志与安装前版本，不通过反复删除用户缓存来掩盖问题。

## Outcomes & Retrospective

- 统一 exact observation 已覆盖启动、手动刷新、周期校验、系统网络变化、唤醒和实时检测。探针与 GeoIP 不再二次选择不同 IP；单次国内回退先进入 verifying，撤销后不写历史。
- 当前真实 OneBox 分流同时返回海外 `54.95.102.233`（日本东京）与国内 `180.173.166.20`（中国上海）。2.0.0 稳定显示日本东京，30 秒观察前后历史均为 7 条，没有新增上海回退或 JP/CN 往返。
- Release 版关闭窗口后的 10 个 CPU 样本为 `0.0, 0.7, 0.9, 0.9, 0.9, 1.1, 0.9, 0.9, 0.9, 0.9%`，中位数约 0.9%，内存约 40MB；相比审查时 1.6.0 的约 5.6%–9.3% CPU 和 82MB 明显降低，达到 ≤2% 目标。
- 严格 Swift 6 clean build 通过，54 项测试 0 失败；版本为 `2.0.0 (8)`，Universal arm64/x86_64，本地签名与 `codesign --deep --strict` 验证通过，安装路径为 `/Applications/Prism.app`。
- 已通过已安装 App 的无障碍树和截图检查 Dashboard、General 与 Network Settings；路线、双栈、确认节拍、Provider 与中文信息均可读。小鹿图标沿用用户提供的资产。
- 尚未代用户切换 OneBox/VPN；该动作会改变安全敏感的网络设置，必须在实际点击前单独确认。自动测试已覆盖代理→直连需连续确认、直连同路线换 IP 立即提交、候选撤销、exact snapshot 与 confirmed-only 历史。
- 用户自行确认 2.0 的 OneBox 关闭/开启能够正确切换，但发现代理内部国家节点切换回归。根因是永久 URLSession 复用了旧代理隧道；2.2 改为 1.5 秒连接代际并保留每秒观察。同路线新 IP 的立即提交测试与连接代际轮换测试均通过，等待用户对实际国家节点切换做最终反馈。
- 2.2 Release 稳态 10 个 CPU 样本为 `0.0, 1.3, 1.3, 1.9, 1.3, 1.7, 1.3, 1.7, 1.3, 2.0%`，中位数约 1.3%，最高 2.0%，内存约 41MB；达到既定后台资源目标。最终安装版本现为 `2.2.0 (10)`。
- 已知限制：公网出口位置是 Provider 对运营商网关的估算；物理移动但公网出口不变时无法推断城市。250ms 是候选阶段调度目标，最终显示仍受 HTTPS RTT 影响，不能保证绝对毫秒完成。
