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

## Frame Readback Diagnostics

With debug logging enabled, anomalous frame writes schedule read-only AX and
fresh CGWindowList samples at approximately 0, 16, 50, 100, and 200 ms after the
write attempt finishes. Search for `Frame diagnostic` in the log. Each sample
records the actual elapsed time, read durations, and `subsequentWriteBatches`
for later Swooshy writes to that window. Sampling does not control docking.
AX reads run on a background task. AX and CG reads are sequential; the log also
records `writesDuringSample` to flag overlapping Swooshy writes.

AX and CG bounds are logged in global top-left-origin coordinates. The CG window
ID is pinned before writing using the AX window ID, a unique title within the
owning process, or unique pre-write bounds. Ambiguous matches stay unresolved;
a missing matched window is never replaced with another window. These reads
bypass the window-ordering cache. A newer anomaly for the same window replaces
its pending samples; disabling logging or shutting down stops sampling.
Matching also recognizes an AX title with the owning application's exact
` - Application Name` suffix omitted from the CG title. Chrome captions with
additional tab-group or memory annotations may match the CG title prefix only
when the owning PID and unique pre-write geometry also agree.

## Smooth Docking Confirmation

Each target state starts one operation. Repeated updates for the same target
reuse it; release awaits that result instead of writing again. There is no
idle docking loop. A finite eased transition is planned once on a target change;
intermediate frames do not recompute the layout or learn size bounds. The final
frame goes through the confirmation below. Completion leaves no animation task
polling or writing the same target.

Position and size writes are confirmed separately. Expansion moves first so
resizing uses the new origin; shrinking resizes before moving. Each phase reads
on absolute deadlines through 500 ms. When a CG window can be pinned, both AX
and its fresh CG bounds must agree on that component. Otherwise confirmation
requires separated, stable AX reads. These checks work with logging disabled.
A size constraint requires two separated requests with the same stable result;
the session then re-anchors that confirmed size. Missing or changing results
fail without learning bounds. Differences within one point are accepted.
AX calls can extend the elapsed time beyond those deadlines.

The persistence key and cache scopes remain unchanged. Cached minimum sizes
and confirmed maximum sizes apply throughout the operation, including release.
Legacy maximum bounds remain stored but are revalidated before limiting a new
request. Only a completed commit persists observations; accepted sizes remove
contradicted bounds across cached actions while preserving other bounds and
scopes. Superseding targets cancel old confirmations. Release-time failure does
not start another docking action, and restore teardown awaits the same operation
before finishing the session.

When `AXEnhancedUserInterface` is already enabled and the CG identity is pinned,
the operation reuses native AX transitions through the confirmed phases instead
of sending interpolated frames. Other windows use the finite Swooshy transition.
This attribute is not a documented animation API, and Swooshy does not enable
it. The session log records its value (`unknown` if unavailable) and the selected
`transition` (`nativeAX` or `interpolated`) for verification.
