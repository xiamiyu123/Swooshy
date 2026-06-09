# 开发日志

[English](../development-log.md) | [简体中文](./development-log.md)

这份文档记录面向开发、调试和 UI 审查使用的特殊启动参数与启动辅助开关。

## 特殊启动参数

| 参数 | 示例 | 作用 |
| --- | --- | --- |
| `--reset-user-config` | `swift run Swooshy --reset-user-config` | 启动前清空用户配置，但保留用户显式开启的实验性浏览器标签页关闭选项；同时清空已持久化的窗口约束观察缓存。 |
| `--clear-cache` | `swift run Swooshy --clear-cache` | 清空已持久化的窗口约束观察缓存，保留用户配置。 |
| `--preview-hotkey-registration-failure` | `swift run Swooshy --preview-hotkey-registration-failure` | 打开设置窗口并跳到“快捷键”页面，临时注入一个快捷键注册失败状态，方便检查红色叹号和 hover 提示样式。它不会制造真实系统快捷键冲突，也不会持久化失败状态。 |
| `--preview-update-available` | `swift run Swooshy --preview-update-available` | 打开设置窗口并跳到“关于”页面，强制让更新卡片显示“发现新版本”的样式，不受当前应用版本号影响。 |

如果要对已安装的 `.app` 使用同样参数，可以通过 `open` 传入：

```bash
open /Applications/Swooshy.app --args --preview-hotkey-registration-failure
open /Applications/Swooshy.app --args --preview-update-available
```

## 启动调试辅助开关

| 开关 | 示例 | 作用 |
| --- | --- | --- |
| `SWOOSHY_DEBUG_LOGS=1` | `SWOOSHY_DEBUG_LOGS=1 swift run Swooshy` | 启动时强制开启调试日志。日志会写入 `~/Library/Logs/Swooshy/debug.log`。 |
