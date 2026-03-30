# Local Packaging (macOS)

[English](../local-packaging.md) | [简体中文](./local-packaging.md)

本文介绍如何在本地构建并打包 Swooshy，生成可直接运行的 `.app`
应用包和可分发的 zip 压缩包。

## 前置条件

- macOS 14+
- Xcode 16+，或与 Swift 6.3 匹配的命令行工具

## 快速开始

在仓库根目录执行：

```bash
./scripts/package-macos-app.sh
```

脚本会完成以下工作：

1. 使用 SwiftPM 构建 release 可执行文件
2. 创建 `dist/Swooshy.app`
3. 将 SwiftPM 资源包拷贝进应用包
4. 应用 ad-hoc 签名，除非你显式关闭
5. 生成 `dist/Swooshy-macOS.zip`

## 运行打包后的应用

```bash
open dist/Swooshy.app
```

首次启动时，macOS 仍可能根据 Gatekeeper 和辅助功能权限设置弹出信任或授权提示。

## 脚本选项

你可以通过环境变量自定义打包行为：

- `PRODUCT_NAME`，默认值：`Swooshy`
- `BUILD_CONFIGURATION`，默认值：`release`
- `DIST_DIR`，默认值：`dist`
- `APP_NAME`，默认值：`Swooshy.app`
- `ZIP_NAME`，默认值：`Swooshy-macOS.zip`
- `APP_VERSION`，默认值：`0.1.0`
- `BUNDLE_ID`，默认值：`com.xiamiyu123.swooshy`
- `REQUIRE_APP_ICON`，默认值：`1`，若找不到应用图标则打包失败
- `SKIP_CODESIGN=1` 可跳过 ad-hoc 签名

示例：

```bash
APP_VERSION=0.2.0 BUNDLE_ID=com.example.swooshy ./scripts/package-macos-app.sh
```

## 更新 Launchpad 图标

Launchpad 读取的是 `/Applications` 中的应用包，而不是 `dist/` 目录里的构建结果。

如果本地打包后 Launchpad 中的图标看起来没有更新，可以替换已安装应用并重启 Dock：

```bash
rm -rf /Applications/Swooshy.app
cp -R dist/Swooshy.app /Applications/Swooshy.app
killall Dock
```

Dock 重启后，Launchpad 应该就会读取到新的应用图标。
