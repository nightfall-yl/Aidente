# Aidente 6.1.6 · Build 27

## 更新内容

### 通用页重组

- **「语言」「外观」合并为「语言与外观」**：两张单行卡收成一张，卡头外置只有标题，语言 / 外观两行加分隔线。
- **卡序定稿**：语言与外观 → 菜单栏 → 登录时启动；「登录时启动」改用琥珀金配色。
- **「MagSafe 指示灯」移入充电管理页**（电池校准之后）：指示灯是充电状态机的可视化外设，写入与限充走同一后台服务，关闭「充电管理」时与电池校准 / 巡航 / 高温保护同族整卡隐藏。

### 窗口框架

- **几何微调**：交通灯中心距顶 30pt，主徽章 34px +「Aidente」18pt bold 中心线在交通灯下方 47pt（y=77）；右栏页头高 60pt，横线距标题中心 30pt。
- **深色模式窗口光圈**：窗口边缘 1pt 白色 20% 描边贴合 12pt 圆角；窗口与设置卡片圆角统一为 12pt。浅色模式不变。

### 修复

- **英文界面卡标题漏翻译**：「登录时启动」「菜单栏」「语言与外观」三张卡的英文词条缺失已补齐；Debug 构建中词典未命中会打日志警告，便于后续发现漏词条。

### 代码优化

- 删除旧 NSMenu 死链（约 870 行）及连带死代码：零引用默认 key、只写不读属性、零引用视图与常量、`ControlServiceRefreshPolicy`、更新模型死字段。
- 性能：DateFormatter 静态缓存、仪表盘卡片顺序解析记忆化、消除每次 SMC 刷新的无效字符串格式化。
- 样板收敛：`AidenteCapabilityGate`、`AidenteMenuOption.options(for:)`、卡片圆角单一常量。

充电策略核心无变化。

## 安装与升级

适用于 Apple Silicon MacBook、macOS 14 及以上。下载 DMG 后将 Aidente.app 拖入「应用程序」；6.1.5 及以上也可通过应用内检查更新安装（更新源为 `nightfall-yl/Aidente` 的 GitHub Release），升级全程免重新授权。

## 验证范围

`zsh BuildSupport/build_app.sh` 完整构建 Exit 0，`codesign` 报 `valid on disk` / `satisfies its Designated Requirement`；`zsh BuildSupport/test_charging.sh` 134 项充电 / 睡眠 / 固件 / 回滚 / 回读检查通过（本轮无充电策略改动，回归为纯逻辑确认）；`zsh BuildSupport/make_dmg.sh` Exit 0，输出 `Dist/Aidente-6.1.6.dmg`，`hdiutil verify` 结果为 VALID。bundle 内 `Info.plist` 为 **6.1.6 / 27**。

## SHA-256

| 文件 | SHA-256 |
| --- | --- |
| 见 `SHA256SUMS-6.1.6.txt` | 以发行资产为准 |
