# 汽水最小化控制不弹窗验收

日期：2026-07-20

## 问题

汽水音乐窗口最小化后，顶屿点击上一首、播放 / 暂停或下一首会短暂取消窗口最小化，导致汽水窗口弹出。根因是 `QishuiSemanticAXController` 在每次控制前后写入 `AXMinimized=false/true`。

## 修复

- 删除控制前临时取消最小化及控制后恢复最小化的路径。
- 缓存控件与重新发现控件统一经过语义健康门禁。
- 唯一且经过结构校验的最小化窗口允许直接执行 `AXPress`。
- 最小化状态下若控件树不可用则安全拒绝，不改变窗口状态。

## 自动化

```text
swift test: 151 passed, 0 failed
git diff --check: passed
```

测试覆盖唯一最小化窗口控件可直接复用，并确认普通可见性门禁仍拒绝未经健康校验的最小化候选。

## 安装版实机验收

前置状态：

```text
front=ChatGPT, sodaFront=false, minimized=true
```

| 操作 | 汽水结果 | 窗口结果 |
| --- | --- | --- |
| 上一首 | 歌曲切换到 `Lost Horizons` | `sodaFront=false`, `minimized=true` |
| 播放 / 暂停 | `isPlaying=true` 切换为 `false` | `sodaFront=false`, `minimized=true` |
| 下一首 | 歌曲切换到 `Nap Time` | `sodaFront=false`, `minimized=true` |

三次操作均由顶屿展开态按钮实际点击触发。原前台 App 全程保持 ChatGPT，鼠标测试后恢复到原位置；未发送系统全局媒体键，也未改写汽水窗口的最小化属性。
