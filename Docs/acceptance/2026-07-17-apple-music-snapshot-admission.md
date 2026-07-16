# 2026-07-17 Apple Music 统一快照准入验收

## 目标

验证 Apple Music 的元数据、时间线、控制确认与异步封面结果都经过同一套准入规则；迟到或瞬时失败结果不得覆盖最近可信状态，控制后也不得发送可合并的重复 Apple Event。

## 实现

- 新增统一快照决策：接受、拒绝旧结果、同进程瞬时失败后重试。
- 先比较 `checkedAt`，旧快照直接拒绝且不取消已有重试。
- 最近可信快照为 `.ready`、候选属于同一进程且为 `.degraded` 时，按 `250ms`、`600ms`、`1.2s`、`2.4s` 有界重试。
- 只有真正接受的新快照才取消待执行重试；进程变化、权限错误和重试耗尽仍按真实状态降级。
- 控制确认发现权威元数据读取已在途时等待该读取并复用结果；没有读取在途时才主动读取轻量时间线。
- 汽水切换等待调整为 `200ms`，Apple Music 后台稳定播放切换等待调整为 `400ms`；快速抖动期间保持原来源。

## 动态结果

- 普通歌曲 `Fast Times - Sabrina Carpenter` 在顶屿中显示歌名、歌手、封面、进度和三项定向控制。
- 顶屿下一首成功切到 `skinny dipping - Sabrina Carpenter`，Apple Music 与岛内歌曲一致；封面随新曲更新。
- 暂停后岛内进度保持在 `1:36 / 2:57`，等待 3 秒没有继续推进；恢复播放后按钮立即切回暂停图标。
- 优化前，同一次播放控制诊断同时出现 `metadata` 和 `timeline` 读取。
- 优化后，`Bad for Business - Sabrina Carpenter` 暂停样本中：
  - `+4ms`：本地乐观 UI 发布暂停状态；
  - `+169ms`：定向控制完成；
  - `+184ms`：仅启动一次 `metadata` 权威读取；
  - 整个控制轨迹没有第二次 `timeline` 读取。
- 前台激活汽水后岛切到 `鲜牛奶 - Arboi氩男孩`，激活 Apple Music 后切到 `Bad for Business - Sabrina Carpenter`；两次均在 1 秒观察窗口内完成，控制目标与显示来源一致。

## 自动化与构建

- `swift test`：112 项通过。
- `swift build -c release`：通过。
- `git diff --check`：通过。
- `/Applications/顶屿.app` 重新打包安装，深度严格签名校验通过。

## 清理

- Apple Music 已退出。
- 汽水音乐已恢复播放，顶屿显示汽水歌曲与暂停按钮。
- “显示音乐诊断信息”已关闭，设置窗口已关闭。
- Computer Use 已执行 `js_reset`。
