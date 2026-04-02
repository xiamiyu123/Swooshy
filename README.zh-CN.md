# <img src="artwork/app-icon/AppIcon-1024.png" width="48" height="48" alt="Swooshy Icon" style="vertical-align: middle;"> Swooshy

[English](./README.md) | [简体中文](./README.zh-CN.md)

更轻量化，开源，可自定义的 macOS 触控板增强工具。

通过触控板手势和全局快捷键快速完成窗口操作。

- 通过辅助功能接口操作当前窗口
- Dock 区域与标题栏区域的触控板手势
- 多语言支持
- 自定义手势动作与快捷键

## 目录

- [操作方式](#操作方式)
- [安装与运行](#安装与运行)
- [权限与限制](#权限与限制)
- [与 Swish 的关系](#与-swish-的关系)
- [许可证](#许可证)

## 操作方式

Swooshy 通过**直觉化的双指手势**来管理窗口。所有手势都建立在两个特定的触发区域：**窗口标题栏** 和 **Dock 栏图标**。

<details open>
<summary><b>第一页：Dock 图标手势 - 切换同应用窗口</b></summary>

当鼠标悬停在 **Dock 上的应用图标** 时：

* **双指左滑 / 右滑**：在该应用的多个窗口之间快速前后切换。
* 适合 Finder、浏览器、编辑器等应用快速切换窗口。

<br>
<img src="docs/images/step1.jpg" width="600" alt="Dock 图标手势-切换同应用窗口" style="border-radius: 8px;">

</details>

<details>
<summary><b>第二页：Dock 图标手势 - 显示与隐藏</b></summary>

悬停在 **Dock 的应用图标** 上，使用触控板上下滑动：

* **双指下滑**：最小化该应用的一个可见窗口。
* **双指上滑**：恢复/拉起该应用的一个处于最小化状态的窗口。

<br>
<img src="docs/images/step4.jpg" width="600" alt="Dock 图标手势-最小化与恢复" style="border-radius: 8px;">

</details>

<details>
<summary><b>第三页：Dock 图标手势 - 捏合退出应用</b></summary>

悬停在 **Dock 的应用图标** 上，可直接用捏合手势结束该应用：

* **双指捏合**：退出当前应用。
* 这个动作针对的是应用本身，不只是关闭单个窗口。
* 若只想关闭单个窗口，可在设置中自定义修改。

<br>
<img src="docs/images/step5.jpg" width="600" alt="Dock 图标手势-捏合退出应用" style="border-radius: 8px;">

</details>

<details>
<summary><b>第四页：标题栏手势 - 快速全屏与快速最小化</b></summary>

将鼠标悬停在 **最前窗口的标题栏区域**，这里就是标题栏手势的触发带：

* **双指上滑**：让当前窗口填充整个屏幕可视区域。
* **双指下滑**：把当前窗口最小化到 Dock。
* 先把指针停在标题栏，再做手势，识别会更稳定。

<br>
<img src="docs/images/step2.jpg" width="600" alt="标题栏手势-触发区域与上下滑" style="border-radius: 8px;">

</details>

<details>
<summary><b>第五页：标题栏手势 - 左右贴靠窗口</b></summary>

将鼠标悬停在 **窗口标题栏区域**，使用左右滑动即可快速整理当前窗口布局：

* **双指左滑**：将当前窗口贴靠到屏幕左半边。
* **双指右滑**：将当前窗口贴靠到屏幕右半边。
* 适合和另一个窗口并排对照查看。

* **预览**：可以直观观察窗口贴靠后所处位置，对于部分有大小限制的应用，Swooshy可能出现预览错误，此时Swooshy将 **记忆** 错误窗口，并在下一次以此改进预览
<br>
<img src="docs/images/step3.jpg" width="600" alt="标题栏手势-左右贴靠窗口" style="border-radius: 8px;">

</details>

<details>
<summary><b>第六页：标题栏手势 - 角落贴靠模式</b></summary>

在标题栏或Dock上悬停后，你也可以进入专门的角落贴靠模式：

* **双指长按 `0.2s` 后再拖向角落**：进入角落贴靠模式。
* 在角落贴靠模式下向屏幕边缘滑动可以将应用停靠在屏幕四角
* 触发所需时长也可以稍后在 `Settings...` -> “高级设置”中自行调整。

<br>
<img src="docs/images/corner-snap-mode.gif" width="600" alt="标题栏手势-角落贴靠模式" style="border-radius: 8px;">

</details>

<details>
<summary><b>第七页：自定义设置与全局快捷键</b></summary>

如果你习惯使用键盘，Swooshy 也提供了全局快捷键；所有手势映射和快捷键都可以在菜单栏点击 `Settings...` 后自由录制和修改。

* **停靠左右屏**：`Control + Option + Command + 左/右方向键`
* **填充可视区域**：`Control + Option + Command + 上方向键 / C`
* **应用内窗口切换**：`Control + Option + Command + \``，配合 `Shift` 反向
* **关闭 / 最小化**：`Control + Option + Command + W / M`
* **退出当前应用**：`Control + Option + Command + Q`

</details>

## 安装与运行

运行条件：

- macOS 14 或更高版本
- 已授予辅助功能权限
- 如果通过 Homebrew 或 Release 安装，首次打开可能触发 Apple 安全警告，请先阅读 [遇到 Apple 安全警告时](#apple-security-warning)
- 本项目为开源软件，不会危害到您的电脑

### 使用 Homebrew 安装

如果你已经安装了 [Homebrew](https://brew.sh)，推荐优先使用：

```bash
brew tap xiamiyu123/swooshy
brew update
brew install --cask swooshy
```

安装完成后，可以直接从 Launchpad / Spotlight 启动 `Swooshy`，也可以执行：

```bash
open /Applications/Swooshy.app
```

如首次打开被阻止，请参考 [遇到 Apple 安全警告时](#apple-security-warning)。

### 从 Release 下载

1. 打开 [Releases](https://github.com/xiamiyu123/Swooshy/releases/latest) 页面
2. 下载最新版本的 `.zip` 安装包
3. 解压后将 `Swooshy.app` 拖到访达中的 `/Applications`（或`应用程序`）
4. 双击 `Swooshy.app` 启动

首次启动后，请按提示为 Swooshy 授予“辅助功能”权限。

<a id="apple-security-warning"></a>

### 遇到 Apple 安全警告时

如果你是通过 Homebrew 或 Release 下载的方式安装，首次打开时 macOS 可能会提示应用已被阻止或无法验证开发者身份，可以用下面两种方式放行。

#### 方式 A：命令行（推荐）

```bash
xattr -dr com.apple.quarantine /Applications/Swooshy.app
open /Applications/Swooshy.app
```

#### 方式 B：系统设置

1. 先尝试打开一次 `Swooshy.app`
2. 打开“系统设置” -> “隐私与安全性”
3. 滚动到页面底部，找到 Swooshy 被阻止的提示
4. 点击“仍要打开”，然后再次确认启动

### 从源码运行

在仓库根目录执行：

```bash
swift run
```

首次启动后，请按提示为 Swooshy 授予“辅助功能”权限。

### 本地打包 `.app`

在仓库根目录执行：

```bash
./scripts/package-macos-app.sh
```

此操作会在本地生成一个可直接打开的应用包，打包说明见 [docs/zh-CN/local-packaging.md](docs/zh-CN/local-packaging.md)。

## 权限与限制

- Swooshy 依赖 macOS 辅助功能接口来读取和移动窗口
- 某些应用可能不暴露可操作的窗口信息，或不允许被移动、缩放、关闭
- Dock 和标题栏手势依赖私有多点触控输入路径
- 当前版本主要聚焦于窗口操作效率，而不是完整的平铺窗口管理
- 这是一个轻量化的首发版本，优先保证常用路径顺手、稳定、可理解

## 与 Swish 的关系

Swooshy 受 Swish 的产品思路启发，但它是一个独立实现的开源项目，定位也更明确：

- 更轻量
- 更偏向菜单栏工具
- 更容易自行构建和修改
- 更强调“可自定义”的开源体验

为喜欢 Swish 交互方式，但追求更可自定义、更自由的用户打造。

## 项目结构

- [Sources/Swooshy/SwooshyApp.swift](Sources/Swooshy/SwooshyApp.swift)：应用入口
- [Sources/Swooshy/AppDelegate.swift](Sources/Swooshy/AppDelegate.swift)：生命周期与控制器装配
- [Sources/Swooshy/StatusBarController.swift](Sources/Swooshy/StatusBarController.swift)：菜单栏 UI 与动作入口
- [Sources/Swooshy/SettingsWindowController.swift](Sources/Swooshy/SettingsWindowController.swift)：设置窗口
- [Sources/Swooshy/WindowManager.swift](Sources/Swooshy/WindowManager.swift)：基于辅助功能接口的窗口读写
- [Sources/Swooshy/DockGestureController.swift](Sources/Swooshy/DockGestureController.swift)：Dock 与标题栏手势调度
- [Sources/Swooshy/GestureFeedbackController.swift](Sources/Swooshy/GestureFeedbackController.swift)：手势 HUD 提示
- [ATTRIBUTION.md](ATTRIBUTION.md)：参考项目与归因说明

## 开发说明

- `swift test`：运行测试
- `SWOOSHY_DEBUG_LOGS=1 swift run`：启动时强制开启调试日志
- `swift run Swooshy --reset-user-config`：启动前清空用户配置
- `open /Applications/Swooshy.app --args --reset-user-config`：已安装 `.app` 时以同样方式清空配置后启动
- 调试日志开启后会写入 `~/Library/Logs/Swooshy/debug.log`

## 许可证

本项目使用 GNU General Public License v3.0 许可证。

详见 [LICENSE](LICENSE) 与 [ATTRIBUTION.md](ATTRIBUTION.md)。

## 欢迎 PR、Issue 与二次开发

让 Swooshy 变得更好。

如果 Swooshy 帮到了你，欢迎点个 Star。

## AI 生成披露

这是一个 vibe-coded 项目。我在开发过程中大量使用了 AI，并随后进行人工测试、调整和清理。
