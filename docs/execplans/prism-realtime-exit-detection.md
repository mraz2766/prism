# Prism 亚秒级出口检测修复 — Debug ExecPlan

这是一份持续更新的调试实施计划。实施过程中维护 `Progress`、`Surprises & Discoveries`、`Decision Log` 和 `Outcomes & Retrospective`。

## Purpose

当用户在 VPN 或代理客户端中切换节点时，即使 macOS 仍认为网络路径保持在线，Prism 也应以 250ms 目标节拍发现公网出口地址变化，自动刷新国家或地区，并同步更新菜单栏、Popover、Dashboard、缓存和历史。稳定网络下只执行轻量地址探测，不重复请求 GeoIP 或隐私分类；真实发现时间仍取决于 HTTPS 往返耗时。

## Progress

- [x] 2026-08-14：处理 `1.2.0` 回归：运行中真实出口已为新加坡 `18.141.204.177`，Prism 仍显示香港 `18.162.245.88`；定位为出口探测复用了绑定旧隧道的持久连接。
- [x] 2026-08-14：按用户追加要求将探测调度从 1 秒提升为 250ms 固定节拍；串行调度且扣除请求耗时，避免请求堆积。
- [x] 2026-08-14：移除公网地址探测和完整双栈查询对旧持久连接的依赖，并增加连接生命周期回归测试。
- [x] 2026-08-14：为菜单栏城市模式实现长度自适应短名称规则与测试：`Tokyo`、`Hong Kong → HK`、`Singapore → SI`。
- [x] 2026-08-14：使用用户提供的小鹿原图替换 AppIcon，并在设置页加入缩小版品牌图标；界面检查通过。
- [x] 2026-08-14：完成真实连续节点切换、34 项自动测试、菜单栏短标签和品牌图标验收；发布 `1.4.0 (5)` 并替换安装版。
- [x] 2026-08-14：复现并确认当前公网 IPv4 为 `18.141.204.177`、国家代码为 `SG`，Prism 缓存仍为东京 `18.182.30.178` / `JP`。
- [x] 2026-08-14：确认当前用户设置为 `refresh.interval = 0`（仅网络变化），且 VPN 节点切换没有产生 `NWPathMonitor` 可见的路径事件。
- [x] 2026-08-14：在修改代码前创建本 Debug ExecPlan。
- [x] 2026-08-14：用户确认本修复方案。
- [x] 2026-08-14：实现独立的 1 秒轻量公网出口探针与生命周期管理。
- [x] 2026-08-14：在探测地址变化时触发已有完整双栈刷新；地址不变时禁止 GeoIP/隐私重复调用。
- [x] 2026-08-14：增加 5 秒失败退避、休眠暂停/恢复和任务取消处理。
- [x] 2026-08-14：增加 Provider、变化检测、重复地址抑制、暂停/恢复、循环停止和失败退避测试；24 项测试全部通过。
- [x] 2026-08-14：更新设置页简中/英文说明、README 和产品规格。
- [x] 2026-08-14：按小改动发布 `1.2.0 (3)`；24 项测试通过，Release 构建成功并替换 `/Applications/Prism.app`。
- [x] 2026-08-14：使用当前新加坡出口完成实时验收；缓存从东京 `18.182.30.178` / `JP` 自动切换到新加坡 `18.141.204.177` / `SG`，实测耗时 `2.016` 秒。
- [x] 2026-08-14：通过安装版界面确认 Dashboard 显示新加坡和新公网地址，设置页显示“实时出口检测：每秒”；完成 Outcomes 与回顾。

## Surprises & Discoveries

- `1.2.0` 在新加坡 → 香港时曾正常写入历史，但香港 → 新加坡后运行中应用持续保留香港；同一时刻新建连接的 `curl` 已返回新加坡。这表明监视循环仍在运行并不足以保证正确性，公网探针必须主动丢弃可能绑定旧 VPN 路径的持久 URLSession 连接。
- `NWPathMonitor` 只报告路径可用性和接口等变化；VPN 客户端在同一隧道或代理接口内切换远端节点时，公网出口会变化，但系统路径可能没有任何状态变化。
- 当前用户偏好明确保存为“仅网络变化”，所以现有周期定时器没有运行。即使默认值改为较短间隔，也无法修复已有用户设置或用户主动选择该模式后的问题。
- 缓存文件、历史文件和实际公网查询形成一致证据：应用自 10:29 左右仍保留日本结果，而当前命令行请求已返回新加坡。
- App Sandbox 下的运行数据实际位于 `~/Library/Containers/com.mraz.prism/Data/Library/Application Support/Prism`，最终验收应检查该容器路径，而不是非沙盒 Application Support 路径。
- 串行公网 HTTPS 请求的单次耗时可能大于 250ms；此时下一轮会立即开始但不会重叠，因此 250ms 是调度目标而非端到端硬保证。真实东京 → 新加坡切换用时 `563.170ms`。

## Decision Log

- 2026-08-14：撤销“实时探针复用单个 URLSession”的决定。对于出口身份查询，连接新鲜度比连接复用更重要；每次轻量探测使用独立 ephemeral URLSession，并在完成后失效，以便 VPN 节点切换后重新建立 TCP/TLS 路径。
- 2026-08-14：完整双栈公网地址查询也采用新会话，否则轻量探针虽然发现新出口，随后完整刷新仍可能从旧连接得到旧地址并无法更新 UI。GeoIP/隐私请求不承担出口发现职责，可以继续复用会话。
- 2026-08-14：菜单栏的 `{city}` 与“旗帜+城市”使用确定性的短城市名称；详情、历史和缓存仍保留 Provider 原始城市名，避免丢失信息。
- 2026-08-14：用户最终锁定城市规则为长度自适应：英文字母数不超过 5 时完整显示（`Tokyo`），更长的多单词城市取前两个首字母（`Hong Kong → HK`），更长的单词城市取前两位（`Singapore → SI`）；无法提取两个 ASCII 英文字母时回退国家代码。
- 2026-08-14：将轻量探测目标节拍设为 250ms，并按每次请求的开始时间计算剩余等待，避免“请求耗时 + 固定睡眠”累加。请求仍保持串行，绝不并发堆积；因此真实发现时间下限仍受 HTTPS 往返影响，不承诺几毫秒完成。
- 2026-08-14：用户提供的是已确定 Logo，按 imagegen skill 的“既有 Logo 优先确定性处理”原则，不进行生成式重绘；只做居中裁切、尺寸派生和资产接入，确保小鹿线条及四色叶片不被改写。
- 2026-08-14：不依赖更换默认刷新间隔来掩盖问题；增加一个与现有刷新设置独立的实时出口探针，使“仅网络变化”仍能识别外部出口变化。
- 2026-08-14：原“每 1 秒探测”决定已被用户追加的亚秒级要求取代。最终默认以 250ms 目标节拍请求一个主公网地址端点；稳定时不调用完整双栈、GeoIP 或隐私服务，检测到不同地址后才复用 `NetworkLookupService.refresh()`。
- 2026-08-14：优先探测 IPv4；IPv4 不可用时回退 IPv6，覆盖 IPv6-only 网络。完整刷新仍由现有双栈服务负责。
- 2026-08-14：相同的新地址触发完整刷新失败后，至少等待 5 秒再重试，避免第三方服务故障时形成每秒刷新风暴。
- 2026-08-14：系统休眠时停止探测；唤醒后等待网络恢复并立即探测。所有任务必须传播取消并由应用退出清理。
- 2026-08-14：本次属于小改动，成功后按项目规则从 `1.1.0 (2)` 提升到 `1.2.0 (3)`。
- 2026-08-14：监视器采用 `@MainActor` 生命周期对象而不是 actor。它只在主线程管理任务状态，URLSession 和 lookup actor 的网络/持久化工作仍在各自并发域中；这样 `RefreshCoordinator` 可以同步、幂等地 start/stop/pause/resume，避免异步控制任务的竞态。
- 2026-08-14：最初将 `URLSessionHTTPClient` 改为复用单个无缓存、无 Cookie 的 URLSession；真实 VPN 二次切换证明该优化会保留旧隧道连接，因此在 `1.2.0` 回归修复中仅对出口身份查询改用新会话策略。

## Context and Implementation Plan

新增 `ExitAddressProbe` 协议和 URLSession 实现。探针只解析单个公网地址，验证 IPv4/IPv6 格式，并使用较短超时。主端点使用现有 ipify IPv4 API，失败时回退 ipify IPv6-only API。网络 DTO 不进入 UI。

新增由 `@MainActor` 管理生命周期的 `RealtimeExitMonitor`。它以 250ms 目标节拍获取一个地址，与 `NetworkLookupService.snapshot().info.addresses` 比较。每轮按请求开始时间扣除已消耗时间；请求超过节拍时不额外睡眠，也不启动重叠请求。已知地址命中时不做任何额外工作；新地址出现时调用已有合并刷新。刷新成功后，现有状态流自然更新菜单栏和窗口；缓存、历史、通知和按 IP 元数据缓存继续走既有逻辑。

`RefreshCoordinator` 负责启动和停止实时监视器，并在休眠/唤醒期间暂停或恢复。原有周期刷新、手动刷新和 `NWPathMonitor` 去抖仍保留，作为完整校验和立即触发路径。

测试使用注入的地址序列和短间隔，验证：相同地址不刷新、新地址只触发一次、失败时退避、取消后不继续、IPv4 失败回退 IPv6、非法响应不触发刷新。运行时验收直接利用当前“缓存日本、实际新加坡”的环境，启动新版后记录缓存国家切换到 `SG` 的时间。

## File-Level Changes

- `Prism/Services/ExitAddressProbe.swift`：轻量公网地址协议与 ipify 实现。
- `Prism/Services/HTTPClient.swift`：持久会话与单请求 ephemeral 会话的显式生命周期策略。
- `Prism/Services/RealtimeExitMonitor.swift`：250ms 目标节拍检测、去重、退避、暂停与取消。
- `Prism/Services/RefreshCoordinator.swift`：实时监视器生命周期和睡眠/唤醒衔接。
- `Prism/App/AppEnvironment.swift`：组装并注入实时监视器。
- `PrismTests/ExitAddressProbeTests.swift`：地址解析、回退和取消测试。
- `PrismTests/HTTPClientTests.swift`：持久复用与每请求新会话回归测试。
- `PrismTests/RealtimeExitMonitorTests.swift`：亚秒级变化、连续变化、去重和退避测试。
- `Prism/Resources/Localizable.xcstrings`、`README.md`、`PRODUCT_SPEC.md`：解释实时探测与流量语义。
- `Prism/Resources/Assets.xcassets/AppIcon.appiconset`：用户小鹿 Logo 的 macOS 多尺寸 AppIcon。
- `Prism/Resources/Assets.xcassets/PrismLogo.imageset`、设置视图：设置页缩小版 Logo。
- `docs/execplans/prism-realtime-exit-detection.md`：持续记录根因、验证和结果。

## Validation and Acceptance

自动验证：

    xcodebuild -project Prism.xcodeproj -scheme Prism -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO test
    ./scripts/release.sh small
    defaults read /Applications/Prism.app/Contents/Info CFBundleShortVersionString
    defaults read /Applications/Prism.app/Contents/Info CFBundleVersion
    codesign --verify --deep --strict /Applications/Prism.app

运行时验收：

1. 使用已安装版从东京 `18.179.56.186` 切换到新加坡 `18.141.204.177`。
2. 高频观察实际出口与沙盒缓存，记录缓存首次变为 `18.141.204.177` / `SG` 的时间；结果为 `563.170ms`，无需手动刷新。
3. 确认 Dashboard、缓存、历史与菜单栏共用状态流，并均显示新加坡出口。
4. 确认连续历史包含香港 → 新加坡 → 东京 → 新加坡，排除只能识别首次变化的回归。
5. 运行 34 项自动测试，覆盖新会话策略、连续地区切换与城市标签规则。
6. 在设置页确认小鹿图标、实时检测说明和菜单栏实时预览 `🇯🇵 Tokyo`；当前显示模式设为“国旗和城市”。

验收标准：实际出口发生变化后无需 `NWPathMonitor` 事件或手动刷新；稳定网络不重复 GeoIP/隐私请求；失败不会形成完整刷新风暴；休眠和退出无遗留任务；菜单城市按最终长度规则显示；版本为 `1.4.0 (5)`；安装 App 可正常启动。

## Idempotence and Recovery

实时探针是只读网络请求，不修改缓存。只有已有完整刷新成功后才写缓存和历史。发布脚本会在测试或构建失败时恢复工程版本并保留当前 `/Applications/Prism.app`。监视器启动与停止必须幂等，避免重复计时任务。

## Outcomes & Retrospective

修复最终交付于安装版 `Prism 1.4.0 (5)`。根因包含两层：同一 VPN 隧道内切换节点不会可靠触发 `NWPathMonitor`；更关键的是 `1.2.0` 的实时探针复用了长生命周期 `URLSession`，其 HTTP/TCP 连接可能继续绑定旧隧道，所以新建 `curl` 已显示新加坡时 Prism 仍读到香港。

最终实现只为“出口身份”请求创建单次 ephemeral 会话并在请求结束后失效，确保每轮重新选择当前网络路径；GeoIP 和隐私服务仍复用连接。实时监视器以 250ms 目标节拍串行探测，扣除请求耗时且不并发堆积。地址稳定时不会重复调用 GeoIP、隐私分类或写入历史，地址变化后才进入完整刷新管线。

真实东京 `18.179.56.186` → 新加坡 `18.141.204.177` 切换从出口变化到 Prism 缓存和地区完成更新实测 `563.170ms`，全程没有手动刷新。历史中的香港 → 新加坡 → 东京 → 新加坡记录也验证了连续切换能力。受公网 HTTPS 往返与完整 GeoIP 响应影响，250ms 是检测调度目标，不承诺几毫秒端到端完成。

菜单栏城市规则已经锁定并测试：英文字母数不超过 5 时完整展示（`Tokyo`）；超过 5 时，多单词取前两个首字母（`Hong Kong → HK`），单词取前两位（`Singapore → SI`）；非英文信息不足时回退国家代码。详情页仍保留完整城市名称。

用户提供的小鹿原图未经生成式重绘，仅确定性裁切和缩放后用于全部 AppIcon 尺寸及设置页品牌图标；原图和处理说明保存在 `docs/assets/`。安装版界面已经确认图标与菜单栏预览显示正确。

最终 34 项测试全部通过，Release 构建为通用 `x86_64 arm64` 包，签名验证通过，并保留 App Sandbox 与网络客户端权限；`/Applications/Prism.app` 已替换并正在运行。
