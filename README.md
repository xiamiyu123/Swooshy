# Swooshy

更轻量化，开源，可自定义的macOS 触控板增强工具。

通过触控板手势和全局快捷键快速完成窗口操作

- 通过辅助功能接口操作当前窗口
- Dock 区域与标题栏区域的触控板手势
- 多语言支持
- 自定义手势动作与快捷键

## 默认手势

### Dock 手势

当鼠标悬停在 Dock 图标上时：

- 双指左滑：向前切换该应用窗口
- 双指右滑：向后切换该应用窗口
- 双指下滑：最小化该应用的一个可见窗口
- 双指上滑：恢复该应用的一个最小化窗口
- 双指捏合：退出该应用

### 标题栏手势

当鼠标悬停在最前窗口的标题栏区域时：

- 双指左滑：贴靠到左半屏
- 双指右滑：贴靠到右半屏
- 双指下滑：最小化当前窗口
- 双指上滑：填充整个屏幕
- 双指捏合：退出当前应用

以上映射都可以在 `Settings…` 中单独开启、关闭或改成别的动作。

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
brew install --cask swooshy
```

安装完成后，可以直接从 Launchpad / Spotlight 启动 `Swooshy`，也可以执行：

```bash
open /Applications/Swooshy.app
```

### 从 Release 下载

1. 打开 [Releases](https://github.com/xiamiyu123/Swooshy/releases/latest) 页面
2. 下载最新版本的 `.zip` 安装包
3. 解压后将 `Swooshy.app` 拖到 `/Applications`
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
2. 打开“系统设置” → “隐私与安全性”
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
此操作会在本地生成一个可直接打开的本地应用包

```bash
./scripts/package-macos-app.sh
```

打包说明见 [docs/local-packaging.md](docs/local-packaging.md)。

## 默认快捷键

- `Control + Option + Command + Left Arrow`：贴靠到左半屏
- `Control + Option + Command + Right Arrow`：贴靠到右半屏
- `Control + Option + Command + Up Arrow`：最大化到可视区域
- `Control + Option + Command + C`：填充整个屏幕
- `Control + Option + Command + M`：最小化到 Dock
- `Control + Option + Command + W`：关闭当前窗口
- `Control + Option + Command + Q`：退出当前应用
- `Control + Option + Command + \``：向前切换当前应用窗口
- `Control + Shift + Option + Command + \``：向后切换当前应用窗口

快捷键支持重新录制

## 使用方式

Swooshy 是一个纯菜单栏应用，不显示 Dock 图标。

启动后你可以这样使用它：

1. 点击菜单栏图标，直接触发窗口动作
2. 打开 `Settings…`，配置语言、快捷键和手势映射
3. 将鼠标移动到 Dock 图标上，配合双指手势操作对应应用
4. 将鼠标移动到最前窗口标题栏上，配合双指手势操作当前窗口

如果权限状态发生变化，也可以在菜单中手动刷新。

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

为喜欢 Swish 交互方式，但追求更可自定义，更自由的用户打造

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
- 调试日志开启后会写入 `~/Library/Logs/Swooshy/debug.log`

## 许可证

本项目使用 GNU General Public License v3.0 许可证。

详见 [LICENSE](LICENSE) 与 [ATTRIBUTION.md](ATTRIBUTION.md)。

## 欢迎PR与提出Issue，二次开发

让Swooshy变得更好
如果Swooshy帮到了你，请点击Star，谢谢喵💓
