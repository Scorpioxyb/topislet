# 汽水逐字歌词时间轴只读探测

## 结论

当前汽水音乐 macOS 版本的可访问性树没有向顶屿暴露可用的逐字时间轴。不能据此断言汽水内部没有时间轴，只能确认当前外部 AX 接口没有提供。

## 探测范围

- 目标：运行中的 `com.soda.music`，主窗口歌词区域。
- 方法：现有 `QishuiProbe`，只读 AX，深度 14，单节点最多 220 个子节点，启用 `AXDOMClassList`，关闭系统扩展、CG 窗口、IPC 和静态资源扫描。
- 证据：`.build/qa/qishui-lyric-timestamp-probe-full.log`。
- 探测没有点击汽水播放、暂停、切歌，也没有读取账号、URL、网络或本地歌词缓存。

## 观察到的结构

```text
lyrics
└── paragraph (placeholder/light)
    └── line
        └── static text
```

AX 快照中可见歌词节点的类别包括 `lyrics`、`paragraph`、`line` 和 `AXStaticText`；`paragraph` 当前只出现 `placeholder` 或 `light` 类，文本通过 `AXValue` 暴露。相关节点的属性集合包含 `AXDOMClassList`、`AXDOMIdentifier`、`AXValue`、`AXFrame` 等通用信息。

## 未发现

在歌词节点及其属性名中未发现：

- 每字或每词子节点；
- `timestamp`、`start`、`end`、`progress`、`duration` 等时间字段；
- 可用于计算逐字进度的 `AXValue` 数值、时间范围或动画进度；
- 可供顶屿直接订阅的 timed-text 回调。

这解释了当前顶屿只能可靠地同步“active 歌词段落”，不能把汽水内部的逐字卡拉 OK 时间精确复制出来。

## 产品决策

build 114 的逐字高亮继续作为视觉回退：active 行变化由汽水 AX 驱动，当前行内部使用可见的逐字显色；它不冒充汽水真实的逐字时间轴。后续只有在取得明确时间字段或受支持的 timed-text 来源后，才切换为精确逐字同步。

final result: passed
