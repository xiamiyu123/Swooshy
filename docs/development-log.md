# Development Log

[English](./development-log.md) | [简体中文](./zh-CN/development-log.md)

This document records developer-facing launch switches and startup helpers used
for testing, debugging, and UI review.

## Special Launch Arguments

| Argument | Example | Effect |
| --- | --- | --- |
| `--reset-user-config` | `swift run Swooshy --reset-user-config` | Clears user preferences before launch, while preserving the explicit experimental browser-tab-close opt-in. Also clears persisted window constraint observations. |
| `--clear-cache` | `swift run Swooshy --clear-cache` | Clears persisted window constraint observations while preserving user preferences. |
| `--preview-hotkey-registration-failure` | `swift run Swooshy --preview-hotkey-registration-failure` | Opens Settings on the Shortcuts page and injects a temporary hotkey registration failure for visual review. This does not create a real system hotkey conflict and does not persist the failure state. |
| `--preview-update-available` | `swift run Swooshy --preview-update-available` | Opens Settings on the About page and forces the update card to show the "new update available" style, without comparing the current app version. |

For an installed app bundle, pass the same arguments through `open`:

```bash
open /Applications/Swooshy.app --args --preview-hotkey-registration-failure
open /Applications/Swooshy.app --args --preview-update-available
```

## Startup Debug Helpers

| Helper | Example | Effect |
| --- | --- | --- |
| `SWOOSHY_DEBUG_LOGS=1` | `SWOOSHY_DEBUG_LOGS=1 swift run Swooshy` | Force-enables debug logging for the launch. Logs are written to `~/Library/Logs/Swooshy/debug.log`. |
