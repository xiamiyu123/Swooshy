# Local Packaging (macOS)

This document explains how to build and package Swooshy locally into a runnable
`.app` bundle and a distributable zip archive.

## Prerequisites

- macOS 14+
- Xcode 16+ (or matching command line tools for Swift 6.3)

## Quick Start

From the repository root:

```bash
./scripts/package-macos-app.sh
```

The script will:

1. Build the release executable with SwiftPM.
2. Create `dist/Swooshy.app`.
3. Copy the SwiftPM resource bundle into the app package.
4. Apply an ad-hoc signature (unless disabled).
5. Generate `dist/Swooshy-macOS.zip`.

## Run The Packaged App

```bash
open dist/Swooshy.app
```

On first launch, macOS may still prompt for trust/permission depending on your
Gatekeeper and Accessibility settings.

## Script Options

You can customize packaging with environment variables:

- `PRODUCT_NAME` (default: `Swooshy`)
- `BUILD_CONFIGURATION` (default: `release`)
- `DIST_DIR` (default: `dist`)
- `APP_NAME` (default: `Swooshy.app`)
- `ZIP_NAME` (default: `Swooshy-macOS.zip`)
- `APP_VERSION` (default: `0.1.0`)
- `BUNDLE_ID` (default: `com.xiamiyu123.swooshy`)
- `REQUIRE_APP_ICON` (default: `1`, fail packaging when app icon is missing)
- `SKIP_CODESIGN=1` to skip ad-hoc signing

Example:

```bash
APP_VERSION=0.2.0 BUNDLE_ID=com.example.swooshy ./scripts/package-macos-app.sh
```

## Update Launchpad Icon

Launchpad reads the app bundle in `/Applications`, not `dist/`.

If your icon looks unchanged in Launchpad after local packaging, replace the
installed app and restart Dock:

```bash
rm -rf /Applications/Swooshy.app
cp -R dist/Swooshy.app /Applications/Swooshy.app
killall Dock
```

After Dock restarts, Launchpad should pick up the updated app icon.
