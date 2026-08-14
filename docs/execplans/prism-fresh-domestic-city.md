# Prism 国内出口城市实时更新 — Debug ExecPlan

这是一份持续维护的调试实施计划。模板文件不存在，因此采用自包含结构记录 Purpose、Progress、Decision Log、Surprises & Discoveries、Validation 与 Outcomes。用户确认本计划前不修改应用代码。

## Purpose

当用户关闭 VPN、切回中国大陆网络，或之后在不同城市使用新的公网出口时，Prism 应在现有 250ms 出口探测管线发现地址变化后，重新从网络查询国家、省份和城市，不复用该 IP 的旧 GeoIP 结果。菜单栏在“国旗和城市”模式中继续使用英文城市名：英文字母数不超过 5 时完整展示，超过 5 时使用既有缩写规则；Popover 和 Dashboard 展示完整 Provider 城市名称。

用户可观察到的目标是：VPN 关闭后无需手动刷新，菜单栏和窗口从 VPN 地区自动变为中国当前公网出口所对应的城市，例如 `🇨🇳 SH`（Shanghai）或 `🇨🇳 JI`（Jiaxing）；国家详情显示中国，城市详情显示 Provider 返回的完整英文名称。250ms 是出口地址检查节拍，端到端城市更新仍需一次公网地址请求和一次 GeoIP HTTPS 请求，不承诺几毫秒完成。

2026-08-14 回归修订：仅移除 GeoIP 缓存仍不足以实现用户价值。中国大陆直连环境无法访问 ipify 时，现有地址发现链会在到达 GeoIP 前失败并误报离线。最终方案必须加入中国大陆可访问的公网地址与位置回退，同时保持海外链优先，避免 OneBox 规则分流时把 VPN 节点错误替换成本地直连出口。

## Progress

- [x] 2026-08-14：读取项目规则并确认 `.agent/PLANS.md` 与 `~/.codex/PLANS.md` 均不存在。
- [x] 2026-08-14：只读检查现有实时出口、GeoIP、缓存与城市缩写实现。
- [x] 2026-08-14：确认旧位置的主要复用点是 `NetworkLookupService.metadata[IP]` 与 `lookup-metadata.json`；相同 IP 再次出现时不会重新请求 GeoIP。
- [x] 2026-08-14：创建本 Debug ExecPlan。
- [x] 2026-08-14：用户确认本计划。
- [x] 2026-08-14：将 GeoIP 与隐私分类缓存拆分；GeoIP 每次完整刷新都强制联网，隐私结果仍按 IP 缓存以保护匿名额度。
- [x] 2026-08-14：为 GeoIP 请求加入明确的 no-store 请求策略和单请求 URLSession，避免 HTTP 缓存及旧 VPN 连接复用。
- [x] 2026-08-14：保留最后一次成功 `NetworkInfo` 仅用于离线/失败时的 stale 展示，不把它作为新出口的地理结果。
- [x] 2026-08-14：扩充测试：关闭 VPN 式地址变化、返回曾见 IP、连续国内城市变化、GeoIP 失败 stale、稳定地址不重复 GeoIP、城市英文缩写；39 项测试通过。
- [x] 2026-08-14：更新中文 README、产品规格、设置隐私说明和本 ExecPlan。
- [ ] 真机完成 VPN 开启 → 关闭验收，并记录公网出口、Provider 返回的国家/省市和端到端耗时。
- [x] 2026-08-14：按小改动提升版本到 `1.5.0 (6)`；39 项测试、Universal Release 构建、签名验证和 `/Applications/Prism.app` 替换均成功。
- [x] 2026-08-14：根据真实大陆回归重构地址发现与国内位置回退；44 项测试和本地严格构建通过。
- [x] 2026-08-14：发布纠正版 `1.6.0 (7)` 并覆盖 `/Applications/Prism.app`；44 项测试、Universal Release 构建、临时签名校验与安装后启动均成功。
- [ ] 完成 OneBox 开关双向真机验收；因关闭系统 VPN/代理属于安全敏感设置，已在操作前请求用户单独确认。
- [ ] 填写 Outcomes & Retrospective。

## Surprises & Discoveries

- 实时出口探测本身已经以 250ms 目标节拍运行，并为每个探测请求创建新会话；本次国内城市显示问题更可能来自 GeoIP 元数据按 IP 永久复用，而不是出口地址检测没有运行。
- `NetworkLookupService` 当前把 GeoIP 和隐私分类组合为一个 `CachedMetadata` 并写入 `lookup-metadata.json`。直接禁用整个缓存会让 ipapi.is 风险分类在相同 IP 重复调用，违反现有匿名额度保护，需要拆分两类生命周期。
- IP GeoIP 表示公网出口或运营商网关的估算位置，不等同于设备 GPS。即使用户物理移动到浙江，如果公网 IP 没有变化，纯网络出口工具无法确认城市变化；如果运营商更换了出口 IP，Prism 会立即重新查询。Provider 也可能只返回省份或相邻城市。
- 应用仍需要保存最后一次成功结果，才能在断网时明确标记“旧数据/暂时无法更新”。“不缓存城市”在实现中定义为“不将旧 GeoIP 当作新鲜查询结果复用”，而不是删除故障降级能力。
- 旧缓存文件包含 GeoIP 与隐私两类数据；迁移实现先把隐私字段写入 `privacy-classifications.json`，成功后删除 `lookup-metadata.json`，从磁盘上消除城市元数据缓存而不损失风险额度保护。
- 首轮 39 项测试中仅新增的 `ip.guide` 中国 no-cache 用例失败。根因是 macOS 26 的英文 Locale 国家名不保证把 `China` 反查为 `CN`；这会真实影响国内定位的回退 Provider，因此补充 `China` 与 `People's Republic of China` 的显式映射，而不是弱化测试。
- 发布前环境基线仍为东京 VPN 出口 `13.230.194.45`，ipwho.is 返回 `JP / Tokyo / Tokyo`，安装版缓存与公网一致；旧 `lookup-metadata.json` 尚存在，正好可用于安装新版后的真实迁移验收。
- 安装 `1.5.0 (6)` 并启动后，旧 `lookup-metadata.json` 已消失，`privacy-classifications.json` 只包含 IP 到风险枚举的映射，不含国家、省市或网络组织，迁移达到预期。
- 当前代理由 OneBox 提供，界面显示“已连接”，节点为“日本1”；关闭连接属于安全敏感网络设置，Computer Use policy 要求在点击开关的动作时单独确认，即使 ExecPlan 已获确认也不能代替该动作确认。
- 用户真实关闭 VPN 后安装版直接显示“无网络连接”，证明首版修订只解决了旧 GeoIP 复用，没有解决大陆环境的数据源可达性，功能未达到 Outcomes 条件。
- 当前 OneBox 规则分流环境同时存在两个出口：海外 ipify/ipwho.is 看到东京 `13.193.241.118`，国内 `myip.ipip.net/json` 看到上海电信 `180.173.166.20`。国内端点不能永久优先，否则 VPN 开启时会错误显示上海。
- 使用 `curl --noproxy '*'` 模拟大陆直连：ipify 在约 40–80ms 内连接失败，`myip.ipip.net/json` 在约 88–124ms 返回 `180.173.166.20` 与 `[中国, 上海, 上海, ..., 电信]`；对该 IP 的 ipwho.is 和 ip.guide 仍可直连并分别约 565ms、838ms 返回上海。因此地址发现必须先短超时尝试海外链，再回退 IPIP 国内链。
- 首轮大陆链 44 项测试中，地址/回退逻辑全部通过，5 个断言只暴露 Pinyin 音节大小写为 `ShangHai/ZheJiang/HangZhou/NingBo`。规范化调整为先合并所有音节再仅大写首字母，得到标准 `Shanghai/Zhejiang/Hangzhou/Ningbo`。

## Decision Log

- 2026-08-14：沿用 250ms 串行公网地址探测，不对 GeoIP 服务每 250ms 轮询。只有出口地址变化时才调用 GeoIP，避免第三方服务压力和限流。
- 2026-08-14：删除 GeoIP 的按 IP 命中复用；即使重新回到曾出现过的 IP，也必须发起新 GeoIP 请求，以覆盖移动、运营商路由和数据库更新。
- 2026-08-14：隐私分类继续按 IP 本地缓存。用户要求的“不要缓存”限定为国家/省市 GeoIP；风险接口每日匿名额度不允许随每次切换重复调用。
- 2026-08-14：GeoIP Provider 使用 `.singleRequest` URLSession 并设置 `reloadIgnoringLocalAndRemoteCacheData`、`Cache-Control: no-store, no-cache`，同时规避 HTTP 缓存与旧 VPN 长连接。
- 2026-08-14：历史与最后成功快照继续落盘，因为它们属于产品记录和离线降级，而不是 GeoIP 查询缓存；stale 状态必须有明确语义，不能冒充当前城市。
- 2026-08-14：城市菜单标签复用现有 `compactCityName` 规则，不另建中国城市特例。`Shanghai → SH`、`Hangzhou → HA`、`Ningbo → NI`，`Yiwu` 和 `Tokyo` 保留完整。
- 2026-08-14：按小改动发布 `1.5.0 (6)`；若实施中发现必须引入 Core Location/GPS 权限，则属于产品范围扩张，停止实施并重新请求用户决策。
- 2026-08-14：`ip.guide` 国家名到 ISO 代码的 Locale 映射增加中国英文名称兜底，确保主 Provider 不可用时仍能得到 `CN` 和国内城市。
- 2026-08-14：新增“海外出口优先、国内链回退”策略。ipify 成功时保持 VPN/代理节点语义；仅当 IPv4/IPv6 海外地址端点均失败时使用 `myip.ipip.net/json`，避免规则分流下混淆两个同时存在的出口。
- 2026-08-14：海外地址发现使用 1 秒单请求上限，以便黑洞式不可达也能快速进入国内回退；IPIP 实测响应约 100ms。250ms 仍是循环目标节拍，单次超时或 HTTPS RTT 较长时请求保持串行而不堆积。
- 2026-08-14：增加 IPIP 国内 GeoIP 最终回退。它只接受响应 IP 与待查询 IP 完全相同的结果；规则分流下若国内端点返回本地 IP 而待查询的是 VPN IP，则必须拒绝，避免用上海位置覆盖东京节点。
- 2026-08-14：IPIP 中文行政区名称通过 Foundation 拉丁转写并去除“省/市/自治区/自治州/地区”等后缀，生成英文 Pinyin 城市名，例如 `上海 → Shanghai`、`杭州 → Hangzhou`，再交给既有菜单缩写规则。

## Context and Implementation Plan

### Milestone 1：拆分元数据生命周期

重构 `NetworkLookupService` 和 `NetworkInfoCache`，使 GeoIP 永远来自本次联网请求，PrivacyClassification 仍可从按 IP 缓存恢复。刷新流程并发执行新 GeoIP 与“缓存优先、缺失才联网”的隐私分类。成功后只保存隐私缓存、当前 NetworkInfo 和历史，不再保存 GeoIP 元数据；迁移时忽略或安全删除旧 `lookup-metadata.json` 中的 GeoIP 内容。

### Milestone 2：确保 GeoIP 请求走当前路径

让 `IPWhoIsGeoProvider` 和 `IPGuideGeoProvider` 使用单请求 ephemeral 会话。每个 URLRequest 显式禁用本地及远端缓存，并携带 no-store/no-cache。主 Provider 失败时仍按已有顺序回退，所有请求继续遵循取消和 15 秒刷新硬截止。

### Milestone 3：状态、界面与城市显示

出口地址变化后，现有 `RealtimeExitMonitor → NetworkLookupService.refresh() → AsyncStream` 更新菜单栏、Popover、Dashboard、历史和通知。菜单栏显示英文城市的紧凑形式，详情页显示 Provider 完整城市名。刷新失败时保留旧 NetworkInfo 但标记 stale，不将上海等旧城市显示为本次已确认结果。

### Milestone 4：验证、文档与发布

自动测试证明同一 IP 第二次出现仍发生 GeoIP 请求、稳定地址不会触发完整刷新、连续地址可映射上海与浙江城市、HTTP 请求禁止缓存且使用新会话。真机关闭 VPN 后同时观察实际公网 IP、沙盒缓存和 Dashboard，记录从 IP 变化到中国城市写入的耗时。随后更新中文 README 和产品规格，运行发布脚本并替换安装版。

## File-Level Changes

- `Prism/Services/NetworkLookupService.swift`：每次出口变化强制 GeoIP，Privacy 单独缓存。
- `Prism/Persistence/NetworkInfoCache.swift`：迁移为隐私结果缓存，并兼容或清理旧元数据文件。
- `Prism/Services/IPWhoIsGeoProvider.swift`：新会话、no-store/no-cache 请求。
- `Prism/Services/IPGuideGeoProvider.swift`：新会话、no-store/no-cache 请求。
- `Prism/App/AppEnvironment.swift`：按最终依赖初始化 Provider。
- `PrismTests/NetworkLookupServiceTests.swift`：相同 IP 重查 GeoIP、隐私缓存、失败降级。
- `PrismTests/GeoIPProviderTests.swift`、`PrismTests/HTTPClientTests.swift`：请求缓存策略和会话生命周期。
- `PrismTests/RealtimeExitMonitorTests.swift`：VPN 关闭式变化与连续中国城市变化。
- `PrismTests/MenuBarLabelRendererTests.swift`：Shanghai/Hangzhou/Yiwu 等英文城市规则。
- `README.md`、`PRODUCT_SPEC.md`、`Prism/Resources/Localizable.xcstrings`：能力、流量和限制说明。
- `docs/execplans/prism-fresh-domestic-city.md`：持续记录实施与验收。

## Validation and Acceptance

自动验证：

    xcodebuild -project Prism.xcodeproj -scheme Prism -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
    ./scripts/release.sh small
    defaults read /Applications/Prism.app/Contents/Info CFBundleShortVersionString
    defaults read /Applications/Prism.app/Contents/Info CFBundleVersion
    codesign --verify --deep --strict /Applications/Prism.app

真机验收：

1. 记录 VPN 开启时的公网 IP、国家和城市。
2. 关闭 VPN，并以高频外部观测记录真实公网地址发生变化的时刻。
3. 观察沙盒当前缓存与 Dashboard，记录首次更新为 `CN` 和 Provider 返回城市的时刻；无需手动刷新。
4. 确认菜单栏使用英文城市紧凑规则，例如上海显示 `SH`；Dashboard 显示完整 `Shanghai`。
5. 再次启用 VPN、随后关闭并回到曾见过的国内 IP，确认 GeoIP 仍重新联网而不命中旧城市元数据。
6. 稳定保持出口不变，确认不会每 250ms 调用 GeoIP 或重复写历史。

验收标准：关闭 VPN 后由 250ms 探测自动进入国内地址回退并触发新 GeoIP；海外端点不可达不再误报离线；新出口不复用历史城市；国家与完整城市同步到窗口，英文城市缩写同步到菜单栏；失败时明确 stale；全部测试通过；最终纠正版为 `1.6.0 (7)` 并覆盖 `/Applications/Prism.app`。

## Idempotence and Recovery

迁移逻辑必须能在多次启动时安全执行。旧元数据读取失败或格式不兼容时降级为空；删除旧 GeoIP 缓存前不影响当前 NetworkInfo、历史或设置。发布脚本在测试或构建失败时恢复版本号并保留已安装版本。所有网络任务继续正确传播取消，系统休眠与退出不得留下请求循环。

## Outcomes & Retrospective

待实施与真机验收后填写。
