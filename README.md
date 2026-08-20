# Prism

Prism 是一款原生 macOS 菜单栏网络出口工具，用于查看当前公网 IPv4、IPv6、国家或地区、城市、运营商、ASN 和网络组织。

它只负责观察和展示网络出口，不控制 VPN、代理或 DNS。应用没有账号、广告、分析、遥测和云同步。

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

首次检测完成后，菜单栏会显示当前出口，例如：

```text
🇯🇵 日本
```

- 左键：第一次点击展开网络信息，第二次点击同一菜单栏图标关闭；点击面板外也会关闭
- 右键：刷新、打开详细信息、设置或退出
- IP 右侧按钮：复制 IPv4 或 IPv6 地址

## 功能

- 分别检测公网 IPv4 和 IPv6
- 显示国家或地区、城市、ISP、组织、ASN 和时区
- 识别直连、代理和分流出口
- 对新出口执行尽力而为的代理、VPN、Tor 或数据中心分类
- 出口变化确认、系统通知和最多 100 条本地历史
- 系统休眠、唤醒和网络路径变化处理
- 登录时启动
- 中英文、键盘操作、Tooltip 和 VoiceOver
- 跟随系统、浅色、深色外观和六套自适应强调色

Prism 不提供节点切换、测速、抓包、防火墙或自动更新。

## 设置

| 页面 | 内容 |
| --- | --- |
| 通用 | 登录启动、出口变化通知、定期资料校验 |
| 菜单栏 | 显示样式、自定义模板和状态预览 |
| 外观 | 系统/浅色/深色模式和六套强调色 |
| 网络 | 当前路线、出口探针和 GeoIP 服务状态 |
| 隐私 | 外部请求与本地数据说明 |

自定义菜单栏模板支持：

```text
{flag} {country} {code} {city} {status}
```

无有效标记时会回退到默认样式，最终文本最多保留 20 个字符。较长英文城市名会在菜单栏中使用紧凑缩写，Dashboard、Popover 和历史仍显示完整名称。

## 检测方式

Prism 使用自适应出口观察：

- 网络稳定时每秒检查一次
- 发现候选地址、网络变化、唤醒或手动刷新后，短暂切换到 250ms 确认节拍
- 同一时间最多进行一轮探测，不堆积重复请求
- IPv4 与 IPv6 同轮观察，单个地址族失败不影响另一个
- 地址变化后重新查询 GeoIP，不复用旧城市结果
- 未确认的候选只显示“正在确认”，不会立即写入历史或发送通知

关闭定期资料校验不会关闭实时出口观察。

## 网络服务与隐私

Prism 会按需访问以下服务：

| 服务 | 用途 |
| --- | --- |
| `ipify` | 检测公网 IPv4 和 IPv6 |
| `myip.ipip.net/json` | 海外探针不可用时的中国大陆回退 |
| `ipwho.is`、`ip.guide`、`ipip.net` | 查询近似位置和网络信息 |
| `ipapi.is` | 对新出口进行尽力而为的隐私分类 |

出口历史、最后一次成功结果和隐私分类仅保存在当前 Mac。IP 地理位置是公网出口或运营商网关的近似位置，不代表 Mac 的 GPS 位置；代理或 VPN 分类也不应视为确定结论。

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

UI 测试位于独立的 `PrismUITests` Scheme，需要本机签名和 macOS 自动化权限。

## 发布与安装

小改动执行：

```bash
./scripts/release.sh small
```

大版本执行：

```bash
./scripts/release.sh major
```

发布脚本会提升版本和内部构建号，运行测试，生成并验证签名 Release 构建，最后替换 `/Applications/Prism.app`。测试或构建失败时不会覆盖当前安装版本。

## 项目结构

```text
Prism/App          应用入口与依赖组装
Prism/Models       网络、状态和设置模型
Prism/Services     探测、刷新、通知与系统服务
Prism/Persistence  缓存、历史和设置
Prism/StatusBar    菜单栏与 Popover
Prism/Views        Dashboard、历史和设置界面
PrismTests         单元测试
PrismUITests       UI 测试
scripts            发布脚本
```

## 常见问题

### 启动后为什么没有 Dock 图标？

Prism 是菜单栏应用。请在屏幕顶部菜单栏查找国家或地区标签。

### 为什么显示缓存结果或暂时无法更新？

当前网络可能离线、请求超时或第三方服务暂时不可用。Prism 会保留最后一次成功结果并标记其状态。

### 为什么代理或 VPN 判断不准确？

分类来自第三方 IP 数据。企业网络、云服务、共享出口和 iCloud Private Relay 都可能造成误判。

### 为什么无签名构建无法验证登录启动？

`SMAppService` 需要已安装并签名的应用。请通过 `scripts/release.sh` 安装 Release 构建后再验证。
