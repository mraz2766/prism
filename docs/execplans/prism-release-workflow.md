# Prism README、应用版本与安装工作流 — Feature ExecPlan

这是一份持续更新的实施计划。实施过程中维护 `Progress`、`Surprises & Discoveries`、`Decision Log` 和 `Outcomes & Retrospective`。

## Purpose

让 Prism 的后续修改具备稳定的交付闭环：每次变更完成后都有明确的应用版本号、通过自动测试、生成可运行的 Release App，并原子替换 `/Applications/Prism.app`。中文 README 应让新用户能够安装、使用和继续开发项目。

## Progress

- [x] 2026-08-14：确认当前工程版本为 `1.0.0`、`/Applications/Prism.app` 尚不存在。
- [x] 2026-08-14：确认项目与全局均无 PLANS 模板，创建本自包含 Feature ExecPlan。
- [x] 2026-08-14：用户确认实施，并澄清不需要 Git，只管理 App 版本号。
- [x] 2026-08-14：编写中文 `README.md`，内容以现有代码、测试和真实命令为准。
- [x] 2026-08-14：添加项目级 `AGENTS.md`，持久化“修改后提升版本、构建、安装、验证”的协作约定。
- [x] 2026-08-14：添加可重复的版本提升、构建、验证、安装脚本，并通过 `zsh -n` 语法检查。
- [x] 2026-08-14：将本次小改动的营销版本从 `1.0.0` 提升到 `1.1.0`，内部构建号从 `1` 提升到 `2`。
- [x] 2026-08-14：执行 16 项测试、签名 Release 构建并替换 `/Applications/Prism.app`，验证安装版本、签名、架构和沙盒权限。
- [x] 2026-08-14：启动已安装 App，确认 Prism 进程正常运行。
- [x] 2026-08-14：完成 Outcomes 与回顾。

## Surprises & Discoveries

- 用户确认“版本控制”仅指 App 的可见版本与内部构建号，不需要 Git 仓库、提交或标签。
- 当前 `/Applications` 中没有 Prism，不需要迁移旧安装；脚本仍需支持以后安全替换已存在版本。
- 工程使用 Xcode build settings 管理 `MARKETING_VERSION` 与 `CURRENT_PROJECT_VERSION`，版本工作流应更新工程设置而不是另建一个会漂移的版本文件。
- 首次发布成功后，zsh 报告 `status` 为只读特殊变量，导致成功路径的临时目录清理没有执行。清理函数已改用 `exit_code`，残留的构建目录和空安装目录已安全移除，随后重新构建并覆盖安装最终文件集。
- 仅指定 `platform=macOS` 时 Xcode 会提示 arm64/x86_64 目标不唯一；发布脚本和 README 已固定测试目标为 `platform=macOS,arch=arm64`。

## Decision Log

- 2026-08-14：将用户的“小改动 +0.1”解释为次版本提升：`1.0.0 → 1.1.0 → 1.2.0`；“大改动 +1”解释为主版本提升并清零次版本：`1.2.0 → 2.0.0`。
- 2026-08-14：`MARKETING_VERSION` 使用 `主.次.0`，`CURRENT_PROJECT_VERSION` 每次发布递增 1，兼顾用户可见版本和 macOS 内部构建号。
- 2026-08-14：安装前必须先测试并完成签名 Release 构建；安装阶段使用暂存与回滚路径，只有新 App 就位后才删除旧备份。
- 2026-08-14：不引入 Git 工作流；版本状态以 Xcode 工程中的 `MARKETING_VERSION` 和 `CURRENT_PROJECT_VERSION` 为唯一事实来源。

## Context and Implementation Plan

新增根目录中文 `README.md`，至少覆盖项目简介、系统要求、安装、首次运行、菜单栏/面板/设置使用、数据与隐私、开发构建、测试、目录结构、版本规则和常见问题。命令直接采用已通过验证的 `xcodebuild` 调用，不声称尚未具备的发布能力。

新增根目录 `AGENTS.md`，使后续任务在完成代码或文档修改后默认执行小版本提升、测试、Release 构建、安装到 `/Applications/Prism.app` 和安装验证；只有明确标记为“大改动”时才提升主版本。失败时不得覆盖已安装版本。

新增 `scripts/release.sh`，接受 `small` 或 `major` 参数。脚本读取工程中的当前营销版本，计算下一版本，通过 Xcode 的版本设置同步 Debug/Release 配置，递增内部构建号，执行 `Prism` 测试 Scheme 和 Release 构建，将产物复制到临时路径，再安全替换 `/Applications/Prism.app`。脚本打印最终版本和安装路径，不主动打开应用。

## File-Level Changes

- `README.md`：中文用户与开发者说明。
- `AGENTS.md`：项目级后续交付规则。
- `scripts/release.sh`：版本提升、测试、构建和安全安装入口。
- `Prism.xcodeproj/project.pbxproj`：启用 Apple Generic Versioning，并由发布流程更新营销版本与构建号。
- `docs/execplans/prism-release-workflow.md`：持续记录本次工作。

## Validation and Acceptance

实施后执行并观察：

    ./scripts/release.sh small
    xcodebuild -project Prism.xcodeproj -scheme Prism -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
    defaults read /Applications/Prism.app/Contents/Info CFBundleShortVersionString
    defaults read /Applications/Prism.app/Contents/Info CFBundleVersion
    codesign --verify --deep --strict /Applications/Prism.app
    codesign -d --entitlements :- /Applications/Prism.app

验收标准：测试零失败；Release 构建成功；安装路径存在且报告 `1.1.0`；签名验证通过且包含 App Sandbox/网络客户端权限；README 中的命令与工程实际行为一致。

## Idempotence and Recovery

发布脚本在测试或构建失败时立即退出，不触碰 `/Applications`。替换安装时先把已有 App 移到唯一备份目录，再移动新构建；若新版本移动失败则恢复旧版本。脚本拒绝未知版本参数和无法解析的版本格式。重复发布必须生成更高的应用版本与内部构建号。

## Outcomes & Retrospective

项目现在包含基于真实代码与已验证命令编写的中文 README，以及项目级 `AGENTS.md`。后续每批实现默认执行小版本升级；明确的大改动执行主版本升级。计划文件的审核和结果记录不触发版本。

`scripts/release.sh` 已实现 `small`/`major` 版本计算、内部构建号递增、失败回滚、16 项单元测试、签名 Release 构建、构建版本校验、原子安装替换和最终签名校验。本次小版本发布将 Prism 从 `1.0.0 (1)` 提升到 `1.1.0 (2)`。

最终验证结果：测试 16/16 通过；Release 构建成功且没有编译警告；`/Applications/Prism.app` 报告版本 `1.1.0`、构建号 `2`；可执行文件包含 `arm64` 与 `x86_64`；`codesign --verify --deep --strict` 通过；签名权限包含 `com.apple.security.app-sandbox` 与 `com.apple.security.network.client`；安装后的 Prism 已成功启动。
