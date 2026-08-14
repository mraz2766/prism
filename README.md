# Prism

Prism 是一款原生 macOS 菜单栏网络出口工具，用于查看当前 Mac 访问互联网时使用的公网 IPv4、IPv6、国家或地区、城市、运营商、ASN、网络组织和时区。它不会控制 VPN、代理或 DNS，也不包含账号、广告、分析和遥测。

## 系统要求

- Apple Silicon Mac
- macOS 14 Sonoma 或更高版本
- 从源码开发时，需要支持 Swift 6 和 macOS 14 SDK 的 Xcode；当前工程使用 Xcode 26.6 验证

Prism 启用了 App Sandbox，只申请客户端网络访问权限。应用以菜单栏工具运行，不会常驻显示 Dock 图标。

## 快速开始

安装完成后，从“应用程序”目录启动 Prism：

```bash
open /Applications/Prism.app
```

首次检测完成后，菜单栏会显示当前出口国家或地区。默认样式类似：

```text
🇯🇵 日本
```

- 左键点击菜单栏标签：打开或关闭紧凑信息面板
- 右键点击菜单栏标签：刷新、打开详细信息、打开设置或退出
- 点击 IP 右侧复制按钮：复制地址，图标会短暂变为勾选状态

## 主要功能

- 分别检测公网 IPv4 和 IPv6，单个地址族失败不会影响另一个
- 显示本地化国家或地区、城市、ISP、组织、ASN 和时区
- `ipwho.is` 查询失败时自动回退到 `ip.guide`，中国大陆直连环境还可回退到 IPIP
- 对新出现的出口 IP 执行尽力而为的疑似代理或 VPN 分类
- macOS 网络路径变化后去抖刷新，并处理系统休眠与唤醒
- 网络稳定时每秒进行一次轻量出口观察；发现候选或网络变化后短暂切换到 250ms 确认节拍
- 候选地址会先显示“正在确认”，连续观察确认后才切换地区、写入历史和发送通知
- 探针、GeoIP、历史和通知消费同一份确切出口观察，避免规则分流时东京/上海来回跳动
- 出口地址变化后总是重新联网查询国家、省市和网络信息，不复用旧 GeoIP 城市结果
- 保留最后一次成功结果；更新失败时明确标记为缓存数据
- 本地保存最多 100 条出口历史，并按日期分组
- 支持登录时启动和出口变化通知
- 支持系统、浅色和深色外观，以及六套深浅模式自适应强调色；设置页导航与控件会同步换色
- 使用用户提供的小鹿 Logo，并在通用设置中展示缩小版品牌图标
- 完整支持英文和简体中文、键盘操作、Tooltip 和 VoiceOver 标签

Prism 不包含 VPN 开关、代理配置、节点切换、测速、延迟、地图、抓包、防火墙或自动更新器。

## Dashboard 与设置

详细信息窗口包含“概览”和“历史”两个页面，可通过菜单栏右键菜单或紧凑面板打开。

设置窗口包含：

- 通用：登录时启动、定期资料校验、网络变化刷新和通知
- 菜单栏：显示样式、自定义模板，以及正常/确认中/离线三种实时预览
- 外观：跟随系统、浅色或深色，以及光谱蓝、潮汐青、暖阳橙、苔原绿、极光紫、石墨灰强调色
- 网络：查看 GeoIP 服务顺序和最近使用的服务
- 隐私：查看实际网络请求与本地数据说明

自定义菜单栏模板支持以下标记：

```text
{flag} {country} {code} {city} {status}
```

无有效标记时会回退到默认样式，最终文本最多保留 20 个字符。
“旗帜和城市”以及自定义模板中的 `{city}` 会按长度自适应：英文字母不超过 5 个时完整显示（如 `Tokyo`、`Yiwu`），超过 5 个时使用紧凑缩写（如 `Hong Kong → HK`、`Singapore → SI`、`Shanghai → SH`、`Hangzhou → HA`）。Dashboard、Popover 和历史仍显示完整城市名。

## 刷新与本地数据

Prism 采用自适应出口观察：网络稳定时目标节拍为 1 秒；出现候选地址、系统网络变化、唤醒或手动刷新后，在 4 秒内提升为 250ms 确认节拍。IPv4 与 IPv6 并发观察，请求不并发堆积。两种地址族在同一轮共享连接，但连接代际最多保留 1.5 秒，避免 OneBox 等代理工具切换国家节点后长期沿用旧隧道；相比每个请求都创建会话，也能显著降低后台 CPU。第一次不同路线的候选会立即显示“正在确认”；连续两次得到相同路线后才提交。同一代理路线内出现新 IP 会立即提交。单次海外请求失败、候选撤销或迟到的旧请求不会覆盖当前稳定出口。

启动、手动刷新、周期校验和网络变化都使用同一条观察管线。确认时 GeoIP 直接消费已经观察到的确切 IP，不再重新查询并选择另一个出口；因此规则分流环境下不会出现探针看到代理出口、资料刷新却写入国内直连出口的问题。地址未变化的实时观察不会请求 GeoIP 或隐私服务；定期校验仍会实时更新位置资料。GeoIP 禁止 HTTP 缓存，即使回到曾使用过的公网 IP，也不会复用旧国家或城市。Provider 在 300ms 阶梯后并发回退，重复失败会暂时熔断 30 秒。

地址发现采用“海外出口优先、国内链回退”：先以 1 秒请求上限检查 ipify，保留 VPN、代理和 OneBox 规则分流时的海外出口语义；只有 IPv4/IPv6 海外端点都不可用时，才查询中国大陆可访问的 `myip.ipip.net/json`。这样 VPN 开启时仍显示节点地区，VPN 关闭且 ipify 不可访问时则自动显示国内公网地址，不会把“海外服务不可达”误判成断网。

定期资料校验默认每分钟一次，可选择 30 秒、1 分钟、5 分钟、10 分钟或仅在网络变化时刷新。关闭定期校验不会关闭自适应实时出口观察。

Prism 使用以下服务：

- `ipify`：稳定时以 1 秒目标节拍观察公网 IPv4 和 IPv6，候选确认阶段短暂提升到 250ms
- `myip.ipip.net/json`：仅在 ipify 不可用时发现中国大陆公网地址，并作为国内位置的最终回退
- `ipwho.is` / `ip.guide` / `ipip.net`：在完整刷新时实时查询近似位置和网络信息，不保存可复用的城市元数据缓存
- `ipapi.is`：仅在新出口 IP 出现时执行疑似代理、VPN、Tor 或数据中心分类

最后一次成功结果、风险结果与历史仅保存在当前 Mac 的 Application Support 目录。旧版 GeoIP 元数据会在升级时迁移为仅含隐私分类的文件并删除城市字段。IP 地理位置和隐私分类均为近似结果，不应视为确定结论。

Prism 显示的是公网出口或运营商网关的估算城市，不是 Mac 的 GPS 位置。关闭 VPN 后，只要海外链持续不可用并连续确认国内公网出口，便会显示中国与英文城市；在上海可能显示 `Shanghai`，到浙江后若运营商分配了新出口，则会显示 Provider 判断的 `Hangzhou`、`Ningbo`、`Jiaxing` 等城市。如果移动后公网 IP 没有变化，纯出口检测无法确认物理城市变化。

## 从源码构建

克隆或打开项目目录后执行：

```bash
xcodebuild \
  -project Prism.xcodeproj \
  -scheme Prism \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO \
  clean build
```

运行单元测试：

```bash
xcodebuild \
  -project Prism.xcodeproj \
  -scheme Prism \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO \
  test
```

UI 测试位于独立的 `PrismUITests` Scheme，需要本机签名和 macOS 自动化授权。

## 版本与安装

项目使用两类应用版本升级：

- 小改动：修订版本加 `0.0.1`，例如 `1.0.0 → 1.0.1`；修订号逢 9 进位，例如 `1.0.9 → 1.1.0`
- 大改动：主版本加 `1.0.0`，次版本与修订号归零，例如 `1.2.5 → 2.0.0`

每次完整修改只提升一次版本。内部构建号 `CURRENT_PROJECT_VERSION` 同时递增 `1`。

完成小改动后，运行：

```bash
./scripts/release.sh small
```

完成大改动后，运行：

```bash
./scripts/release.sh major
```

脚本会依次提升版本、运行测试、生成签名 Release 构建、验证签名，然后安全替换：

```text
/Applications/Prism.app
```

测试或构建失败时不会替换已安装版本。如果当前账户无权写入 `/Applications`，脚本会在安装阶段退出。

## 常用快捷键

- `⌘R`：刷新
- `⌘O`：打开详细信息
- `⌘,`：打开设置
- `⌘W`：关闭当前窗口
- `⌘Q`：退出 Prism

## 项目结构

```text
Prism/App             应用入口与依赖组装
Prism/Models          网络、状态与设置模型
Prism/Services        网络查询、刷新、通知与登录启动
Prism/Persistence     缓存、历史和设置持久化
Prism/StatusBar       菜单栏、Popover 与标签渲染
Prism/Views           Dashboard、历史、设置和通用组件
PrismTests            单元测试
PrismUITests          UI 测试
scripts               版本、构建和安装脚本
docs/execplans        持久化实施计划
```

## 常见问题

### 为什么 Dock 中看不到 Prism？

Prism 是 accessory 类型的菜单栏应用。启动后请在屏幕顶部菜单栏查找国家或地区标签。

### 为什么显示“暂时无法更新”？

当前网络可能离线、请求超时或第三方服务暂时不可用。Prism 会继续显示最后一次成功结果，并明确标记为缓存状态。

### 为什么疑似代理或 VPN 的判断不准确？

该结果来自第三方 IP 分类，只能作为线索。企业网络、云服务、iCloud Private Relay 或共享出口都可能造成误判。

### 登录启动为什么无法在无签名构建中验证？

`SMAppService` 需要安装并签名的 App。请使用 `scripts/release.sh` 安装 Release 构建后再测试。

## 相关文档

- [产品规格](PRODUCT_SPEC.md)
- [参考项目分析](REFERENCE_ANALYSIS.md)
- [MVP 实施记录](docs/execplans/prism-macos-mvp.md)
- [版本与安装实施记录](docs/execplans/prism-release-workflow.md)
