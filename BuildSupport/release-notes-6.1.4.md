# Aidente 6.1.4 · Build 25

本版把软件更新流程重做为单一独立弹窗，并把更新检查源切到自有仓库 `nightfall-yl/Aidente`——从此可通过应用内更新直接拉取 GitHub Release 资产；同时修正「计划任务」卡分隔线、调整设置页若干交互、法律文档改为仓库链接、修正充电 hero 文案。充电策略与底层服务逻辑没有改动。

## 更新内容

### 软件更新流程重构

- **整个更新流程收进一个独立弹窗**：设置页「软件更新」卡固定两行（当前版本 + 自动检查更新），点「检查更新」立即弹窗并实时跟随状态——正在检查 / 无可用更新 / 发现新版本 / 下载校验安装 / 安装完成 / 失败原因，全部在弹窗内呈现，不再有卡片状态行与系统告警。
- **新增「跳过这个版本」**：被跳过的版本跨启动不再提示（新增 `Defaults.Keys.skippedUpdateVersion` 与 `UpdateService.skipVersion(_:)`），更新的版本仍会提示。
- **新增「取消更新」**：下载与校验阶段可取消，回到空闲并清理临时文件；安装阶段已交棒外部 updater 不可取消、只给「后台继续」。

### 更新检查源切到自有仓库

- 全部发行版地址由上游 `buffoons8-sketch/Aidente` 换为 `nightfall-yl/Aidente`（releases 页面、latest API、下载与校验 URL、官方下载白名单）。6.1.4 起应用内更新从 GitHub Release 拉取 `Aidente-6.1.4-macOS-arm64.zip` 并校验 `SHA256SUMS-6.1.4.txt`。

### 设置页交互与链接

- 「关于 → 软件更新」卡固定两行并删除「查看 GitHub 发行版」按钮（链接挂到副标题）；「仪表盘 → 访问仪表盘」删除状态文案行与卡头横线；「自动化 → 计划任务」把「添加计划任务」移到卡头右侧，无任务时不显示卡头分隔线；新增 / 恢复「Apple 快捷指令」卡（6 条 URL + 中英说明）。
- 「关于」页法律文档按钮改为 GitHub 链接：「查看开源许可证」「查看第三方声明」打开 `nightfall-yl/Aidente` 仓库文档，不再打开 app 包内文件。

### 文案修正

- 充电 hero 状态「充电中」改为「等待充电」，明确该状态表示「策略已请求充电」而非硬件实测正在充电；顶部标题栏的「正在充电」保持不动。

## 安装与升级

适用于 Apple Silicon MacBook、macOS 14 及以上。下载 DMG 后将 Aidente.app 拖入「应用程序」；6.1.3 及以上也可通过应用内检查更新安装（从本版起更新源为 `nightfall-yl/Aidente` 的 GitHub Release）。

升级后若已开启「管理充电」，Aidente 会在启动时自动提示重新授权，通过 macOS 管理员弹窗更新应用及后台服务的身份登记。管理员密码只由系统弹窗接收。发行包沿用 ad-hoc 完整性签名，未经 Apple 公证；首次打开可按 macOS 提示从 Finder 右键选择「打开」。

本版提供 `Dist/Aidente-6.1.4.dmg`（3.7M）、`Aidente-6.1.4-macOS-arm64.zip`（3.2M）与 `SHA256SUMS-6.1.4.txt`，发布于 GitHub Release `6.1.4`。

## 验证范围

`zsh BuildSupport/build_app.sh` 完整构建 Exit 0，`codesign` 报 `valid on disk` / `satisfies its Designated Requirement`；`zsh BuildSupport/make_dmg.sh` Exit 0，输出 `Dist/Aidente-6.1.4.dmg`，`hdiutil verify` 结果为 VALID。bundle 内 `Info.plist` 为 **6.1.4 / 25**。构建日志仅剩第三方 `Vendor/Defaults` 中 `onChange(of:perform:)` 在 macOS 14 已弃用的警告；`Aidente/` 下零警告。

`zsh BuildSupport/test_charging.sh` **138 项充电、睡眠、固件、回滚与读回检查全部通过**。

本版改动集中在软件更新流程、设置页交互与文案，仍需在实机逐项核对：更新弹窗六态流转（检查 / 无更新 / 有更新 / 下载校验 / 安装 / 失败）、「跳过这个版本」跨启动不重复提示、「取消更新」在下载阶段正确回到空闲；设置页计划任务卡无任务时的分隔线、法律文档链接跳转。充电策略主体未改动，充电与持续合盖睡眠 / 唤醒的供电行为未因本版重新做硬件回归；macOS 26+ 的液态玻璃分支表现仍需在 26 环境实机核对。
