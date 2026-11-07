# 更新日志

记录 Aidente 的变更。格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，使用中文。

项目当前版本为 **6.1.1 / Build 22**。带版本号的发行说明见 `BuildSupport/release-notes-*.md`；下方 `[未发布]` 中的条目是尚未发行的本地改动，不代表已发行版本。

## [6.1.1]-2026-11-07

### 修复

- **首次编译失败**：`@Observable` 展开报 `declaration name 'shouldNotifyObservers' is not covered by macro 'Observable'`。根因是 Swift 6.2.4 搭配 macOS 15.x SDK 的 Observation 宏缺陷，不是业务源码问题。`BuildSupport/build_app.sh` 从硬编码 `MacOSX15.5.sdk` 改为 `xcrun --sdk macosx --show-sdk-path` 动态取最新 SDK，部署目标仍保持 macOS 14.0。
- **仪表盘显示开关无效果**：`showXXX` 偏好只被零引用的旧 `Aidente/Views/MenuBuilder.swift` 消费，实际面板 `DashboardPopoverView.swift` 没有读取。改为在真实仪表盘用 `@Default` 门控各区块，`showPowerDistribution` 默认值改为 `true` 以保持原有观感。
- **界面始终为暗色**：删除 4 处强制暗色（`DashboardPopoverView.swift` 的 `.preferredColorScheme(.dark)`、`StatusBarManager.swift` 两处与 `SettingsWindowController.swift` 一处的 `.darkAqua`），界面改为跟随系统外观（现为「外观」设置，见「新增」）；补齐 `AidenteChromeBar` 与 `PopoverCardBackground` 的浅色分支。
- **双屏时非活跃屏幕的状态栏图标不变淡**：`Aidente/StatusBarManager.swift` 把 `button.image = nil` 改为 `button.image = NSImage()` 空占位图。自定义 `NSHostingView` 原本不会触发系统的 inactive-display 变淡处理；多屏菜单栏是同一视图的 clone，不能靠自行判断活跃屏幕改透明度。
- **`.app` 图标缩略图陈旧**：反复重建 bundle 后 Finder / IconServices 缓存未刷新。构建脚本末尾增加 `touch` 与 `lsregister -f` 重新登记。
- **功率流图导线左右溢出**：面板加宽后两列节点仍贴齐卡片边缘，且导线端点插进已改为半透明的节点内。新增 `maxNodeGap = 72` 让两列整体居中，新增 `flowEndInset = 6` 让端点停在节点外侧，`wireInset` 随间距自适应防止导线反向；`.clipped()` 只加在 `Canvas` 上，避免裁掉节点阴影。
- **导线箭头未对齐**：箭头尖端原本绑在 `end.x - 1`，端点内缩后箭头悬在节点外。新增 `arrowTipX` 参数链（`body → drawFlows → 6 处 drawFlow`），尖端对齐右列节点左边缘，底边与线终点重叠 1pt。
- **快速连点状态栏图标导致仪表盘不渲染 / 位置漂移**：`togglePopover` 不防重入，原 `popover.isShown` 在显示/关闭动画期间不可靠。已新增主线程 `isPresenting` 过渡锁丢弃重复点击（`StatusBarManager.swift`）；该机制的载体随后随 NSPopover 弃用（见下条）由 `menuPanel.isVisible` 判断替代。
- **菜单栏弹窗顶部的系统箭头（chevron）无法消除**：`NSPopover` 的 `hasFullSizeContent = true` 在实机（含 `popover.appearance = nil`）均无效，箭头是 AppKit 强加的 chrome。最终弃用 `NSPopover`：主菜单改为复用既有 `AidentePreviewPanel` 无边框 `NSPanel`（borderless、透明背景、圆角 15、`.floating`），`presentMenuPanel` 按屏幕坐标把面板锚定到状态栏图标正下方（顶边固定 `buttonFrame.minY - 4`、随内容高度向下生长），外部点击（local + global 鼠标监听，排除状态栏按钮矩形防止「关闭→重开」翻转）与图标点击均可靠关闭。同时删除 `popover` 实例、`configurePopoverShell`、`preparePopoverContentIfNeeded`、`popoverDidShow/DidClose` 与 `NSPopoverDelegate` 协议；`togglePopover` / `showDashboardWindow` / `showPopoverForPreview` 全部改走 `menuPanel`，`applyContentHeight` 同步面板尺寸并重锚顶边。已实机确认尖尖彻底消失（`StatusBarManager.swift`）。

### 新增

- **四个功能卡片显示开关**：容量与寿命趋势、当前耗电 App、快捷养护、自动保护。分别新增 `Defaults.Keys`、设置页「面板模块」开关与仪表盘条件渲染，默认全部开启；隐藏卡片后面板高度自动收缩。
- **状态栏电池图标重绘**：按 macOS 15 单色 template 风格绘制 —— 透明内部、`.primary` 描边与填充、右端凸起、反色的数字与充电标记；仅低电量与低电量模式使用状态色。
- **「外观」卡片新增 自动 / 浅色 / 深色 分段控件**（全局生效）：新增 `AppAppearance` 枚举（auto / light / dark，默认 auto）与 `appAppearance` Defaults key，本地化补「外观模式 / 自动 / 浅色 / 深色」；SwiftUI 侧 `DashboardPopoverView` / `SettingsView` 根视图 `.preferredColorScheme`，AppKit 侧 `AidenteBackdropMaterial` 玻璃按 `appAppearance` 设 `NSAppearance`（`AidenteTheme.swift` 新增 `AppAppearance.nsAppearance` 扩展），独立主菜单窗口 / 预览面板 / 设置窗口同步设置 `window.appearance`。
- **仪表盘类液态玻璃材质（macOS 15 及更早）**：参考 `github.com/kubai087/glasswork` 的分层思路，只移植能用 SwiftUI 自绘的静态部分，不含真实折射与色散。`AidenteTheme.swift` 新增 `AidenteGlassTokens`（边缘光主旋钮 `0.20`、`rimWidth 40`，其余层按原型系数联动）与 `AidenteGlassOverlay`（边缘增厚 `RadialGradient`、内缩柔光、顶部高光、左上/右下 1pt 角向渐变描边）；`AidenteLevelSurface` 在 tint 之后叠该层，并以 `!AidenteReadability.supportsSystemMaterial` 保证 macOS 26+ 只走系统 `glassEffect`、不双份叠加；`.clipShape(shape)` 保留。blur / saturation / brightness 仍由系统材质决定、App 不可调；dispersion / 真折射未实现（需实时 backdrop 纹理与屏幕录制权限）。
- **恢复仪表盘容器背景采样**：`StatusBarManager.swift` 三处 `makeDashboardRootView(canSampleBackdrop:)` 由 `false` 改回 `true`（主菜单无边框面板 / 独立主菜单窗口 / 预览面板），使 `usesBackdropMaterial` 生效、L0 走 `NSVisualEffectView(.popover, .behindWindow)`。设置窗口仍由 `SettingsView.swift` 强制 `false`，视觉无变化；`AidenteSettingsBackground` 与诊断读数不动。

### 变更

- **界面材质与外观**：材质由 macOS 决定，app 只承诺文字可读性，不再提供多档材质选择器；设置页为「外观」卡片（「自动 / 浅色 / 深色」分段控件 + 「始终使用不透明背景」开关），未恢复旧四档 Picker。
  - `Aidente/Views/AidenteTheme.swift`：`AidenteSurfaceTokens.color(_:scheme:)` 为固定中性色阶（亮 `#F4F5F6 / #F8F8F8 / #FCFCFC`，暗 `#232326 / #28282B / #2D2D31`，L1−L0、L2−L0 差值恒定）；`AidenteLevelSurface` 为唯一绘制入口，可采样背景且未被强制不透明时 L0 走真玻璃（macOS 26+ 用 `glassEffect(.regular)`，macOS 15 及更早用 `NSVisualEffectView(.popover, .behindWindow)` 叠加自绘玻璃近似层，见「新增」），设置窗口 / 系统「降低透明度」/ app「始终使用不透明背景」走实体；`glassTint` 亮 `white .14` / 暗 `rgb(30,30,34) .24`、`controlFill` 用于 L4 控件。
  - 容器能力用 SwiftUI Environment 标志 `aidenteCanSampleBackdrop` 表达：原 `NSPopover` 为 `true`，随 NSPopover 弃用（见「修复」）曾全部改为 `false`；本轮又把仪表盘的三个容器（菜单面板 / 独立窗口 / 预览面板）恢复为 `true`（见「新增」），设置窗口仍由 `SettingsView.swift` 保持 `false`。
  - 去噪：`AidenteCard` 去掉卡片阴影只留 1pt 中性描边；`SettingsView` 顶栏去阴影只留 1pt 底线；`DashboardPopoverView` 页眉 / 页脚透空，L0 玻璃直接透上来，只留 1pt 中性分隔线；`FooterButton` 用 `controlFill`（亮 `white .24` / 暗 `white .055`）。
  - 一次性迁移 `AidenteMigration.migrateMaterialPreferenceIfNeeded()`（旧 `interfaceMaterialStyle: solid` → 新 `forceOpaqueBackground` 开启）；诊断字段改为 `readabilityStrategy` / `readabilitySource` / `forceOpaqueBackground`。
- 仪表盘宽度 `408 → 400`（`DashboardLayout.width`）；高度上限 `DashboardLayout.maxHeight`  `720 → 800` （最大值而非固定值，超过滚动、不足取实际值）。
- **header 时间串上移**：「系统运行时间」「电池剩余时间」从 `statusHero` 卡片移到 header 大标题下方，最终 **10 pt + `.secondary` 灰字**；`statusHero` 仅保留充放电状态行。header 主标题字号 20 pt、垂直 padding `top 10 / bottom 10` 不变。
- **右上角三个 `FooterButton`（刷新 / 设置 / 退出）图标改 `.secondary` 灰字**，与时间串同灰。
- **设置页「状态信息」卡重排**：电源来源 → 系统运行时间 → 电池剩余时间（原「剩余使用时间」改名，删除旧开关），本地化删「剩余使用时间」、补「电池剩余时间」。
- **删除设置页「高级」tab**：`SettingsTab` 移除 `advanced`，设置页现为 通用 / 仪表盘 / 充电管理 / 计划与自动化 / 诊断 / 关于 六项；原「高级」页功能（登录时启动、主菜单呼出等）移入「通用」tab（`SettingsView.swift` / `GeneralSettingsView.swift`）。
- 仪表盘指标行「温度」改名为「电池温度」。
- 状态栏电池图标尺寸：本体 `19 × 11`（`insideIcon` 整体 `27 × 13`），百分比字号 12 pt。
- 充电时功率流图仍使用 136 pt 三节点布局，超出上限允许滚动。
- **「外观」卡片副标题文案**：`AidenteReadabilityStrategy.detail` 的 `.compatible` 改为「macOS 26 以前的系统，仪表盘使用类液态玻璃材质；升级到 macOS 26+，自动使用系统液态玻璃材质。」，删去原「可采样桌面背景」这一尚未实机验证的断言；`.systemMaterial` 同步把「系统材质 / 自动采用」统一为「系统液态玻璃材质 / 自动使用」。中英双语各两句（共 4 条字符串），`.opaque` 文案与 badge 短标签不变。
- **应用图标按 Apple macOS 模板重制**：`BuildSupport/generate_icon.swift` 在 1024×1024 画布中把原 896pt 绘制空间（圆角底板 `insetBy(dx: 64, dy: 64)`）整体重映射到 824×824 居中框，即四边各留 100pt（Apple 模板比例），原绘制坐标一律不动；脚本经 `lockFocus()` 在 Retina 下按 2× 超采样输出 2048px PNG。`BuildSupport/Aidente.icns` 由标准 10 档 iconset（`icon_16x16.png` … `icon_512x512@2x.png`）重新 `iconutil -c icns` 生成，补齐此前缺失的 `ic10` 1024×1024 档（原 `ic14` 误放 512×512），各档均从 2048px 主图直接下采样。同一 alpha 边界口径下，含投影的可见边界由 488/512 ≈ 95.3% 收敛到 898/1024 ≈ 87.7%（圆角底板本体 824/1024 = 80.5%），不透明像素由 85.5% 降到 72.5%，解决启动台里图标比其它 App「大一圈」的观感；1024 档为原生分辨率而非从 512 放大。原文件备份于 `/tmp/Aidente.icns.bak-1794064487`。构建时仍由 `BuildSupport/build_app.sh:227` 拷入 bundle。

### 构建与验证

- **版本号升级到 6.1.1 / Build 22**：`BuildSupport/Info.plist`、`BuildSupport/ReaderInfo.plist` 的 `CFBundleShortVersionString` 与 `Aidente.xcodeproj/project.pbxproj` 六个构建配置的 `MARKETING_VERSION` 统一为 `6.1.1`；`CFBundleVersion` / `CURRENT_PROJECT_VERSION` 统一递增为 `22`。`AGENTS.md` 的当前版本声明同步更新。历史文档（`README.md`、`BuildSupport/release-notes-6.1.md`、`CODEX_HANDOFF.md`、`maintenance-test-notes.md`、`administrator-install-notes.md`）与 `UpdateService.swift` 里针对 6.1 的版本比较测试数据保留原值。已完整构建并输出 `Dist/Aidente-6.1.1.dmg`（6.1.1 / Build 22）；`[未发布]` 未归档、未新建 `release-notes-6.1.1.md`、未提交 / 推送 / 打标签 / 发布 Release。
- **编译警告**：现仅剩第三方 `Vendor/Defaults/Sources/Defaults/SwiftUI.swift:229` 的 `onChange(of:perform:)` 在 macOS 14 已弃用（上游代码，未改动，不影响产物）。`SystemAppearanceMonitor.currentSystemIsDark()` 原误标 `nonisolated` 却读取 main-actor 隔离的 `NSApp.effectiveAppearance`，产生两条 `main actor-isolated` 警告；已去掉多余的 `nonisolated` 并加注释说明隔离边界（保留供 KVO 回调使用的 `isDark(_:)` 的 `nonisolated`），运行时行为不变。修正后重新构建 Exit 0、该警告归零，耗时约 20 秒。`nm` 已确认 `AidenteGlassTokens` 相关符号进入可执行文件。
- **26+ 验证缺口**：类型检查与构建通过不能替代实机验收。当前实机 15.8.2 可验收仪表盘的 `.popover` 毛玻璃与自绘玻璃光效、设置页 / 仪表盘层级与「始终使用不透明背景」开关；macOS 26+ 的 `glassEffect` 系统材质、以及本轮「26+ 不叠自绘层」的分支表现，仍需在 26 环境实机核对。


