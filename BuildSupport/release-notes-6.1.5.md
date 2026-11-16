# Aidente 6.1.5 · Build 26

## 更新内容

### 界面材质与可读性

- **仪表盘卡片透出窗口玻璃**：普通卡片与 hero 渐变改为半透明绘制，透出窗口已采样的系统材质；填充透明度浅色 0.3 / 深色 0.4，系统开启「降低透明度」时自动回到不透明。浅色下彩色文字与小图标统一换用加深的 ink 色，保证玻璃上的对比度；进度条、渐变、徽章底等装饰色保持原色。
- **移除「始终使用不透明背景」开关**：界面材质完全跟随系统「降低透明度」，容器无法采样背景时自动降级为不透明，不再提供 App 内覆盖。

### 设置页窗口框架

- **改为 macOS 系统设置式无标题栏左右分栏**：删除横贯全宽的标题栏，侧栏、1pt 分界线、内容区从窗口顶部贯通到底；AppKit 交通灯定位到侧栏左上角（中心距顶 32pt、左缘 20pt），并用透明 titlebar accessory 保证点击热区。
- **左右分治**：左栏恒为玻璃（局部叠加系统材质与染色），右栏与卡片恒为实色；浅色下右栏底色改为略偏灰的 `#EDEEF0`，卡片用专用浅灰白 `#F5F5F7`，不再过白。
- **页头固定并简化为纯标题**：18pt 标题、文字中心距窗口顶 32pt，下方横线距中心 32pt，整块页头可拖动窗口。
- **页头新增前进 / 后退按钮**：标题左侧一对 chevron 导航按钮，带 tab 浏览历史栈——首次打开两按钮灰；切换 tab 后后退可用，后退后前进可用；从历史中间切新 tab 会截断前进分支。高亮方式与 macOS 系统设置一致：平时无底色，可用 = 图标加深，悬停时才出现卡片色圆角底。

## 安装与升级

适用于 Apple Silicon MacBook、macOS 14 及以上。下载 DMG 后将 Aidente.app 拖入「应用程序」；6.1.4 及以上也可通过应用内检查更新安装（更新源为 `nightfall-yl/Aidente` 的 GitHub Release）。

## 验证范围

`zsh BuildSupport/build_app.sh` 完整构建 Exit 0，`codesign` 报 `valid on disk` / `satisfies its Designated Requirement`；`zsh BuildSupport/test_charging.sh` 138 项充电 / 睡眠 / 固件 / 回滚 / 回读检查通过（本轮无充电策略改动，回归为纯逻辑确认）；`zsh BuildSupport/make_dmg.sh` Exit 0，输出 `Dist/Aidente-6.1.5.dmg`，`hdiutil verify` 结果为 VALID。bundle 内 `Info.plist` 为 **6.1.5 / 26**。

设置页窗口框架与页头导航按钮的交互项（交通灯点击、页头拖拽、前进 / 后退流转）在实机上以常规使用验证为准。
