# 更新日志

记录 Aidente 的变更。格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，使用中文。

项目当前 bundle 版本为 **6.1.4 / Build 25**（`BuildSupport/Info.plist`、`BuildSupport/ReaderInfo.plist`、`Aidente.xcodeproj/project.pbxproj` 六个构建配置与 `AGENTS.md` 已同步）。`[6.1.4]-2026-11-14` 汇总 6.1.3 发行之后的全部改动（更新流程重构为独立弹窗、更新检查源切到 `nightfall-yl/Aidente`、计划任务卡修正、设置页交互与法律文档链接调整、充电状态文案修正），已于 2026-11-14 正式发行：GitHub Release `6.1.4`，资产含 `Aidente-6.1.4.dmg` / `Aidente-6.1.4-macOS-arm64.zip` / `SHA256SUMS-6.1.4.txt`，自动更新源即本仓库。带版本号的发行说明见 `BuildSupport/release-notes-*.md`。

## [6.1.4]-2026-11-14

### 变更

**更新**

- **更新检查源与发行资产切到 `nightfall-yl/Aidente`**：`UpdateService.swift` 里全部发行版地址由上游 `buffoons8-sketch/Aidente` 换为本仓库，含 releases 页面、latest API 与 latest 页面、重定向 tag 路径校验、下载与校验文件 URL、官方下载 URL 白名单、检查中状态文案及预览 fixture。已发行的 6.1.3 Release 现同时提供 `Aidente-6.1.3.dmg`、`Aidente-6.1.3-macOS-arm64.zip` 与 `SHA256SUMS-6.1.3.txt`，自动更新的 API 主路径与重定向 fallback 校验链均有对应资产。
- **整个更新流程收进一个独立弹窗**：设置页「软件更新」卡固定两行、不加状态行；点「检查更新」立即弹窗并实时跟随 `UpdateService.phase` 切换——正在检查、无可用更新（「当前已是最新版」+ 版本胶囊）、发现新版本、下载 / 校验 / 安装、安装完成与失败原因全在 `AboutSettingsView.swift` 的 `UpdateProgressSheet`（560 宽）内呈现。弹窗只显示当前状态（图标 + 标题 + 一句说明 + 版本胶囊），没有卡头行、阶段清单、进度条与状态文案；底部按状态提供「后台继续」/「完成」/「关闭 + 重试」/「跳过这个版本 + 立即更新」，其中下载与校验阶段（`.downloading` / `.preparing`）额外提供「取消更新」（ghost 按钮，调 `UpdateService.cancelInstall()` 取消 install Task，`performInstall` 捕获 `CancellationError` 后回到 `.idle`、清理临时文件），安装阶段（`.installing`）已交棒外部 updater 不可取消、只给「后台继续」。新增 `Defaults.Keys.skippedUpdateVersion` 与 `UpdateService.skipVersion(_:)`，被跳过的版本跨启动不再提示、更新的版本仍会提示；删除 `presentUpdatePrompt` 的「发现新版本」NSAlert 与 `promptedVersions`，预览方式改为直接置 `.available`。`UpdateService.swift` 去掉检查 / 安装失败三处与 sheet 重复的 `presentErrorAlert`，保留启动授权失败告警；`settings-redesign-prototype.html` 按「添加计划任务」弹窗的形式展示 6 种 sheet 状态与流转说明。

**设置页与界面**

- **设置页交互与公共组件调整**：`settings-redesign-prototype.html` 与 Swift 源码同步——`AidenteTheme.swift` 的 `AidenteCard` / `AidenteSectionHeader` 新增卡头右侧动作按钮（`headerAccessory`）、副标题内链（`AidenteCardSubtitleLink`，系统文字色、无下划线）与 `showDivider: false`；「关于 → 软件更新」卡固定两行「当前版本（`v<版本> (Build <号>)` + 检查更新按钮）/ 自动检查更新」，删掉「查看 GitHub 发行版」按钮并把链接挂到副标题「GitHub 发行版」；「仪表盘 → 访问仪表盘」删除状态文案行与卡头横线，「打开仪表盘」移到卡头右侧；「自动化 → 计划任务」把「添加计划任务」移到卡头右侧，并在其后加回「Apple 快捷指令」卡（6 条 URL + 中英说明）。零引用的 `UpdateService.openReleasePage()` 已删除。
- **「关于」页法律文档按钮改为 GitHub 链接**：`AboutSettingsView.swift` 的「查看开源许可证」「查看第三方声明」不再用 `openBundledDocument` 打开 app 包内的 `LICENSE.txt` / `THIRD_PARTY_NOTICES.md`，改为用 `NSWorkspace.shared.open` 打开 `nightfall-yl/Aidente` main 分支的同名文档；零引用的 `openBundledDocument` 已删除。`settings-redesign-prototype.html` 同步把两个按钮渲染成新标签打开的可点击链接。
- **「计划任务」卡无任务时不显示卡头分隔线**：`AutomationSettingsView.swift` 的 `AidenteCard` 调用 `headerAccessory` 重载时显式传入 `showDivider: !scheduleStore.tasks.isEmpty`，`ScheduleStore`（`Models/ScheduleTask.swift`）为 `@Observable`，增删任务时横线随 `tasks` 出现 / 消失，与原型 `settings-redesign-prototype.html`（无任务时 `renderCard` 不输出 `card-divider`）一致；有任务时仍保留卡头与首行之间的分隔。

**状态文案**

- **hero 状态文案改为「等待充电」**：`ChargeManager.swift:43` 的 `ChargeOperationStatus.charging.title` 由 `AidenteL10n.t("充电中", "Charging")` 改为 `AidenteL10n.t("等待充电", "Waiting to Charge")`，明确该状态表示「策略已请求充电」而非硬件实测正在充电；顶部标题栏的「正在充电」保持不动。

### 验证

- **版本号升级到 6.1.4 / Build 25**：`BuildSupport/Info.plist`、`BuildSupport/ReaderInfo.plist`、`Aidente.xcodeproj/project.pbxproj` 六处 `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`、`AGENTS.md` 当前版本声明已同步；`[6.1.4-preview]` 归档为 `[6.1.4]-2026-11-14`，新建 `BuildSupport/release-notes-6.1.4.md`。
- `zsh BuildSupport/build_app.sh` Exit 0（`codesign` 报 `valid on disk` / `satisfies its Designated Requirement`），产物 `Dist/Aidente.app` 的 `Info.plist` 为 **6.1.4 / 25**；唯一警告仍为第三方 `Vendor/Defaults/Sources/Defaults/SwiftUI.swift:229` 的 `onChange(of:perform:)` deprecated。
- `zsh BuildSupport/make_dmg.sh` Exit 0，输出 `Dist/Aidente-6.1.4.dmg`（3.7M，卷名 `Aidente 6.1.4`），`hdiutil verify` VALID；另产出 `Aidente-6.1.4-macOS-arm64.zip`（3.2M）与 `SHA256SUMS-6.1.4.txt`。
- **充电回归**：`zsh BuildSupport/test_charging.sh` Exit 0：**PASS: 138 charging, sleep, firmware, rollback and readback checks**。
- **发行**：GitHub Release `6.1.4`（tag `6.1.4`，已置 latest）发布于 `nightfall-yl/Aidente`，资产含上述 dmg / zip / SHA256SUMS；代码已提交并推送 `main`、打 tag `6.1.4`。

### 修订

- **修复更新器无法完成更新（2026-11-14 当日补发）**：6.1.4 初版发行后，从 6.1.3 升级到 6.1.4 在「安装」阶段报「无法完成更新 / Aidente did not quit before the update timeout」。根因为更新进度以**模态 SwiftUI `.sheet`** 呈现，而 `NSApplication.terminate` 在仍有模态 session 时被推迟、app 实际未退出，外部 updater 等满 60s 超时。修复：当 `UpdateService.phase` 变为 `.installing`（即将交棒外部 updater 并 terminate）时，于 `AboutSettingsView.swift` 先 `dismiss` 该 sheet 以消去阻塞 terminate 的模态 session，并把 `performInstall` 里的宽限由 450ms 提到 800ms 确保 sheet 退场动画走完。`UpdaterHelper/main.swift` 的 `processIsZombie` 此前把 `proc_bsdinfo` 的 `pbsd_status` 错读成偏移 4（实为 `pbsd_ppid`），已改为偏移 12，zombie 识别真正生效（双保险）。

- **hero 卡新增「点击修复」备用入口（2026-11-14 补发）**：当 hero 显示「充电控制未生效」且根因为后台控制服务（helper）缺失 / 身份不匹配 / 连接或健康检查失败时，hero 顶部状态行变为可点击并显示「点击修复充电控制」提示（要求 `manageCharging` 开启且不在磁盘映像运行）；点击复用与启动 / 更新后重新授权同一路径（`ChargingHelperManager.repair()`，触发一次 macOS 管理员密码弹窗），完成后经 `ChargeManager.retryControlAfterRepair()` 重新下发充电策略。门控用 `ChargingHelperManager.needsRepair`（`!isInstalled || failure != nil`）区分「helper 授权类故障」与「瞬时 SMC 命令失败」（后者不弹管理员密码、由周期轮询自愈），避免对瞬时错误误给修复入口；修复期间 hero 就地显示「修复中…」，失败保留原错误。新增 `ChargeManager.canQuickRepair` / `attemptQuickRepair()` 与 `MenuViewModel` 透传，`AidenteL10n` 补「修复中…」「点击修复充电控制」中英词条。该入口作为授权意外消失时的备用触发点，避免用户只能去「充电管理」重开关开关。

- **两轮补发均已提交并同步 tag**：更新器修复与 hero 入口两次补发都已提交到 `main`，`tag 6.1.4` 已移到包含全部补发的提交并强制推送，GitHub Release `6.1.4`（本仓库 `nightfall-yl/Aidente`）的 dmg / zip / SHA256SUMS 同步覆盖上传（silent patch，版本号与 tag 不变）。

## [6.1.3]-2026-11-13


### 变更

**设置页框架与导航**

- **设置页重构为 macOS 系统设置风格**：`SettingsView.swift` 由分段 Picker 改为左侧 236pt 侧栏 + 右侧详情（`HStack` + 贯穿 `Divider()`），选中项为 80% 系统蓝；新增 `permissions` tab 与 `PermissionsSettingsView.swift`（重新检查授权、修复控制服务），充电管理里的授权提示与修复按钮迁入该页；「访问仪表盘」移到仪表盘 tab 末尾、「快捷操作」移到充电管理 tab 末尾。各页新增 `detailSubtitle` 中英双语说明；`settings-redesign-prototype.html` 为对应原型。
- **设置页标题栏底边补 1pt 分隔线**：窗口使用 `.fullSizeContentView` + 透明标题栏，系统不绘制标题栏分隔线，标题栏与内容之间缺一条贯穿整窗的横线，竖线看起来像凭空长出。`SettingsView.swift` 的主 `HStack` 增加 `.overlay(alignment: .top)`，用 `AidenteSurfaceTokens.stroke(scheme:)` 画 1pt 贯穿线（深浅色自动适配）；详情页标题下的 `Divider().padding(.horizontal, 20)` 保持只在右侧，竖线仍贯穿全高。
- **详情区标题随内容一起滚动**：`SettingsView.swift` 的 `detailPane` 改为外层 `ScrollView { VStack { 页标题 + 副标题 + Divider + 分页内容 } }`；`AidenteTheme.swift` 的 `AidenteSettingsPage` 去掉自带的 `ScrollView`（避免嵌套滚动），只保留 `LazyVStack` + 740 宽居中容器。7 个设置分页由外层 ScrollView 统一承接；标题栏那条 1pt 线仍在 `HStack` 上保持固定。
- **左右标题区统一规格**：`SettingsView.swift` 左侧栏标题区（徽章 + Aidente + 电池养护控制台）改为与右侧详情页标题区（徽章 + 页标题 + 副标题）一致：徽章 34 pt（去掉 `cornerRadius: 8`，与右侧同用默认圆角）、标题 20 pt bold、副标题 12 pt secondary、HStack spacing 11；上下 padding 同为 16 / 12，两侧内容等高、垂直中心落在同一水平线。侧栏 7 个导航项的尺寸、间距、顺序一律不动；水平 padding 仍为左 12 / 右 20。
- **侧栏导航项整行可点击**：`SettingsView.swift` 的 `sidebarRow` 使用 `.buttonStyle(.plain)` 时，末尾 `Spacer()` 与未选中项的 `Color.clear` 背景不参与命中测试，只有图标和文字可点。在 `.background(...)` 之后加 `.contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))`，把整行（含 padding 与右侧空白）纳入命中区域，形状与选中高亮一致；行间 4 pt 间隙保持不动。
- **第一个导航项与第一张卡片上边距对齐**：`SettingsView.swift` 侧栏 `ScrollView` 内的 `VStack` 增加 `.padding(.top, 21)`（右侧标题区之后还有 1pt `Divider()` 与 `AidenteSettingsPage` 顶部 20pt padding）。左右标题区高度本就相同，因此「通用」行与第一张卡片顶边落在同一水平线；7 个导航项整体下移 21pt，彼此间距与顺序不变。
- **窗口标题栏遮罩（滚动截断）**：`SettingsView.swift` 在 `ZStack` 最上层加一层独立标题栏遮罩（`AidenteChromeBar()` 不透明 chrome 材质，高 28 pt = 系统隐藏标题的标题栏高度），向上偏移 28 pt 覆盖到窗口顶部；1pt 贯穿线移到遮罩底边。滚动时卡片被遮罩截断/遮住，不再压在标题栏前面，与原型 `.titlebar`（chrome 底 + `border-bottom`）一致；遮罩 `allowsHitTesting(false)` 不挡交互。
- **设置页左右头部中心线对齐**：`SettingsView.swift` 左右侧栏标题区与详情头部新增共享常量 `headerContentHeight = 46`（`.frame(height:)` 固定内容高度），侧栏 App 图标（34pt 布局帧）与详情页 34pt 徽章几何中心同落在 y = 16 + 23 = 39pt 的水平线上；此前详情页标题+副标题文字列（约 41pt）高于徽章使头部自然变高、徽章下沉错位。侧栏导航行 `.padding(.top, 21)` 的首行对齐逻辑不动。
- **设置页卡片结构**：侧栏「权限管理」更名「睡眠管理」，整页只留「睡眠行为」卡（三个睡眠开关自充电页迁入），删除「检查后台服务状态」卡。通用页删除「通知」卡并整删系统通知功能，MagSafe 指示灯卡自充电页迁入。充电页收敛为 充电管理 / 巡航模式 / 高温保护 / 电池校准 四卡，「启用自动放电」并入「充电管理」卡（默认关闭）。自动化页删除「Apple 快捷指令」卡与「还没有计划任务」空状态，tab 更名「自动化」。诊断页整合为「诊断与导出」+「可选 CLI」两卡，「诊断记录未启动」改为普通控件行（右侧内联开始 / 停止按钮与录制计时），复制 / 导出反馈移至页面底部。侧栏标题区去掉第二行标语，只保留 App 图标 + Aidente；App 图标加 `.scaleEffect(1.18).clipped()` 裁掉自带留白。
- **HTML 原型**：`settings-redesign-prototype.html` 的卡片清单、控件、配色、色板图例与规则说明以 Swift 源码为基线同步；保留 `renderCard` 单点覆盖与 `--tab-badge-size` 唯一尺寸来源。segmented 行不再把首选项当字段名，「电量数字位置」「高温保护时的灯光」恢复为带字段名的 Picker 控件行；图例补齐 legacy 徽章例外与 sheet 标题 34 说明；清除未引用的 CSS 类 / 变量、失效的按钮 `kind` 参数与空转的 Inset 替换。交互元素补 `role` / `tabindex` / `aria-*` / 键盘激活与焦点环，标题改为 `h1` / `h2`，主题切换不再重渲染以保留控件状态。正文与数值读数统一用系统语义文字色，随深浅色自动保持对比度；滑杆数值 `.slider-val` 用 `var(--text)`，不再注入卡色可读档，相关明暗档计算 helper 已删除；侧栏选中态保持 macOS 15 系统蓝（浅色 #007AFF / 深色 #0A84FF，各 80%），原型与 Swift 源码一致。

**设置页品牌与图标**

- **左侧标题区主徽章换成电池 + 闪电**：`SettingsView.swift:174-185` 侧栏标题区的徽章由 `bolt.heart.fill` + `[jade, mint]` 改为「关于」页同款 `battery.100percent.bolt` + `[jade, mint, gold]`（参照 `AboutSettingsView.swift`），尺寸仍为 34 pt、其余布局不动。`AidenteIconBadge` 只取 `colors.first` 作底色/描边、`colors.last` 作图标色，因此中间 `mint` 不参与绘制，效果是绿色半透明圆角底 + 绿色细描边 + 橙黄色电池闪电；未新增图像资源，`BuildSupport/Aidente.icns` 是完整应用图标（深蓝底），与设置页小徽章不是同一图形。
- **左侧标题区主徽章改为 App 图标**：`SettingsView.swift` 侧栏标题区原先的 `AidenteIconBadge`（先是 `bolt.heart.fill`、后改 `battery.100percent.bolt` + `[jade, mint, gold]`）替换为运行中 Aidente 的 App 图标 `Image(nsImage: NSApp.applicationIconImage)`，尺寸仍为 34 pt、其余布局（spacing 11、padding 16/12、20pt bold 标题、12pt 副标题）不动。不再使用 SF Symbol 近似，直接呈现完整应用图标（深蓝圆角底 + 绿色电池 + 橙黄闪电）。

**设置文案与状态**

- **设置文案修订**：「登录时启动 Aidente」副标题改为「登录后自动启动，并在菜单栏显示图标」；「菜单栏实时读数」副标题改为「在电量、功率或两者同时显示之间切换。」；「高温保护」副标题改为「温度超过阈值时暂停充电，并通过约五分钟的延迟避免频繁切换。」，三条英文词条同步进 `AidenteL10n.swift`。
- **修英文漏翻**：「自动检查更新」副标题词典 key 缺句尾句号导致 `AidenteL10n.t()` 匹配失败、英文界面回退显示中文；补带句号词条。批量核对设置页全部句号结尾直译字面量，仅此一处失配。
- **语言选项**：中文界面下语言 Picker 的「English」显示为「英语」（`AppLanguage.english.title` 改 `AidenteL10n.t("英语", "English")`）。

**数据与充电服务**

- **`ChargerInfoProvider` 充电器统一显示名（并入 `IOKitService` 数据流）**：新建 `Aidente/Services/ChargerInfoProvider.swift`，仅保留 `displayName(adapter: AdapterMetrics)` 一个纯函数，把 `AdapterMetrics` 里的制造商 / 是否 Apple / 功率 / PD 协议信息翻译成本地化显示名（五态统一使用「电源适配器」一词，英文 "Power Adapter"）。原先独立的 `ACChargerInfo` 结构与 `read()` IOKit 读取逻辑已删除——`AdapterMetrics`（`Models/BatteryMetrics.swift`）新增 `manufacturer` / `isApple` 两个字段，由 `IOKitService.getAdapterSpecification()` 从同一份 `AppleSmartBattery.AdapterDetails` 读取、随插拔事件（`kIOGeneralInterest`）刷新，彻底消除与 `IOKitService` 的重复读取。
- **充电器显示名接入仪表盘「彩色能量流」标题右侧**：`DashboardPopoverView.swift` 的 `powerSummary` 标题 `HStack` 在 `Spacer()` 之后、`Label("彩色能量流")` 右侧新增 `Text(viewModel.chargerDisplayName)`（10.5pt medium、`.secondary` 灰字、居右）。`MenuViewModel` 新增 `chargerDisplayName` 属性，在 `updateFormattedValues` 里由 `ChargerInfoProvider.displayName(adapter:)` 计算；随 IOKit 流与语言切换自动更新，视图不再自行读取 IOKit。

**配置与代码整理**

- **移除「实时功率」设置卡与弹窗对应三处读数**：`DashboardSettingsView.swift` 删除「实时功率」整张卡（电源来源 / 电池功率数据 / 适配器功率数据三个开关）及对应的三条 `@Default` 属性，仪表盘 tab 现只剩「状态信息」+「访问仪表盘」两张卡。`DashboardPopoverView.swift` 的 `powerSummary`（彩色能量流）同步删掉标题右侧的电源来源文字、底部两行电气读数 Label（分别由 `showPowerSource` / `showInternalPower` / `showExternalPower` 控制）及三条 `@Default` 属性，卡片只保留标题 + `CompactPowerFlowDiagram` 分流图；分流图节点内的电压/电流小字属于图本身、不受这三个开关控制，保留不动。`DefaultsKeys.swift` 的三个 key 与 `AidenteL10n.swift` 的对应词条**保留**：零引用的旧 `MenuBuilder.swift` 仍在编译范围内并引用它们，删掉会破坏构建；已保存的用户偏好从此不再被真实 UI 读取，但不会报错。
- **「软件更新」卡去重**：idle 态不渲染状态面板——原「等待检查更新 / 更新来源：GitHub 正式发行版」与卡副标题、「自动检查更新」toggle 三重重复；点「检查更新」后面板才出现。
- **代码整理（不影响功能）**：① `ChargingSettingsView` 抽私有 `InlineSliderRow`，四处「Slider + 数值读数」行合一（Double 域，视觉不变）；② `AidenteTheme` 新增 `aidenteInstallErrorAlert` ViewModifier，充电/权限两页错误 alert 去重；③ 三处 `@State` 持有的共享单例（`ChargingHelperManager.shared` ×2、`ScheduleStore.shared`）改 `private let`；④ `ShortcutCommand` 列表静态化（URL + 词条 key 常量，翻译保留渲染时解析，切语言不受影响）；⑤ `ScheduleActionKind.icon/colors` 移至 `AidenteTheme.swift`，删除设置页五处未使用的 `@Default(.appLanguage)` 死声明（`SettingsView` / `GeneralSettingsView` 的为语言切换刷新机制，保留）。
- **`test_charging.sh` SDK 选择与 `build_app.sh` 对齐**：脚本优先硬编码 `MacOSX15.5.sdk`，而 `build_app.sh` 已改为 `xcrun` 动态取最新 SDK（macosx26.2），产物模块与测试加载不匹配、回归无法编译。改为同样 `xcrun` 优先、15.5 兜底。

**权限与后台控制**

- **后台控制服务：每次启动检测并一键重新授权**：`AppDelegate` 启动时调用 `UpdateService.checkControlAuthorizationOnLaunch()`，条件为 `ChargingHelperManager.refreshStatus()` 后 `.notInstalled && Defaults[.manageCharging]`；不依赖 `last-install-result.json`，因此自动更新与手动把新 bundle 复制进 `/Applications` 后启动都会提示。自动更新成功时标题带版本号，手动替换时用通用文案；「立即重新授权」走 `repair()` → macOS 管理员弹窗，成功后 `controlRetryHandler` 立即恢复充电控制。`consumeInstallResultIfNeeded()` 返回 `InstallResultOutcome`，每次启动最多一个弹窗。删除「修复控制服务」卡片与手动入口，并清理设置页、HTML 原型、README / README_en、管理员安装说明、维护测试说明、6.0.2–6.1.3 发行说明、CODEX_HANDOFF、`AidenteL10n` 死词条及 `ChargingHelper` 报错中所有指向该按钮的旧文案；睡眠管理页副标题改为「配置 Mac 睡眠与退出应用后的充电行为。」
- **「修复控制服务」改用橙红色**：`PermissionsSettingsView.swift` 里「修复控制服务」卡片的图标徽章、`AidenteNotice`、按钮样式三处颜色由 `AidenteTheme.chargingColors`（绿 `jade/mint`）改为 `AidenteTheme.aboutColors`（`[coral, amber]` ≈ `#FA574D → #FF972E`），取自仪表盘 hero「充电控制未生效」的错误态橙红；静态数组不随深浅色切换，未新增主题常量。「重新检查授权」卡片仍为蓝色 `generalColors`。
- **「重新检查授权」改为真实的状态检查**：原按钮调用 `ChargingHelperManager.refreshStatus()`（只判断 `LocalControlInstaller.installedMatchesCurrentApp()`，与「登录项与扩展」批准无关），服务未安装时点击无任何反馈。`PermissionsSettingsView.swift` 将该卡改为「检查后台服务状态」：点击后刷新并在卡内显示结果（已安装且身份匹配 → 绿色勾选；未安装 / 不匹配 → 橙红警示并引导使用「修复控制服务」），未点击时显示中性说明；按钮改为「检查状态」。新增文案全部走 `AidenteL10n.t(_:_:)` 中英双语。移除已无用的 `checkApprovalStatus()` 与 `toggleManageCharging(_:)`；`repairControlService()` 及底层服务逻辑不变。
- **「权限管理」页整改**：① 修复按钮加 `helperManager.isBusy` 防护（忙时禁用 + 文字/图标切「正在修复…」），杜绝连点重复触发管理员弹窗；② 修复 Task 结束后自动 `refreshStatus()` 并置 `hasCheckedStatus = true`，状态卡即时转绿、无需手动复查。`aboutColors` 橙红强调色为用户刻意设计，保留。
- **修复插电后菜单栏图标不自动切换为充电态**：`BatteryService.handleIOKitUpdate` 检测 `adapterConnected` false→true，事件驱动地安排 1 秒与 3 秒两次跟进 SMC 轮询（`postConnectPollTask`），`stop()` 同步取消；弹窗关闭期间也能刷新功率来源，不引入常驻轮询开销。

**各设置页整改**

- **「关于」页整改**：① 「Aidente」Hero 卡整体删除（用户判定无实质作用），页内剩 软件更新 + 法律与开源 两卡；② `legalBlock` 三个标题补 `AidenteL10n.t()`，修英文漏翻；③ 法律卡新增「查看第三方声明」按钮（打开内置 `THIRD_PARTY_NOTICES.md`），抽公共 `openBundledDocument(named:extension:)`。
- **「计划与自动化」整改**：① `ScheduleActionKind` 新增 `.resumeCharging`「恢复充电」动作（`ChargeManager.executeScheduledTask` 走 `resumeNormalManagement()`），补齐与快捷指令 `aidente://resume` 的能力对齐；② 新建任务弹窗滑杆按动作区分——充电上限 20–100、放电目标 20–80，切换动作时 `onChange` 自动 clamp；③ DatePicker 加 `in: Date()...` 只能选未来时间；④ 快捷指令卡改为 6 条「等宽 URL + 灰色说明」逐行展示；⑤ 任务行日期格式化 locale 跟随语言（en_US / zh_CN，原硬编码 zh_CN）；⑥ 任务行开关 Toggle 移至行尾（macOS 惯例）；⑦ 副标题补「或恢复充电」，词条同步。
- **「通用」页整改**：① 「使用硬件电量百分比」开关 + Notice 从「菜单栏实时读数」卡迁出，在「充电管理」页新增独立「电量读取方式」卡（始终可见）；② 「充电状态变化时通知」副标题动态化——总开关禁用时显示「已被“关闭全部通知”停用」（新增词条 "Disabled by Turn Off All Notifications"）。
- **「仪表盘」页整改**：① tab 副标题改为「配置仪表盘顶部的时间信息与打开方式」（原副标题名不副实：面板显示项开关在仪表盘内部、本页无功率监测设置）；② 「访问仪表盘」卡提示补「面板显示项可在仪表盘内配置」。
- **「诊断」页整改**：① `statusMessage` / `errorMessage` 两个 Notice 从「导出诊断包」卡内移至页面级——复制编号、复制 CLI 路径、停止记录、导出完成的反馈不再跨卡错位；② 错误 Notice 改 `[coral, amber]` 警示色。
- **「充电管理」页整改**：① 充电上限滑杆 `50...100` → `20...100`，与计划任务创建界面及调度器内部 clamp 域对齐，低于 50% 的调度任务不再被滑杆静默改写；② 「睡眠与退出行为」卡三个开关补 `.disabled(!hasChargingControl)` + 置灰。
- **充电管理页状态回显与数值读数排版**：`ChargingSettingsView.swift` 在「充电上限」滑杆之后新增 `AidenteNotice`，以 `AidenteL10n.t` 中英双语显示当前 `chargeLimit` 与 `sailingMode`（原型为静态示例文案），色对随卡继承 `chargingColors`、徽章沿用 legacy 式 22。充电管理卡顺序为 管理充电开关 → 固件警告 → 充电上限 → 状态文案 → 自动放电。滑杆数值与「恢复充电电量」等只读读数统一为 `.body` 等宽常规字重，颜色一律 `Color.primary` / `var(--text)`，与行标签同调；`InlineSliderRow` 移除 `accent` 参数的字号差异，原型 `.slider-val` 同步去掉 `font-weight: 600`、与 `rStepper` 同为 13px 常规字重。这是「同一卡内颜色一致」规则里数值读数的唯一例外（颜色与字重均不随卡色）。
- **睡眠行为卡三个开关补齐副标题（中英双语）**：`PermissionsSettingsView.swift`「睡眠行为」卡三个 `AidenteSettingToggle` 新增副标题——「达到上限前阻止睡眠」说明仅拦空闲自动睡眠、合盖仍会睡眠；「睡眠时暂停充电」说明进入睡眠（含合盖）即暂停；「退出 Aidente 后保持暂停」说明退出后保持充电受控状态。三条中文文案及英文对照进 `AidenteL10n.swift`，原型已先行对齐。
- **仪表盘「自动保护」卡：睡眠暂停 pill 替换为阻止睡眠、调整顺序并中英双语**：`DashboardPopoverView.swift` 的 `automaticProtection` 卡把原「睡眠暂停」`ProtectionPill`（绑定 `stopChargingWhileSleeping`）替换为「阻止睡眠」（绑定 `disableSleepUntilChargeLimit`，即设置页「达到上限前阻止睡眠」），「巡航」改名「电池巡航」；三个 pill 顺序由 睡眠暂停 → 高温保护 → 巡航 调整为 电池巡航 → 高温保护 → 阻止睡眠。三个 pill 标题经 `AidenteL10n.t` 本地化：电池巡航 / Battery Sailing、高温保护 / Heat Protection、阻止睡眠 / Prevent Sleep；`AidenteL10n.swift` 原有死条目「睡眠暂停 / Sleep Pause」「巡航 / Sailing」替换为新标签。

**配色体系**

- **设置页配色重排（三原则）**：① 侧栏 7 tab + 每页首卡 = tab 身份色——`AidenteTheme` 新增 `permissionColors = [ocean, violet]`（权限管理不再与通用撞蓝），诊断 tab/首卡 → `advancedColors`（不再与仪表盘撞紫粉）；② 第二张卡起卡色跟功能语义；③ **相邻卡不得同色**：外观卡→紫粉、访问仪表盘卡→蓝、快捷指令卡→紫粉、电量读取方式卡→蓝、自动放电卡→绿、快捷操作卡→绿；卡内 Notice/按钮/行徽章颜色同步对齐。改后各页节奏：通用 蓝→紫→蓝→绿→橙，仪表盘 紫→蓝，充电 绿→蓝→绿→靛→紫→蓝→珊瑚→橙→绿，权限 蓝紫→珊瑚，自动化 橙→紫，诊断 靛→蓝→靛→紫粉，关于 珊瑚→橙→珊瑚。
- **设置页配色**：侧栏 7 tab 身份色 = 通用 `generalColors`、仪表盘 `dashboardColors`、充电管理 `chargingColors`、睡眠管理 `advancedColors`、自动化 `automationColors`、诊断 `aboutColors`、关于 `permissionColors`（`[ocean, violet]`）；每页首卡与 tab 同色，其余卡按功能语义取色——「访问仪表盘」`automationColors` 橙、「巡航模式」`generalColors`、「高温保护」`[amber, coral]`、「电池校准」`automationColors`、「可选 CLI」`permissionColors`、「法律与开源」`generalColors` 等。所有动作按钮调用点的色对已统一到所在卡色。
- **同一张卡片内颜色一致**：`AidenteCard` 通过 `aidenteCardColors` Environment 把本卡色对发布给全部子视图并 `.tint(colors.first)`；卡头徽章、行徽章、开关两态、状态点、状态文案、动作按钮、Picker / Slider / Stepper 一律继承，不设强调色 / 状态色例外；数值读数统一用系统文字色 `Color.primary` / `var(--text)`（含滑杆后面的数值与「恢复充电电量」等只读读数），与行标签同色，不随徽章色或卡色变化。徽章 = 色对 135° 渐变实底 + 白图标，侧栏 100% 饱和、详情区 90% 饱和，恒定不随主题；状态文案 7.5% 底 / 20% 描边、动作按钮 20% 底 / 34% 描边、开关开态首色实底 / 关态首色 16% 半透明，三者叠在卡背景上随主题变化。相邻卡片允许同色或相近色。
- **徽章与行的几何规范**：页标题 34 / 卡头 28 / 行·Inset 26 / 状态文案跟随侧栏 tab 徽章（`--tab-badge-size`，当前 22）；状态文案徽章用 `AidenteIconBadge` legacy 式（首色 16% 底 / 34% 描边 / 尾色图标）并与文字垂直居中；所有 toggle / seg / control 行徽章包进 28px 槽位，右缘对齐卡头徽章。「添加计划任务」sheet 标题徽章 34、任务设置卡 5 个行徽章 22 legacy 式，卡内色对由 `aidenteCardColors` 覆盖为 `automationColors`。

### 验证

- **版本号升级到 6.1.3 / Build 24**：`BuildSupport/Info.plist` 与 `BuildSupport/ReaderInfo.plist` 的 `CFBundleShortVersionString` / `CFBundleVersion`、`Aidente.xcodeproj/project.pbxproj` 六处 `MARKETING_VERSION` 与六处 `CURRENT_PROJECT_VERSION`、`AGENTS.md` 的当前版本声明已同步。`[未发布]` 归档为 `[6.1.3]-2026-11-13`，新建 `BuildSupport/release-notes-6.1.3.md`；历史发行说明、`settings-redesign-prototype.html` 与 `UpdateService.swift` 里针对旧版本的比较测试数据保留原值。
- `zsh BuildSupport/build_app.sh` Exit 0（ad-hoc 签名，`codesign` 报 `valid on disk` / `satisfies its Designated Requirement`），日志 `/tmp/aidente-build-6.1.3.log`，产物 `Dist/Aidente.app` 的 `Info.plist` 为 **6.1.3 / 24**；唯一警告仍为第三方 `Vendor/Defaults/Sources/Defaults/SwiftUI.swift:229` 的 `onChange(of:perform:)` deprecated。**本次构建与当前源码一致**：覆盖设置页重构与文案修订、标题栏 1pt 贯穿线、标题区随内容滚动、左右标题区统一、导航项整行命中、第一个导航项与第一张卡片上边距对齐、「修复控制服务」橙红 `aboutColors`、窗口标题栏遮罩、「重新检查授权」改为后台服务状态检查、左侧标题区主徽章替换、移除「实时功率」设置卡与弹窗三处读数、hero 状态「正在充电」改名「充电中」；标题栏加高 28→38 pt 与分段控件紧凑靠右两处已回退、不在产物内。视觉效果待实机验收。
- **充电回归**：`zsh BuildSupport/test_charging.sh` Exit 0：**PASS: 138 charging, sleep, firmware, rollback and readback checks**（含 `test_charging.sh` SDK 对齐修复后恢复可跑；重构后复跑仍全过）。
- **发行打包（含同日全部改动重出）**：`zsh BuildSupport/make_dmg.sh` Exit 0，输出 `Dist/Aidente-6.1.3.dmg`（3.7M，卷名 `Aidente 6.1.3`），`hdiutil verify` 结果为 VALID。脚本从 bundle 的 `Info.plist` 读版本，输出 `Aidente 6.1.3 (build 24)`；DMG 沿用 ad-hoc 完整性签名，仅适合本机 / 受信分发。
- **提交状态**：本节所述全部改动已提交并推送至 `origin/main`（"Bump to 6.1.3 and add charger info provider, permissions settings, and settings redesign"）。

## [6.1.2]-2026-11-09

### 新增

**仪表盘编辑态与 dock**

- **仪表盘卡片长按编辑 + 底部 dock 显隐 + 整卡拖动排序**：仿 macOS 小组件编辑态。整张卡片任意位置长按 0.5 秒进入编辑态；已显示卡片左上角出现红色减号，点按移回 dock；底部 dock 以实色蓝「图标 + 名称」胶囊只列出未打开的卡片，点按即打开并即时从 dock 消失，dock 为空时整个胶囊区不渲染、不留占位。编辑态底部保留一行操作提示与「已完成」按钮；**六张**可编辑卡片在编辑态下任意位置按住即可拖动重排，无专属拖拽 icon，顺序持久化到 `dashboardCardOrder`（逗号分隔；已存偏好里缺失的卡按默认位置插入，不会被追加到末尾）。
- **dock 胶囊与「已完成」按钮圆角**：均为 `RoundedRectangle(cornerRadius: 8, style: .continuous)`，与「自动保护」三个 `ProtectionPill` 一致；取值收进 `DashboardFooterMetrics.buttonCornerRadius`。
- **编辑态「已完成」按钮**：文字为 `.secondary` 灰，与右上角 `HeaderButton` 图标一致；左右 padding 10pt、垂直 5pt、8pt 圆角，底色 `AidenteSurfaceTokens.controlFill(scheme:)`。
- **「彩色能量流」纳入编辑体系**：`DashboardEditableCard.colorEnergyFlow` 是六张可编辑卡之一，默认顺序首位；显隐复用 `showPowerDistribution`，与其它卡片一样可长按编辑 / 拖动排序 / 进 dock。仪表盘卡片标题与 dock 一致，为「彩色能量流 / Color Energy Flow」；`powerSummary` 直接渲染 `PopoverCompactCard`，无外层显隐门控。
- **「电池健康」纳入编辑体系**：`showBatteryHealthCard` 控制整张指标条显隐，与三个指标开关解耦。指标条三项（电池健康 / 循环次数 / 电池温度）恒显示，`showBatteryTemperature` 默认开启。
- **dock 横向滚动与实色蓝胶囊**：胶囊保持「图标 + 完整标题」，不压缩、不截断；剩余胶囊不足以撑满面板时整行水平居中，超出时左对齐并向右横滑，46pt 行内垂直居中。胶囊为实色 `AidenteTheme.ocean`（`0.24, 0.56, 0.98`）配白色文字与图标，8pt 圆角与「自动保护」三个 `ProtectionPill` 一致。dock 高度固定 46pt，不影响面板高度计算。

**hover 与提示**

- **底部悬停引导 + hover 渐变带**：仪表盘底部 20pt 悬停热区，鼠标悬停时才显示「长按进入编辑模式」以及一条跟随出现的渐变带（正常态完全透明）；渐变带与文字一同 0.15s 淡入、一同消失。该热区同时支持长按进入，保证卡片全部移出后仍能回到编辑态。卡片底边到提示文字收至 **2pt**（编辑态仍保留 11pt，避免 dock 贴住卡片）；提示文字在 20pt 热区内垂直居中（`ZStack` 默认对齐），使最后一张卡片底边与面板底边视觉居中，渐变带仍铺满整个热区。所有新文案走 `AidenteL10n.t(_:_:)` 内联双语（中 / 英），未硬编码单一语言。
- **右上角按钮悬停提示**：header 右上角刷新 / 设置 / 退出三个 `HeaderButton` 用 `.onHover` + `@State` 自绘名称气泡——深底 `Color(white: 0.16, opacity: 0.96)` + 白字，`fixedSize` 保证「刷新 / 设置 / 退出」两字完整显示，`.offset(y: 30)` 浮在按钮正下方，`zIndex(1)` 确保不被下方卡片遮挡，`allowsHitTesting(false)` 不挡交互、0.15s 淡入；同时补 `.accessibilityLabel` 修复读屏无标签。替代 `.help()` 原生 tooltip，避免浮窗每秒重渲染导致 `NSHelpManager` 计时器被反复重置、需等 4–5s 才出现。名称经 `AidenteL10n.t(_:)` 双语（中 / 英），新增 `刷新 / Refresh`、`设置 / Settings`、`退出 / Quit` 三条词条。

### 变更

**设置页与仪表盘配置**

- **设置页-仪表盘**：长按编辑是卡片显隐的唯一入口，设置页不提供模块开关。页面为 访问仪表盘 → 状态信息 → 实时功率 三张卡；`DefaultsKeys.swift` 的 `showPowerDistribution` 等 key 保留，仪表盘仍读写。
- **设置页卡片布局**：「访问仪表盘」卡片组（含 `AidenteNotice` 说明与「打开仪表盘」按钮，打开 `aidente://dashboard`）位于仪表盘 tab 第一个；「电源来源」开关位于「实时功率」组第一个。状态信息组为 系统运行时间 / 电池剩余时间，实时功率组为 电源来源 / 电池功率数据 / 适配器功率数据。
- **仪表盘命名统一**：设置页卡片为「访问仪表盘」、按钮「打开仪表盘」，说明文案为「完整仪表盘 / 独立仪表盘窗口」，与 `AidenteL10n.swift` 的英文词条（`Dashboard Access` / `Open Dashboard` 等）语义一致。CLI 帮助与输出、独立窗口标题（`Aidente Dashboard`）、两张 HTML 原型、`README.md` 均使用仪表盘语义。中文文案与字典 key 成对维护，英文模式不会退回中文原文。
- **dock 英文命名统一**：`DashboardEditableCard.title` 使用单参数 `AidenteL10n.t(_:)` 复用既有词条（`Color Energy Flow` / `Battery Health` / `Capacity & Health Trend` / `Top Energy Apps` / `Quick Care` / `Automatic Protection`），中英文下 dock 与卡片标题一致。
- **dock 胶囊居中**：`dockRow` 外层 `GeometryReader` 取实际可见尺寸，内容 HStack 在 `.fixedSize(horizontal: true)` + `.padding(.horizontal, 14)` 之后补 `.frame(minWidth: proxy.size.width, minHeight: proxy.size.height, alignment: .center)`。`minWidth` 让胶囊不足撑满面板时整行水平居中、超出时固有宽度胜出并左对齐向右横滑；`minHeight` 让 46pt 行内胶囊垂直居中、上下留白对称。面板宽度 `DashboardLayout.width = 400`，中心与面板中心一致；`dockHeight = 46` 与 `footerHeight` 常量口径不变，不影响面板高度。
- **「状态信息」副标题**：`DashboardSettingsView.swift:40` 为「选择仪表盘顶部显示的系统与电池时间信息。」，`AidenteL10n.swift:127` 英文值为 `Choose the system and battery readouts shown at the top of the dashboard.`。该卡只含 `showUptime` / `showTimeTillDischarge` 两个开关，对应 `DashboardPopoverView.swift:575-589` header 里的两行时间；卡片标题仍为「状态信息 / Status Information」。

**仪表盘结构与手势**

- **`DashboardPopoverView.swift` 结构**：`ForEach(visibleCards)` 统一渲染六张可编辑卡；`DashboardEditableCard` / `DashboardFooterMetrics` / `DashboardCardFrameKey` / `DashboardCardHitArea` 集中管理顺序、尺寸与命中区；footer 高度计入 `scrollHeight` / `totalHeight`，避免 dock 撑破 800 上限。排序用 `DragGesture` + `GeometryReader` 上报卡片 frame 到 `dashboardCards` 坐标空间，松手按落点写回顺序、拖动中高亮落点；编辑态由覆盖整卡的透明层独占按压，减号在最上层可点，无专属拖拽 icon。
- **常驻卡边界与整卡手势**：只有 `statusHero`（含充电上限滑杆）常驻，完全不进入编辑态（无减号、不参与排序）。`PopoverCompactCard` 的 `content.padding(13).background` 不提供 `.contentShape`，卡片顶部的 `Spacer()` / `VStack spacing` / padding 空白需显式命中形状；`editableCard` 非编辑态与编辑态共用 `DashboardCardHitArea`（14pt 连续圆角、四边内缩 2pt，与 `PopoverCardBackground` 圆角一致）。除边缘 2pt 外，非编辑态整卡 `.highPriorityGesture(LongPressGesture(0.5s, maximumDistance: 24))` 任意位置长按可进编辑态；编辑态整卡透明层 + `DragGesture(minimumDistance: 6)` 任意位置按住即可拖。六张非常驻卡全部走 `editableCard`；底部 20pt hover 热区不受影响。
- **hover 渐变带的绘制出口**：`AidenteTheme.swift` 的 `AidenteFooterHintSurface`（与 `AidenteChromeBar` / `AidenteMaterialLayer` 并列）只在 `if isFooterHovering` 里和文字一起出现：`clear → AidenteTheme.ocean.opacity(0.09 / 0.16)` 垂直渐变 + 底边 1pt 细线，`.allowsHitTesting(false)`，深浅色分别给 alpha；守单一绘制出口约定，L0–L3 固定色阶不变。`hoverHint` 为 `ZStack` 默认居中 + `.transition(.opacity)` + `onHover` 的 `withAnimation(0.15s)`；`LazyVStack` 下 padding 为 `isEditingCards ? 11 : 2`。渐变带与拖动落点高亮线为蓝色 `ocean`。

### 验证

- 全量 `swiftc -typecheck`（`Aidente/**/*.swift`，不产出二进制）在早期改动中均 Exit 0；后续改动直接以完整构建 Exit 0 验证。`Aidente/DefaultsKeys.swift`、`Aidente/Views/DashboardPopoverView.swift`、`Aidente/Views/AidenteTheme.swift`、`Aidente/Views/Settings/GeneralSettingsView.swift`、`Aidente/Views/Settings/DashboardSettingsView.swift`、`Aidente/Views/Settings/ChargingSettingsView.swift` 均通过。
- **预览构建（11-09，6.1.1 / 22）与发行构建（6.1.2 / 23）均通过**：`zsh BuildSupport/build_app.sh` 全部 Exit 0（预览日志 `/tmp/aidente-build-20261109{-1..9}.log`、发行日志 `/tmp/aidente-build-6.1.2.log`，单次约 22–24s）。`Dist/Aidente.app` 为 6.1.2 / Build 23，`codesign --verify --deep --strict` Exit 0（ad-hoc 签名，未公证）。最新产物字节核查：新串（`访问仪表盘`、`Aidente 仪表盘`、`选择仪表盘顶部显示的系统与电池时间信息。`、英文 `Choose the system and battery readouts shown at the top of the dashboard.`、`colorEnergyFlow`、`Color Energy Flow`、`Dashboard Access`、`Power Source`、`showBatteryHealthCard`、`dashboardCards`）均在；旧串（旧副标题、`dockGreen`、硬编码 `Capacity & Lifespan` / `Energy-Intensive Apps`）均为 0。`Aidente/` 下零警告，唯一警告来自第三方 `Vendor/Defaults/Sources/Defaults/SwiftUI.swift:229` 的 `onChange(of:perform:)` deprecated。
- **实机验收全部通过（无问题）**：本机（macOS 15.8.2）已核对上述仪表盘编辑态、dock 显隐/居中/横滑、整卡长按与拖动排序、hover 渐变带、命名统一、文案本地化与设置页迁移等全部改动。原待验收清单各项均通过——最大风险 `highPriorityGesture` 未吞掉卡片内 Picker / 四个养护按钮 / 三个保护按钮短按；「访问仪表盘」可打开独立窗口；六枚胶囊横滑、实色 `ocean` 配白字在深浅色下对比度与辨识度正常；「彩色能量流」移出后可从 dock 恢复且面板高度/滚动正常；编辑态整卡拖动落点与减号点击有效；hover 渐变带淡入淡出与 2pt↔11pt 切换面板高度无跳动；dock 仅剩 1–2 枚时居中、点掉一枚居中↔滚动切换无跳动或裁切；「已完成」padding 10pt 点击区够用；「状态信息」新副标题中英译文正确；dock 胶囊上下留白对称、与提示文字间距自然；六张非常驻卡任意位置（含标题行 Spacer/padding 空白）长按均进编辑态、边缘 2pt 不触发、容量卡 Picker 区域长按有效、Button/Picker 短按未被 contentShape 吞掉、实色蓝胶囊配白字可读性达标。
- **发行打包**：`zsh BuildSupport/make_dmg.sh` Exit 0，输出 `Dist/Aidente-6.1.2.dmg`（卷名 `Aidente 6.1.2 (build 23)`，3.6M），`hdiutil verify` 结果为 VALID；`Dist/Aidente.app` 主二进制约 7.8M，`Aidente.icns` 与 `BuildSupport/Aidente.icns` 一致。DMG 仍为 ad-hoc 签名，仅适合本机 / 受信分发。

## [6.1.1]-2026-11-07

### 修复

**编译与构建**

- **首次编译失败**：`@Observable` 展开报 `declaration name 'shouldNotifyObservers' is not covered by macro 'Observable'`。根因是 Swift 6.2.4 搭配 macOS 15.x SDK 的 Observation 宏缺陷，不是业务源码问题。`BuildSupport/build_app.sh` 从硬编码 `MacOSX15.5.sdk` 改为 `xcrun --sdk macosx --show-sdk-path` 动态取最新 SDK，部署目标仍保持 macOS 14.0。
- **`.app` 图标缩略图陈旧**：反复重建 bundle 后 Finder / IconServices 缓存未刷新。构建脚本末尾增加 `touch` 与 `lsregister -f` 重新登记。

**仪表盘显示与交互**

- **仪表盘显示开关无效果**：`showXXX` 偏好只被零引用的旧 `Aidente/Views/MenuBuilder.swift` 消费，实际面板 `DashboardPopoverView.swift` 没有读取。改为在真实仪表盘用 `@Default` 门控各区块，`showPowerDistribution` 默认值改为 `true` 以保持原有观感。
- **功率流图导线左右溢出**：面板加宽后两列节点仍贴齐卡片边缘，且导线端点插进已改为半透明的节点内。新增 `maxNodeGap = 72` 让两列整体居中，新增 `flowEndInset = 6` 让端点停在节点外侧，`wireInset` 随间距自适应防止导线反向；`.clipped()` 只加在 `Canvas` 上，避免裁掉节点阴影。
- **导线箭头未对齐**：箭头尖端原本绑在 `end.x - 1`，端点内缩后箭头悬在节点外。新增 `arrowTipX` 参数链（`body → drawFlows → 6 处 drawFlow`），尖端对齐右列节点左边缘，底边与线终点重叠 1pt。
- **快速连点状态栏图标导致仪表盘不渲染 / 位置漂移**：`togglePopover` 不防重入，原 `popover.isShown` 在显示/关闭动画期间不可靠。已新增主线程 `isPresenting` 过渡锁丢弃重复点击（`StatusBarManager.swift`）；该机制的载体随后随 NSPopover 弃用（见下条）由 `menuPanel.isVisible` 判断替代。

**外观与状态栏**

- **界面始终为暗色**：删除 4 处强制暗色（`DashboardPopoverView.swift` 的 `.preferredColorScheme(.dark)`、`StatusBarManager.swift` 两处与 `SettingsWindowController.swift` 一处的 `.darkAqua`），界面改为跟随系统外观（现为「外观」设置，见「新增」）；补齐 `AidenteChromeBar` 与 `PopoverCardBackground` 的浅色分支。
- **双屏时非活跃屏幕的状态栏图标不变淡**：`Aidente/StatusBarManager.swift` 把 `button.image = nil` 改为 `button.image = NSImage()` 空占位图。自定义 `NSHostingView` 原本不会触发系统的 inactive-display 变淡处理；多屏菜单栏是同一视图的 clone，不能靠自行判断活跃屏幕改透明度。
- **菜单栏弹窗顶部的系统箭头（chevron）无法消除**：`NSPopover` 的 `hasFullSizeContent = true` 在实机（含 `popover.appearance = nil`）均无效，箭头是 AppKit 强加的 chrome。最终弃用 `NSPopover`：主菜单改为复用既有 `AidentePreviewPanel` 无边框 `NSPanel`（borderless、透明背景、圆角 15、`.floating`），`presentMenuPanel` 按屏幕坐标把面板锚定到状态栏图标正下方（顶边固定 `buttonFrame.minY - 4`、随内容高度向下生长），外部点击（local + global 鼠标监听，排除状态栏按钮矩形防止「关闭→重开」翻转）与图标点击均可靠关闭。同时删除 `popover` 实例、`configurePopoverShell`、`preparePopoverContentIfNeeded`、`popoverDidShow/DidClose` 与 `NSPopoverDelegate` 协议；`togglePopover` / `showDashboardWindow` / `showPopoverForPreview` 全部改走 `menuPanel`，`applyContentHeight` 同步面板尺寸并重锚顶边。已实机确认尖尖彻底消失（`StatusBarManager.swift`）。

### 新增

**仪表盘功能与图标**

- **四个功能卡片显示开关**：容量与寿命趋势、当前耗电 App、快捷养护、自动保护。分别新增 `Defaults.Keys`、设置页「面板模块」开关与仪表盘条件渲染，默认全部开启；隐藏卡片后面板高度自动收缩。
- **状态栏电池图标重绘**：按 macOS 15 单色 template 风格绘制 —— 透明内部、`.primary` 描边与填充、右端凸起、反色的数字与充电标记；仅低电量与低电量模式使用状态色。
- **恢复仪表盘容器背景采样**：`StatusBarManager.swift` 三处 `makeDashboardRootView(canSampleBackdrop:)` 由 `false` 改回 `true`（主菜单无边框面板 / 独立主菜单窗口 / 预览面板），使 `usesBackdropMaterial` 生效、L0 走 `NSVisualEffectView(.popover, .behindWindow)`。设置窗口仍由 `SettingsView.swift` 强制 `false`，视觉无变化；`AidenteSettingsBackground` 与诊断读数不动。

**外观与材质**

- **「外观」卡片新增 自动 / 浅色 / 深色 分段控件**（全局生效）：新增 `AppAppearance` 枚举（auto / light / dark，默认 auto）与 `appAppearance` Defaults key，本地化补「外观模式 / 自动 / 浅色 / 深色」；SwiftUI 侧 `DashboardPopoverView` / `SettingsView` 根视图 `.preferredColorScheme`，AppKit 侧 `AidenteBackdropMaterial` 玻璃按 `appAppearance` 设 `NSAppearance`（`AidenteTheme.swift` 新增 `AppAppearance.nsAppearance` 扩展），独立主菜单窗口 / 预览面板 / 设置窗口同步设置 `window.appearance`。
- **仪表盘类液态玻璃材质（macOS 15 及更早）**：参考 `github.com/kubai087/glasswork` 的分层思路，只移植能用 SwiftUI 自绘的静态部分，不含真实折射与色散。`AidenteTheme.swift` 新增 `AidenteGlassTokens`（边缘光主旋钮 `0.20`、`rimWidth 40`，其余层按原型系数联动）与 `AidenteGlassOverlay`（边缘增厚 `RadialGradient`、内缩柔光、顶部高光、左上/右下 1pt 角向渐变描边）；`AidenteLevelSurface` 在 tint 之后叠该层，并以 `!AidenteReadability.supportsSystemMaterial` 保证 macOS 26+ 只走系统 `glassEffect`、不双份叠加；`.clipShape(shape)` 保留。blur / saturation / brightness 仍由系统材质决定、App 不可调；dispersion / 真折射未实现（需实时 backdrop 纹理与屏幕录制权限）。

### 变更

**界面材质与外观**

- **界面材质与外观**：材质由 macOS 决定，app 只承诺文字可读性，不再提供多档材质选择器；设置页为「外观」卡片（「自动 / 浅色 / 深色」分段控件 + 「始终使用不透明背景」开关），未恢复旧四档 Picker。
  - `Aidente/Views/AidenteTheme.swift`：`AidenteSurfaceTokens.color(_:scheme:)` 为固定中性色阶（亮 `#F4F5F6 / #F8F8F8 / #FCFCFC`，暗 `#232326 / #28282B / #2D2D31`，L1−L0、L2−L0 差值恒定）；`AidenteLevelSurface` 为唯一绘制入口，可采样背景且未被强制不透明时 L0 走真玻璃（macOS 26+ 用 `glassEffect(.regular)`，macOS 15 及更早用 `NSVisualEffectView(.popover, .behindWindow)` 叠加自绘玻璃近似层，见「新增」），设置窗口 / 系统「降低透明度」/ app「始终使用不透明背景」走实体；`glassTint` 亮 `white .14` / 暗 `rgb(30,30,34) .24`、`controlFill` 用于 L4 控件。
  - 容器能力用 SwiftUI Environment 标志 `aidenteCanSampleBackdrop` 表达：原 `NSPopover` 为 `true`，随 NSPopover 弃用（见「修复」）曾全部改为 `false`；本轮又把仪表盘的三个容器（菜单面板 / 独立窗口 / 预览面板）恢复为 `true`（见「新增」），设置窗口仍由 `SettingsView.swift` 保持 `false`。
  - 去噪：`AidenteCard` 去掉卡片阴影只留 1pt 中性描边；`SettingsView` 顶栏去阴影只留 1pt 底线；`DashboardPopoverView` 页眉 / 页脚透空，L0 玻璃直接透上来，只留 1pt 中性分隔线；`FooterButton` 用 `controlFill`（亮 `white .24` / 暗 `white .055`）。
  - 一次性迁移 `AidenteMigration.migrateMaterialPreferenceIfNeeded()`（旧 `interfaceMaterialStyle: solid` → 新 `forceOpaqueBackground` 开启）；诊断字段改为 `readabilityStrategy` / `readabilitySource` / `forceOpaqueBackground`。
- **header 时间串上移**：「系统运行时间」「电池剩余时间」从 `statusHero` 卡片移到 header 大标题下方，最终 **10 pt + `.secondary` 灰字**；`statusHero` 仅保留充放电状态行。header 主标题字号 20 pt、垂直 padding `top 10 / bottom 10` 不变。
- **右上角三个 `FooterButton`（刷新 / 设置 / 退出）图标改 `.secondary` 灰字**，与时间串同灰。
- **「外观」卡片副标题文案**：`AidenteReadabilityStrategy.detail` 的 `.compatible` 改为「macOS 26 以前的系统，仪表盘使用类液态玻璃材质；升级到 macOS 26+，自动使用系统液态玻璃材质。」，删去原「可采样桌面背景」这一尚未实机验证的断言；`.systemMaterial` 同步把「系统材质 / 自动采用」统一为「系统液态玻璃材质 / 自动使用」。中英双语各两句（共 4 条字符串），`.opaque` 文案与 badge 短标签不变。

**仪表盘与设置页**

- 仪表盘宽度 `408 → 400`（`DashboardLayout.width`）；高度上限 `DashboardLayout.maxHeight`  `720 → 800` （最大值而非固定值，超过滚动、不足取实际值）。
- **设置页「状态信息」卡重排**：电源来源 → 系统运行时间 → 电池剩余时间（原「剩余使用时间」改名，删除旧开关），本地化删「剩余使用时间」、补「电池剩余时间」。
- **删除设置页「高级」tab**：`SettingsTab` 移除 `advanced`，设置页现为 通用 / 仪表盘 / 充电管理 / 计划与自动化 / 诊断 / 关于 六项；原「高级」页功能（登录时启动、主菜单呼出等）移入「通用」tab（`SettingsView.swift` / `GeneralSettingsView.swift`）。
- 仪表盘指标行「温度」改名为「电池温度」。
- 状态栏电池图标尺寸：本体 `19 × 11`（`insideIcon` 整体 `27 × 13`），百分比字号 12 pt。
- 充电时功率流图仍使用 136 pt 三节点布局，超出上限允许滚动。

**应用图标**

- **应用图标按 Apple macOS 模板重制**：`BuildSupport/generate_icon.swift` 在 1024×1024 画布中把原 896pt 绘制空间（圆角底板 `insetBy(dx: 64, dy: 64)`）整体重映射到 824×824 居中框，即四边各留 100pt（Apple 模板比例），原绘制坐标一律不动；脚本经 `lockFocus()` 在 Retina 下按 2× 超采样输出 2048px PNG。`BuildSupport/Aidente.icns` 由标准 10 档 iconset（`icon_16x16.png` … `icon_512x512@2x.png`）重新 `iconutil -c icns` 生成，补齐此前缺失的 `ic10` 1024×1024 档（原 `ic14` 误放 512×512），各档均从 2048px 主图直接下采样。同一 alpha 边界口径下，含投影的可见边界由 488/512 ≈ 95.3% 收敛到 898/1024 ≈ 87.7%（圆角底板本体 824/1024 = 80.5%），不透明像素由 85.5% 降到 72.5%，解决启动台里图标比其它 App「大一圈」的观感；1024 档为原生分辨率而非从 512 放大。原文件备份于 `/tmp/Aidente.icns.bak-1794064487`。构建时仍由 `BuildSupport/build_app.sh:227` 拷入 bundle。

**原型与文档**

- **三份 HTML 原型对齐现行方案 + `new-glass.html` 改名 `gross-glass.html`**：以 `liquid-glass-proposal.html` 的定稿参数为基准，按「现状对齐」保留历史对照骨架与表格、不丢信息。`gross-glass.html`（原 `new-glass.html`）把「方案 A」一侧改为 6.1.1 真实状态：删除 L1 底栏节点与旧 `.footer` CSS、刷新 / 设置 / 退出三个 25×20 控件移到 header 右上角并新增 `.hdr-actions` / `.timestr`、补 `AidenteGlassTokens` 参数、更新层级表 / `CHANGES.a` / readout 文案；`readability-strategy.html` 把色阶 token 与 JS `LEVELS` 改为亮 `#F4F5F6 / #F8F8F8 / #FCFCFC`、暗 `#232326 / #28282B / #2D2D31`，并把提案中「未改动产品代码 / 未执行构建 / 不做 DMG / 不定新版本号 / 仪表盘不再透桌面」等过时结论就地更正。两份顶部均加「现行方案 · 6.1.1 / Build 22」横幅。遗留的 4 处旧文件名注释引用（`liquid-glass-proposal.html:9` 与 `AidenteTheme.swift:26 / 40 / 79`）已随后同步为 `gross-glass.html`（纯注释，未改逻辑）。随后按用户要求删去 `readability-strategy.html` 中已无用的部分：整节「09 实施步骤」（9 条已全部完成）、07 设置页信息架构表格的「改版前（历史）」列（改为现行 6.1.1 单列清单）；「10 验收标准 / 11 风险与边界」重编号为 09 / 10，横幅与 foot 的提案式措辞改为已落地表述，08 补上真实实现 `AidenteMigration.migrateMaterialPreferenceIfNeeded()`。交互原型与 01–06 决策依据保留，文件由 533 行收敛到 513 行、章节 01–10 连续。三份 HTML 均不参与构建，本轮未编译、未重出 DMG。
- **`liquid-glass-proposal.html` 补上 glasswork 来源链接**：lede 中的「glasswork」与「许可」条目均改为指向 `https://github.com/kubai087/glasswork` 的外链（`target="_blank" rel="noopener noreferrer"`），许可条目另补 `<code>github.com/kubai087/glasswork</code>` 明文仓库地址；新增 `a` / `a:hover` 样式（沿用 `--accent`、1pt 下划线、hover 降透明度）。MIT 可用与「macOS 壁纸素材 © Apple 不在许可内、原型背景为 CSS 自绘渐变」的说明保持不变。纯静态文档改动，不参与构建，未编译、未重出 DMG。
- **README 中文化 + 补 6.1.1 发行说明**：原英文 `README.md` 原样另存为 `README_en.md`；新的中文 `README.md` 按 app 内术语（巡航 / 补电 / 充电上限 / 高温保护 / 修复控制服务 / 仪表盘等）完整翻译，保留全部章节、代码块与链接，并在版本段落最前面补「版本 6.1.1（Build 22）」一节（依据 `[6.1.1]` 内容、参考 6.1 段落写法）。新建 `BuildSupport/release-notes-6.1.1.md`，沿用 `release-notes-6.1.md` 的「更新内容 / 安装与升级 / 验证范围」结构与面向用户的措辞；「安装与升级」如实写明当前只有本地 `Dist/Aidente-6.1.1.dmg`、尚未发布 GitHub Release，未编造 arm64 DMG / ZIP / `SHA256SUMS-6.1.1.txt`。纯文档改动，不参与构建，未编译、未重出 DMG、未提交 / 推送 / 打标签 / 发布 Release。

**版本与更新**

- **清理写死的旧版本兜底**：`AboutSettingsView.swift:200` 的 `appVersion` 与 `UpdateService.swift:224` 的 `currentVersion` 在 `Bundle.main` 读不到 `CFBundleShortVersionString` 时原回退为硬编码 `6.0.1`，现统一改为 `development`，与 `DiagnosticCenter.swift:291/294` 已有写法一致；版本真源从此只有 `BuildSupport/Info.plist`。`UpdateService.swift:454-461` 的 `runVersionSelfTest()` 中 `6.0.1` 等字符串是版本比较测试数据，按约定保留原值。正常 app bundle 读得到 6.1.1，兜底不生效；非 bundle 环境（SwiftUI 预览 / 单测 / 裸可执行文件）下 `versionComponents("development")` 会解析为 `[0]`，`isVersion` 因而把任何远端版本判为更新、User-Agent 变为 `Aidente/development`，该路径随后已加 gate 消除（见下条）。
- **彻底消除非发行构建的更新误报**：`UpdateService.swift` 新增 `private var verifiedBundleVersion: String?`，用现成的 `isStableNumericVersion` 校验 `CFBundleShortVersionString`，plist 缺失或值非法都返回 nil；`currentVersion` 仍回退 `development`，只供「关于」页徽章与 User-Agent 显示。`performCheck` 在 `--update-preview` 与 `isBusy` 之后加 gate：拿不到可信版本时自动检查静默跳过（不发请求、不改 phase、不弹提示），手动检查设 `.failed` 并弹出「无法读取当前应用版本，已跳过更新检查。」；版本比较改用 `localVersion` 而非 `currentVersion`。`fetchLatestRelease()` 与正式路径的 `presentUpdatePrompt` 都只在 `performCheck` 内，因此 gate 覆盖了手动检查、启动后检查与每 6 小时定时检查，四处 `User-Agent: Aidente/\(currentVersion)` 在 gate 之后的网络路径上已不可达。`--update-preview` 的显式调试预览保留在 gate 之前，不受影响。`xcrun swiftc -frontend -parse` 语法解析通过；已由本轮完整构建与重出 DMG 收口（见「构建与验证」）。

### 构建与验证

- **版本号升级到 6.1.1 / Build 22**：`BuildSupport/Info.plist`、`BuildSupport/ReaderInfo.plist` 的 `CFBundleShortVersionString` 与 `Aidente.xcodeproj/project.pbxproj` 六个构建配置的 `MARKETING_VERSION` 统一为 `6.1.1`；`CFBundleVersion` / `CURRENT_PROJECT_VERSION` 统一递增为 `22`。`AGENTS.md` 的当前版本声明同步更新。历史文档（`README.md`、`BuildSupport/release-notes-6.1.md`、`CODEX_HANDOFF.md`、`maintenance-test-notes.md`、`administrator-install-notes.md`）与 `UpdateService.swift` 里针对 6.1 的版本比较测试数据保留原值。已完整构建并输出 `Dist/Aidente-6.1.1.dmg`（6.1.1 / Build 22）；`[未发布]` 已归档为 `[6.1.1]`，发行说明见 `BuildSupport/release-notes-6.1.1.md`；未提交 / 推送 / 打标签 / 发布 Release。
- **编译警告**：现仅剩第三方 `Vendor/Defaults/Sources/Defaults/SwiftUI.swift:229` 的 `onChange(of:perform:)` 在 macOS 14 已弃用（上游代码，未改动，不影响产物）。`SystemAppearanceMonitor.currentSystemIsDark()` 原误标 `nonisolated` 却读取 main-actor 隔离的 `NSApp.effectiveAppearance`，产生两条 `main actor-isolated` 警告；已去掉多余的 `nonisolated` 并加注释说明隔离边界（保留供 KVO 回调使用的 `isDark(_:)` 的 `nonisolated`），运行时行为不变。修正后重新构建 Exit 0、该警告归零，耗时约 20 秒。`nm` 已确认 `AidenteGlassTokens` 相关符号进入可执行文件。
- **2026-11-08 完整构建与重出 DMG（收口本轮全部源码改动）**：`zsh BuildSupport/build_app.sh` Exit 0，日志中 `error:` 计数为 0，仅剩上游 `Vendor/Defaults/Sources/Defaults/SwiftUI.swift:229` 的 `onChange(of:perform:)` 弃用警告；`codesign --verify --deep --strict` 通过。产物 `Dist/Aidente.app` 的 `Info.plist` 为 6.1.1 / 22，`Aidente.icns` 与 `BuildSupport/Aidente.icns` 完全一致（702747 字节），体积 9.9M；`strings` 已确认本轮新增的 gate 提示文案进入可执行文件。`zsh BuildSupport/make_dmg.sh` Exit 0，重新生成 `Dist/Aidente-6.1.1.dmg`（3.5M，卷名 `Aidente 6.1.1 (build 22)`），`hdiutil verify` 结果为 VALID。上方各条中「本轮未编译 / 未重出 DMG」均为写该条当时的状态：三份 HTML 与 README / 发行说明不进入 bundle，两处 Swift 源码改动（硬编码兜底清理、更新检查 gate）已随本次构建进入产物。DMG 仍为 ad-hoc 签名，仅适合本机 / 受信分发；未提交 / 推送 / 打标签 / 发布 Release。
- **26+ 验证缺口**：类型检查与构建通过不能替代实机验收。当前实机 15.8.2 可验收仪表盘的 `.popover` 毛玻璃与自绘玻璃光效、设置页 / 仪表盘层级与「始终使用不透明背景」开关；macOS 26+ 的 `glassEffect` 系统材质、以及本轮「26+ 不叠自绘层」的分支表现，仍需在 26 环境实机核对。
