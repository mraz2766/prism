# Prism

Prism 是一款原生 macOS 菜单栏网络出口工具，用于探测海外代理路径的可用性及当前可用出口来源，显示公网 IPv4、IPv6、位置和运营商，并独立观察中国大陆端点看到的 IPv4。它只观察网络出口，不控制 VPN、代理或 DNS，也不包含账号、广告、遥测或云同步。

## 系统要求

- macOS 14 Sonoma 或更高版本
- Apple Silicon 或 Intel Mac
- 从源码构建需要支持 Swift 6 和 macOS 14 SDK 的 Xcode

Prism 使用 App Sandbox，只申请客户端网络访问权限。它以菜单栏应用运行，不显示 Dock 图标。

## 快速开始

将签名后的 `Prism.app` 安装到 `/Applications`，然后启动：

```bash
open /Applications/Prism.app
```

首次检测完成后，菜单栏默认显示圆角国旗和 ISO 国家代码，例如“中国圆角旗 + CN”。

- 左键：第一次点击展开网络信息，第二次点击同一菜单栏图标关闭；点击面板外也会关闭
- 右键：查看当前出口、复制 IP、刷新、打开详细信息、历史、设置或退出
- 点击 IP 所在行：复制公网出口或国内出口地址；完整 IPv6 保留在详情页

## 功能

- 分别检测公网 IPv4 和 IPv6
- 独立显示国内出口 IPv4，并判断它是否与当前公网出口一致
- 公网 IPv4 与国内出口相同时自动合并为一行，避免重复展示
- 单击弹窗默认聚焦公网 IPv4 与国内出口 IPv4；只有 IPv4 缺失时才显示 IPv6
- 监听系统网络、代理和 VPN 路由变化，切换后废弃旧连接并重新确认当前出口
- 真正断网时隐藏旧国家、国旗和 IP；网络恢复后立即重新检测
- 显示国家或地区、城市、ISP、组织、ASN 和时区
- 按出口 IP 复用成功归属地，并内置 IPv4 / IPv6 离线国家库；在线服务超时不影响国家展示
- 海外不可达时展示已确认的国内出口，海外恢复后自动切回实际出口
- 对新出口执行尽力而为的代理、VPN、Tor 或数据中心分类
- 出口变化确认、系统通知（出口变化、回退国内、海外恢复）和最多 500 条本地历史，支持搜索、单条删除与拷贝为 CSV
- 期望地区守护：出口离开指定国家时提醒并在菜单栏标记
- 可选全局快捷键呼出面板，显示出口探测延迟
- 系统休眠、唤醒和网络路径变化处理
- 登录时启动
- 中英文、键盘操作、Tooltip 和 VoiceOver
- 跟随系统、浅色、深色外观和六套自适应强调色
- 卡通国旗、波浪国旗、圆角国旗、方形国旗、邮票国旗、双联胶囊、国旗色标、小印章和系统 Emoji 九种视觉风格

Prism 不提供节点切换、测速、抓包、防火墙或自动更新。

## 设置

| 页面 | 内容 |
| --- | --- |
| 通用 | 登录启动、出口变化通知、全局快捷键、检测灵敏度、定期资料校验、地区守护 |
| 菜单栏 | 标识方式、国旗风格、自定义模板和状态预览 |
| 外观 | 系统/浅色/深色模式和六套强调色 |
| 关于 | 版本、隐私说明、外部服务与数据来源 |

当前路线、出口探针和 GeoIP 服务状态位于详情窗口的“诊断”标签。

菜单栏内置五种标识方式：

- 国旗 + 国家代码（默认）
- 国旗 + 城市
- 仅国家代码
- 仅国旗
- 自定义模板

国旗可选卡通国旗、波浪国旗、圆角国旗（默认）、方形国旗、邮票国旗、双联胶囊、国旗色标、小印章或系统 Emoji，在设置中以带预览的网格选择。选中的风格会同步应用到菜单栏弹窗、概览、历史列表和详情；所有样式在空间有限的系统菜单栏中都会自动使用像素对齐的紧凑布局。国旗色标以粗体国家代码搭配底部代表色色带，小印章使用厚边框和轻微倾斜；两者在托盘与界面中共用绘制逻辑，并适配深浅外观。邮票国旗使用透明齿孔与细纸边，托盘画布为 22×18pt；双联胶囊将圆形旗面与国家代码组合在 28×18pt 画布中，固定白底深色字，旗面等比绘制，避免图案拉伸。

自定义模板支持：

```text
{flag} {country} {code} {city} {status}
```

无有效标记时会回退到默认样式，最终文本最多保留 20 个字符。较长英文城市名只在菜单栏中使用紧凑缩写。

## 检测方式

Prism 使用自适应出口观察：

- 可在设置中滑动调节检测灵敏度；灵敏度越高，越快发现 VPN 不可用、恢复和地区切换
- 根据灵敏度以 2–12 秒检查稳定网络；低电量模式下自动降低频率
- 发现候选地址、探测失败、网络变化、唤醒或手动刷新后，短暂切换到 100–500ms 确认节拍
- 连续探测失败时及时标记出口不可用，探测恢复后即使 IP 未变也会恢复实时状态
- 同一时间最多进行一轮探测，不堆积重复请求
- IPv4 与 IPv6 同轮观察，单个地址族失败不影响另一个
- 地址确认后先查本地：同一 IP 的近期成功记录立即恢复国家和城市；没有记录时使用离线国家库，随后在后台补全 GeoIP
- 未确认的候选只显示“正在确认”，不会立即写入历史或发送通知
- 已确认的新出口需继续稳定 3 秒才写入历史，短时回跳不会留下噪声记录
- 国内出口 IPv4 在启动、网络或主出口变化、唤醒、手动刷新和定期资料校验时独立更新，不加入 5 秒实时轮询

关闭定期资料校验不会关闭实时出口观察。

## 网络服务与隐私

归属地查询跟随 macOS 系统代理配置，按明确的出口 IP 查询，并复用连接以减少握手开销；单次查询超时为 1.5 秒。

归属地采用本地优先策略：优先使用同一 IP 在最近 30 天内的成功记录；否则查询内置国家库。离线库没有覆盖时仍可沿用该 IP 的旧成功记录，并显示原始记录时间。在线查询只负责后台补全和更新城市、运营商等资料；查询失败不会清空成功记录，也不会把可用出口标成网络异常。完全没有国家数据时显示中性的“国家待识别”，IP 仍正常显示。不同 IP、IPv4 与 IPv6 之间不会套用未经查询的位置。

主展示跟随当前可达路径：海外 IPv4 / IPv6 探针均失败、国内端点仍可达时，连续两轮确认同一国内地址后，主国旗与 IP 切换为国内出口，状态显示“国内可用”。国内出口为中国地址时显示中国国旗，不再继续展示此前的海外节点。每轮仍优先检测海外路径；连续两轮确认恢复后，自动切回实际海外出口，国家优先由同 IP 缓存或离线库提供。单次超时后立即恢复不会切换国家；两条路径都失败时才保留“最近确认”。这反映探针可达性，不控制代理软件或替它切换节点。

Prism 会按需访问以下服务：

| 服务 | 用途 |
| --- | --- |
| `ipify` | 检测公网 IPv4 和 IPv6 |
| `myip.ipip.net/json` | 独立观察国内出口 IPv4；海外探针均不可达时提供主出口回退 |
| `ipwho.is`、`ip.guide`、`api.ip.sb/geoip/{ip}`、`ipip.net` | 查询近似位置和网络信息 |
| `ipapi.is` | 对新出口进行尽力而为的隐私分类 |

出口历史、最后一次观察、最多 256 个 IP 的成功归属地和隐私分类仅保存在当前 Mac；国内出口 IPv4 仅保存在运行内存。历史缓存、离线国家和在线资料会分别标明来源，离线国家不会虚构城市或在线更新时间。IP 地理位置是公网出口或运营商网关的近似位置，不代表 Mac 的 GPS 位置；代理或 VPN 分类也不应视为确定结论。

### 离线国家库

内置 [DB-IP Country Lite](https://db-ip.com/db/download/ip-to-country-lite) 2026-11 数据，覆盖 IPv4 / IPv6，国家索引约 7.73 MiB。索引只加载一次，通过二分查找返回国家，不发起网络请求；不包含城市或运营商。私网、保留地址和未覆盖区间返回未知。

数据库随 App 发布更新，运行时不自动下载。开发者更新命令：

```bash
python3 scripts/build-country-database.py YYYY-MM
```

也可使用 `--source /path/to/dbip-country-lite-YYYY-MM.csv.gz` 从本地官方 CSV 压缩包生成。来源、月份、转换说明及 SHA-256 校验值保存在 `Prism/Resources/GeoIP/country-dbip.source.json`；数据库缺失或损坏时安全回退到缓存和在线查询。

## 快捷键

| 快捷键 | 操作 |
| --- | --- |
| `⌘R` | 刷新 |
| `⌘O` | 打开详细信息 |
| `⌘,` | 打开设置 |
| `⌘W` | 关闭当前窗口 |
| `⌘Q` | 退出 Prism |

## 从源码构建

构建：

```bash
xcodebuild \
  -project Prism.xcodeproj \
  -scheme Prism \
  -destination 'platform=macOS,arch=arm64' \
  clean build
```

运行单元测试：

```bash
xcodebuild \
  -project Prism.xcodeproj \
  -scheme Prism \
  -destination 'platform=macOS,arch=arm64' \
  ENABLE_HARDENED_RUNTIME=NO \
  test
```

单元测试命令仅为本地测试宿主关闭 Hardened Runtime，使临时签名的 XCTest 包可以加载；Release 构建保持启用。

UI 测试位于独立的 `PrismUITests` Scheme，需要本机签名和 macOS 自动化权限。构建与测试保留正常签名，避免生成无法启动的测试 Runner。发布脚本使用临时构建目录，隔离日常开发产物。

## 发布与安装

小改动执行：

```bash
./scripts/release.sh small
```

大版本执行：

```bash
./scripts/release.sh major
```

发布脚本会自动识别安装在 `/Applications/Xcode.app` 的完整 Xcode，提升版本和内部构建号，运行测试，生成并验证签名 Release 构建，最后替换并启动 `/Applications/Prism.app`。首次运行会自动打开概览窗口，后续保持纯菜单栏运行。测试、构建或启动失败时不会覆盖当前安装版本。

如果 Xcode 刚安装且尚未完成首次设置，请先运行：

```bash
sudo xcodebuild -license
sudo xcodebuild -runFirstLaunch
```

## 项目结构

```text
Prism/App          应用入口与依赖组装
Prism/Models       网络、状态和设置模型
Prism/Services     探测、刷新、通知与系统服务
Prism/Persistence  缓存、历史和设置
Prism/StatusBar    菜单栏与 Popover
Prism/Views        Dashboard、历史和设置界面
Prism/Resources    本地化、图标和内置国旗资源
PrismTests         单元测试
PrismUITests       UI 测试
scripts            发布脚本
```

## 常见问题

### 启动后为什么没有 Dock 图标？

Prism 是菜单栏应用。请在屏幕顶部菜单栏查找国家或地区标签。

### 为什么显示缓存结果或暂时无法更新？

出口 IP 确认后立即显示，并使用同一 IP 的成功缓存或离线国家库。第三方归属地服务超时只影响资料补全，不会显示网络异常；具体原因可在设置的服务状态中查看。后台按 5、15、30 秒退避重试，服务冷却期间等待恢复，出口探测仍正常进行。只有出口探测本身暂时无法确认时才显示“上次确认”；真正断网时会隐藏旧出口。

### 为什么代理或 VPN 判断不准确？

分类来自第三方 IP 数据。企业网络、云服务、共享出口和 iCloud Private Relay 都可能造成误判。

### 为什么国内出口 IPv4 不是中国地址？

这个地址表示中国大陆端点实际看到的请求来源。规则代理通常会让国内流量直连；全局代理或全隧道 VPN 仍可能代理该请求，因此 Prism 会标记“国内流量可能仍走代理”，而不会把它误称为非代理 IP。

### 为什么无签名构建无法验证登录启动？

`SMAppService` 需要已安装并签名的应用。请通过 `scripts/release.sh` 安装 Release 构建后再验证。

## 第三方资源

离线国家库由 [DB-IP Country Lite](https://db-ip.com/db/download/ip-to-country-lite) 转换为紧凑国家边界索引，采用 [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) 许可证（IP Geolocation by DB-IP）。转换合并了相邻同国家区间，将非 ISO 国家代码保留为未知；来源与许可说明位于 `Prism/Resources/GeoIP/DB-IP-LICENSE.txt`。

用于双联胶囊和缺失素材回退的圆形国旗来自 [Circle Flags](https://github.com/HatScripts/circle-flags)（提交 `379588b5da95`），采用 MIT 许可证。资源完全随 App 打包，不会在运行时下载；许可证副本位于 `Prism/Resources/CircleFlags/LICENSE.circle-flags.md`。

卡通国旗来自 [OpenMoji](https://github.com/hfg-gmuend/openmoji) 17.0.0，图形采用 CC BY-SA 4.0 许可证。Prism 在原图基础上增加旗杆、轻微倾斜和阴影；许可证副本位于 `Prism/Resources/CartoonFlags/LICENSE.openmoji.txt`。

波浪国旗来自 [Noto Emoji region flags](https://github.com/googlefonts/noto-emoji/tree/main/third_party/region-flags)（提交 `8998f5dd6834`）。原始旗帜为公有领域资源，相关来源与声明保存在 `Prism/Resources/WavedFlags`。

圆角国旗（原“渐变国旗”）来自 [FlagKit](https://github.com/madebybowtie/FlagKit)（提交 `f12111d91902`），采用 MIT 许可证；许可证副本位于 `Prism/Resources/FlagKitFlags/LICENSE.flagkit.txt`。

方形国旗来自 [flag-icons](https://github.com/lipis/flag-icons) 7.2.3 的 1×1 版本，采用 MIT 许可证；许可证副本位于 `Prism/Resources/SquareFlags/LICENSE.flag-icons.txt`。

波浪和方形国旗体积较大，已用 `scripts/rasterize-flags.swift` 按运行时相同的规格预先栅格化为 PNG 随 App 打包，外观与直接渲染 SVG 一致。
