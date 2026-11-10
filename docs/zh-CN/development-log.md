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

## 窗口回读诊断

开启调试日志后，窗口写入异常会在本次写入尝试结束后约 0、16、50、100、200ms
进行只读采样，同时读取 AX 和最新的 CGWindowList。搜索 `Frame diagnostic` 可查看
实际采样时间、读取耗时，以及期间 Swooshy 对同一窗口的后续写入次数
`subsequentWriteBatches`。采样不参与停靠决策。
AX 读取在后台任务中执行。AX 和 CG 是先后读取，日志同时通过 `writesDuringSample`
标明读取期间是否有 Swooshy 写入，便于识别采样受到的干扰。

AX 和 CG 边界统一采用屏幕左上角为原点的全局坐标。写入前通过 AX 窗口 ID、
同一进程内唯一标题或唯一的写入前边界匹配并固定 CG 窗口 ID。匹配不明确时记录
`unresolved`；已匹配窗口消失时不会改匹配其他窗口。采样不使用窗口排序缓存。
同一窗口出现新的异常时会替换尚未完成的采样；关闭日志或退出应用会停止采样。
匹配也支持 AX 标题比 CG 标题多出所属应用的完整 ` - 应用名` 后缀。
Chrome 标题还包含群组、内存等信息时，只允许在进程 PID 和唯一的写入前边界
也一致的情况下，用 CG 标题前缀完成匹配。

## 平滑停靠结果确认

每个目标状态只启动一个操作。重复更新相同目标时复用已有任务，松手等待该任务
的结果，不再重新写入。目标改变时只规划一次有限的渐进过渡，中间帧不重新计算
布局，也不学习尺寸边界；最后一帧按下述流程确认。到位后不再轮询或重复写入。

位置和尺寸分开写入并分别确认。扩张时先移动，确保缩放基于新位置；缩小时先改
尺寸再移动。每个阶段按绝对时间点回读，最长确认至 500ms。能够固定 CG 窗口
身份时，要求 AX 与该窗口的最新 CG 边界在对应分量上一致；无法匹配时，要求
间隔读取的 AX 结果稳定。这些确认不依赖调试日志开关。只有两次间隔尺寸请求
得到相同的稳定结果，才确认尺寸约束并重新贴边；回读缺失或变化时失败，不学习
边界。允许一像素点以内的误差。AX 调用本身可能使实际耗时超过这些时间点。

缓存存储键和作用域不变。缓存的最小尺寸与已确认的最大尺寸参与整个操作，松手
也继续使用。旧版最大尺寸边界保留在缓存中，但重新验证后才会限制新请求。
只有提交完成才持久化观察；实际接受的尺寸会移除各动作缓存中被反证的边界，
保留其他边界和作用域。目标改变会取消旧确认；松手失败不会另起整套停靠重试。
取消手势后的恢复也等待同一操作完成，再结束会话。

应用已开启 `AXEnhancedUserInterface` 且能够固定 CG 身份时，复用原生 AX 过渡，
按上述阶段确认，不再发送额外插值帧；其他窗口使用 Swooshy 的有限渐进过渡。
该属性不是有文档保证的动画接口，Swooshy 不会主动开启它。会话日志记录其实际值
（无法读取时为 `unknown`）和所选 `transition`（`nativeAX` 或 `interpolated`），
便于核实具体应用的表现。
