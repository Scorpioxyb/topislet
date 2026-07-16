# 汽水无窗口控制调查

日期：2026-07-16

## 环境

- macOS：26.5.2
- 汽水音乐：2.9.1（build 1553）
- Bundle ID：`com.soda.music`
- 顶屿控制策略：汽水 PID 内唯一语义 AX 控件

## 复现

1. 保持汽水播放并关闭主窗口，不退出进程。
2. 确认前台应用为 Codex，汽水 `frontmost=false`。
3. 运行安装版 `--qishui-control-diagnostic`。

结果：

```text
accessibilityTrusted=true
manualAccessibilityEnabled=true
scanned=2
candidateCount=0
applicationChildren=1
attribute[AXWindows]=count:0,roles:
root[0]=role:AXMenuBar,children:7,traversal:7
```

汽水专属 MediaRemote 状态流仍存在，但 AX 播放控件随主窗口销毁，无法继续执行安全语义控制。

## 候选路径

| 路径 | 结果 | 决策 |
| --- | --- | --- |
| 应用菜单“显示汽水音乐” | 能恢复窗口，但汽水立即成为前台 | 拒绝 |
| `open -g -b com.soda.music` | 能恢复窗口，但汽水立即成为前台 | 拒绝 |
| 先隐藏汽水，再按压显示菜单 | 仍会取消隐藏并激活汽水 | 拒绝 |
| Dock 菜单 | 只有显示、隐藏、退出等系统项目，没有播放命令 | 不可用 |
| URL / AppleScript | `Info.plist` 没有公开 URL 类型，`sdef` 返回无字典 | 不可用 |
| 本地 IPC | 无外部可连接的 Unix/TCP 控制服务；Electron `transportPort` 只存在于汽水 renderer/preload 内 | 不可用 |
| MediaRemote client / player command | 历史抖音、QuickTime 回归已证明可能误控系统当前媒体 | 禁用 |

以上验证均未移动鼠标。测试后恢复 Codex 前台，并保留汽水可见主窗口。

## 结论

当前没有同时满足以下条件的无窗口恢复路径：

- 不激活汽水，不切换前台应用；
- 不发送全局媒体键或坐标事件；
- 只控制 `com.soda.music`，不会误控视频；
- 操作后恢复原来的无窗口状态。

因此本阶段不实现自动重开。顶屿在 `AXWindows=count:0` 时继续安全拒绝，并提示用户先显示或最小化汽水主窗口。唯一最小化标准窗口仍可后台临时恢复、执行控制后再最小化。

## 重启条件

汽水后续版本出现以下任一能力时重新评估：

- 官方 URL / Apple Event / XPC 控制契约；
- 不依赖系统当前媒体焦点的应用定向播放 API；
- 无窗口状态仍保留且可唯一验证的 AX 播放控件。
